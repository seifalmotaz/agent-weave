"""Inventory selected Ollama OpenAPI schemas and check the pinned upstream sources."""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

from openapi_contract import schema_fields, validate_references

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / 'tool/contracts/ollama'
REVISION = 'e9fde36d75fea66579d84099956ce1430792737a'
SOURCE = 'https://raw.githubusercontent.com/ollama/ollama'
FILES = {'openapi.yaml': 'docs/openapi.yaml', 'types.go': 'api/types.go'}
HASHES = {'openapi.yaml': 'd8e08be41dd858c933c32bef5ee8d0c5faf7d7462069a49b368731cfbceaab03',
          'openapi.json': '99b395ad35ba04f11729da401e5a208e2564af8ad0786a1aa107f3935a5dae46',
          'types.go': '8e54520d34c312bb6adfccb652b0d1e18bb5c4cdb8ac2eb2eab0c065a508effa'}
PATHS = ['/api/chat', '/api/generate', '/api/embed', '/api/show']
SCHEMAS = ['ChatRequest', 'ChatResponse', 'ChatStreamEvent', 'ChatMessage',
           'ToolCall', 'ToolDefinition', 'GenerateRequest', 'GenerateResponse',
           'GenerateStreamEvent', 'EmbedRequest', 'EmbedResponse', 'ShowRequest',
           'ShowResponse', 'ModelOptions', 'ThinkValue', 'Thinking', 'TokenLogprob', 'Logprob']
# OpenAPI is incomplete; this reviewed supplement follows api/types.go and is
# bound to its byte snapshot by --upstream. It is not an independent schema.
GO_SUPPLEMENT = {
    'ChatRequest': 'runner truncate shift _debug_render_only',
    'GenerateRequest': 'runner truncate shift _debug_render_only',
    'EmbedRequest': 'runner',
    'ShowRequest': 'runner all_manifests system template options name',
    'Message': 'thinking tool_name tool_call_id',
    'ToolCall': 'id',
    'ToolCallFunction': 'index',
    'Tool': 'items',
    'ToolProperty': 'anyOf type items description enum properties required',
    'ToolFunctionParameters': 'type $defs items required properties',
    'ToolFunction': 'name description parameters',
    'Options': 'num_keep seed num_predict top_k top_p min_p typical_p repeat_last_n temperature repeat_penalty presence_penalty frequency_penalty stop',
    'Runner': 'num_ctx num_batch num_gpu main_gpu use_mmap num_thread draft_num_predict',
    'ShowResponse': 'thinking license modelfile parameters template system renderer parser template_source details messages remote_model remote_host model_info projector_info tensors capabilities voices manifests modified_at requires',
    'ModelDetails': 'parent_model format family families parameter_size quantization_level context_length embedding_length runner',
    'Tensor': 'name type shape',
    'ManifestSummary': 'digest runner format selected',
    'ChatResponse': 'model remote_model remote_host created_at message done done_reason _debug_info logprobs',
    'GenerateResponse': 'model remote_model remote_host created_at response thinking done done_reason context tool_calls _debug_info logprobs',
    'DebugInfo': 'rendered_template image_count',
    'Metrics': 'total_duration load_duration prompt_eval_count prompt_eval_cached_count prompt_eval_duration eval_count eval_duration',
}

def digest(data):
    return hashlib.sha256(data).hexdigest()


def disposition(schema, path):
    # Classification describes the intended access boundary, not model acceptance.
    if schema == 'ChatRequest' and path in ('$/properties/model', '$/properties/messages', '$/properties/tools', '$/properties/stream'):
        return 'runtime-owned-in-agent-chat'
    if schema in ('ChatMessage', 'ToolCall', 'ToolDefinition'):
        return 'runtime-mapped-for-agent-chat; other nested fields raw-native'
    if schema in ('ChatResponse', 'ChatStreamEvent'):
        return 'selected content and tool calls normalized; raw frames and terminal metadata retained in private provider output'
    return 'raw-native; no dedicated agent-runtime behavior claimed'


def build_inventory(document):
    validate_references(document)
    schemas = {}
    for name in SCHEMAS:
        rows = schema_fields(document['components']['schemas'][name], document)
        for row in rows:
            row['disposition'] = disposition(name, row['path'])
        schemas[name] = rows
    return {
        'source': {'revision': REVISION, 'license': 'MIT',
                   'files': {local: {'url': f'{SOURCE}/{REVISION}/{remote}',
                                      'sha256': digest((CONTRACT / local).read_bytes())}
                             for local, remote in FILES.items()},
                   'openapiJson': 'tool/contracts/ollama/openapi.json'},
        'scope': 'Selected official chat, generate, embed and show operations and related schemas; Go supplement records additional reviewed fields. Raw transport and runtime normalization are distinct; no model acceptance is implied.',
        'paths': {path: document['paths'][path] for path in PATHS},
        'schemas': schemas,
        'goSupplement': {name: [{'field': field, 'disposition': 'raw-native; no dedicated runtime behavior claimed'}
                                for field in fields.split()] for name, fields in GO_SUPPLEMENT.items()},
        'unsupported': ['Automatic agent execution for generate, embed and show',
                        'Dedicated normalized runtime events for every provider metadata field (raw frames and terminal metadata are retained privately)',
                        'Guaranteed model support for all options, tools, media or thinking'],
        'notes': {'images': 'Go ImageData is []byte; JSON image values are base64 strings.',
                  'toolCalls': 'id is optional; function.index is an integer and arguments is a JSON object. Source does not specify a general repeated-index fragment merge algorithm.',
                  'duration': 'keep_alive accepts numeric seconds or Go duration strings; negative is indefinite; zero unloads.',
                  'stream': 'Chat and generate stream newline-delimited JSON by default; embed and show return JSON.',
                  'embedInput': 'Go source accepts strings, arrays and multimodal text/image/audio maps; image/audio are base64 blobs. OpenAPI may lag.',
                  'cache': 'prompt_eval_cached_count is a response metric in Go types, not a documented prompt cache control.'}}


def render_reference(inv):
    return f'''# Ollama API parameter inventory

The [official OpenAPI]({SOURCE}/{REVISION}/docs/openapi.yaml) and [Go API types]({SOURCE}/{REVISION}/api/types.go) are pinned at `{REVISION}` under MIT. The [machine-readable inventory](ollama-api-inventory.json) records selected operations and nested schema fields, union shapes, and reviewed Go-only additions. The OpenAPI can lag the server types: for example, it omits message `thinking`, `tool_name`, `tool_call_id`, and tool call `id` and `function.index`. Neither source establishes model-specific support.

Agent chat owns model, messages, tools and stream construction and maps selected text and tool events. Raw native access handles other fields; agent chat retains raw frames, including logprobs, and terminal metadata in private provider output, without dedicated normalized events for every field. Generate, embed and show have no automatic agent execution. Check the implementation and tests for the actual extent of raw access; inventory is source coverage, not live verification.

Chat and generate stream **newline-delimited JSON**, not SSE; stream defaults to true. Embed and show return JSON. Image bytes are base64 strings in JSON. Go types allow embed input as text, batches, or multimodal text/image/audio maps; audio and image blobs are base64. The `format` union includes `json` or a JSON schema object; `think` is boolean or a model-defined string. `keep_alive` accepts seconds or a Go duration string; negative means keep loaded, zero unloads. Duration metrics are nanoseconds; `prompt_eval_cached_count` is a reported metric, not a cache setting.

Chat history may include assistant thinking, tool calls, tool result `tool_name` and `tool_call_id`. Tool-call `id` is optional; `function.index` is an integer and arguments are an object. Responses may contain part of a message; the pinned types do not define a universal merge rule for repeated call fragments. Preserve raw events and avoid assuming that a repeated index always represents an appendable delta.

Run `python3 tool/ollama_contract.py --check` offline; `--upstream` compares the official current source bytes without changing the pin. The OpenAPI JSON snapshot is a parsed representation of the retained YAML. Review both source diffs, update the JSON snapshot, fixtures and dispositions before refreshing. No model download or live model call is required.
'''


def json_text(value):
    return json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--upstream', action='store_true')
    args = parser.parse_args()
    for name, expected in HASHES.items():
        if digest((CONTRACT / name).read_bytes()) != expected:
            raise SystemExit(f'Ollama pinned source changed: {name}; review and update its hash.')
    if args.upstream:
        for local, remote in FILES.items():
            request = Request(f'{SOURCE}/main/{remote}', headers={'User-Agent': 'AgentWeave contract check'})
            with urlopen(request, timeout=45) as response:
                current = response.read()
            if current != (CONTRACT / local).read_bytes():
                raise SystemExit(f'Ollama upstream changed: {remote}; review source, schema and fixtures before repinning.')
        print('Current Ollama sources match the pinned snapshots.')
    inventory = build_inventory(json.loads((CONTRACT / 'openapi.json').read_text()))
    outputs = {ROOT / 'docs/ollama-api-inventory.json': json_text(inventory),
               ROOT / 'docs/ollama-parameters.md': render_reference(inventory)}
    for path, expected in outputs.items():
        if args.check:
            if not path.exists() or path.read_text() != expected:
                raise SystemExit(f'Stale generated contract: {path.relative_to(ROOT)}')
        else:
            path.write_text(expected)
    print(f'Ollama contract: {len(PATHS)} paths, {len(SCHEMAS)} schemas; live behavior unverified.')


if __name__ == '__main__':
    main()
