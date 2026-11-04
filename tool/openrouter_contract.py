"""Generate and verify the pinned OpenRouter OpenAPI inventory."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.request import Request, urlopen

from openapi_contract import schema_fields, validate_references

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / 'tool/contracts/openrouter/openapi.json'
SOURCE = 'https://openrouter.ai/openapi.json'
SHA256 = '08855d8f74f3f44be3b3007576d79aee13faa6ecf6fd5cd790fcd78b51e6a4fb'
SNAPSHOT_SHA256 = '1ad4d41351fb6342c8ff6270d457006f7cde7dc99fe93f0f3ad99c5534b73af9'
KEY_PATTERN = re.compile(r'sk-or-v1-[A-Za-z0-9_-]{8,}')


def redact_source_examples(value):
    if isinstance(value, str):
        return KEY_PATTERN.sub('[OPENROUTER_API_KEY_REDACTED]', value)
    if isinstance(value, list):
        return [redact_source_examples(item) for item in value]
    if isinstance(value, dict):
        return {key: redact_source_examples(item) for key, item in value.items()}
    return value


METHODS = {'get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'}
INTEGRATED = {('post', '/chat/completions'), ('post', '/responses'), ('post', '/images'), ('get', '/images/models'), ('get', '/images/models/{author}/{slug}/endpoints')}
CANONICAL = {
    'ChatRequest': {'model', 'messages', 'max_tokens', 'max_completion_tokens', 'tools', 'tool_choice', 'response_format', 'stream', 'stream_options'},
    'ResponsesRequest': {'model', 'input', 'instructions', 'max_output_tokens', 'tools', 'tool_choice', 'text', 'stream'},
}
FORWARDED = {
    'ChatRequest': {'modalities', 'cache_control', 'debug', 'deferred_tools', 'frequency_penalty', 'image_config', 'logit_bias', 'logprobs', 'metadata', 'min_p', 'models', 'parallel_tool_calls', 'plugins', 'prediction', 'presence_penalty', 'prompt_cache_key', 'prompt_cache_options', 'provider', 'reasoning', 'reasoning_effort', 'repetition_penalty', 'route', 'seed', 'service_tier', 'session_id', 'stop', 'stop_server_tools_when', 'temperature', 'top_a', 'top_k', 'top_logprobs', 'top_p', 'trace', 'user'},
    'ResponsesRequest': {'access_programs', 'background', 'cache_control', 'debug', 'deferred_tools', 'frequency_penalty', 'image_config', 'include', 'max_tool_calls', 'metadata', 'models', 'parallel_tool_calls', 'plugins', 'presence_penalty', 'prompt', 'prompt_cache_key', 'prompt_cache_options', 'provider', 'reasoning', 'route', 'safety_identifier', 'service_tier', 'session_id', 'stop', 'stop_server_tools_when', 'temperature', 'top_k', 'top_logprobs', 'top_p', 'trace', 'truncation', 'user'},
}
NOT_INTEGRATED = {'ChatRequest': set(), 'ResponsesRequest': {'modalities', 'previous_response_id', 'store'}}

# Every selected Image API field must be explicitly reviewed against the pin.
IMAGE_FIELDS = {
    'ImageGenerationRequest': {'aspect_ratio', 'background', 'input_references', 'model', 'n', 'output_compression', 'output_format', 'prompt', 'provider', 'quality', 'resolution', 'seed', 'session_id', 'size', 'stream', 'trace', 'user'},
    'ImageGenerationProviderPreferences': {'allow_fallbacks', 'ignore', 'only', 'options', 'order', 'sort'},
    'ImageGenerationResponse': {'created', 'data', 'usage'},
    'ImageGenerationUsage': {'cache_creation', 'completion_tokens', 'completion_tokens_details', 'cost', 'cost_details', 'is_byok', 'iterations', 'prompt_tokens', 'prompt_tokens_details', 'server_tool_use', 'service_tier', 'speed', 'total_tokens'},
    'ImageGenPartialImageEvent': {'b64_json', 'partial_image_index', 'type'},
    'ImageGenTextChunkEvent': {'phase', 'text', 'type'},
    'ImageGenCompletedEvent': {'b64_json', 'created', 'media_type', 'type', 'usage'},
    'ImageGenStreamErrorEvent': {'error', 'type'},
    'ImageStreamingResponse': {'data'},
    'ImageModelsListResponse': {'data'},
    'ImageModelEndpointsResponse': {'id', 'endpoints'},
    'ImageModelListItem': {'architecture', 'created', 'description', 'endpoints', 'id', 'name', 'supported_parameters', 'supports_streaming'},
    'ImageModelArchitecture': {'input_modalities', 'output_modalities'},
    'ImageEndpoint': {'allowed_passthrough_parameters', 'pricing', 'provider_name', 'provider_slug', 'provider_tag', 'supported_parameters', 'supports_streaming'},
    'ImagePricingEntry': {'billable', 'cost_usd', 'unit', 'variant'},
    'EnumCapability': {'type', 'values'},
    'RangeCapability': {'type', 'min', 'max'},
    'BooleanCapability': {'type'},
    'ContentPartImage': {'type', 'image_url'},
    'TraceConfig': {'generation_name', 'parent_span_id', 'span_name', 'trace_id', 'trace_name'},
}
IMAGE_NESTED_FIELDS = {
    ('ImageGenerationResponse', 'data', 'items'): {'b64_json', 'media_type'},
    ('ImageGenStreamErrorEvent', 'error'): {'code', 'message', 'param', 'type'},
    ('ContentPartImage', 'image_url'): {'url'},
}


def image_field_status(document):
    schemas = document['components']['schemas']
    result = {}
    for name, reviewed in IMAGE_FIELDS.items():
        actual = set(schemas[name].get('properties', {}))
        if actual != reviewed:
            raise ValueError(f'Unreviewed or stale {name} fields: {sorted(actual ^ reviewed)}')
        result[name] = {field: (
            'runtime-owned-stream' if name == 'ImageGenerationRequest' and field == 'stream' else
            'typed-request' if name == 'ImageGenerationRequest' else
            'typed-provider-construction' if name == 'ImageGenerationProviderPreferences' else
            'typed-usage' if name == 'ImageGenerationUsage' and field in {'prompt_tokens', 'completion_tokens', 'total_tokens', 'cost'} else
            'raw-preserved-usage' if name == 'ImageGenerationUsage' else
            'native-trace' if name == 'TraceConfig' else
            'native-reference' if name == 'ContentPartImage' else
            'typed-native-output'
        ) for field in sorted(actual)}
    nested = {}
    for path, reviewed in IMAGE_NESTED_FIELDS.items():
        schema = schemas[path[0]]['properties'][path[1]]
        if len(path) == 3:
            schema = schema[path[2]]
        actual = set(schema.get('properties', {}))
        if actual != reviewed:
            raise ValueError(f'Unreviewed or stale {".".join(path)} fields: {sorted(actual ^ reviewed)}')
        nested['.'.join(path)] = {field: 'typed-native-output' if path[0] != 'ContentPartImage' else 'native-reference' for field in sorted(actual)}
    unions = {
        'ImageStreamingResponse': {'ImageGenPartialImageEvent', 'ImageGenTextChunkEvent', 'ImageGenCompletedEvent', 'ImageGenStreamErrorEvent'},
        'CapabilityDescriptor': {'EnumCapability', 'RangeCapability', 'BooleanCapability'},
    }
    for name, reviewed in unions.items():
        value = schemas[name]['properties']['data']['anyOf'] if name == 'ImageStreamingResponse' else schemas[name]['oneOf']
        actual = {item.get('$ref', '').rsplit('/', 1)[-1] for item in value}
        if actual != reviewed or len(value) != len(reviewed):
            raise ValueError(f'Unreviewed or stale {name} union: {sorted(actual ^ reviewed)}')
    return result, nested


def json_text(value):
    return json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + '\n'


def build_inventory(document, source_sha=SHA256):
    validate_references(document)
    operations = []
    for path, item in sorted(document['paths'].items()):
        for method, operation in sorted(item.items()):
            if method not in METHODS:
                continue
            operations.append({
                'method': method.upper(), 'path': path,
                'operationId': operation.get('operationId'),
                'status': 'integrated-selected-behavior' if (method, path) in INTEGRATED else 'not-integrated',
                'pathParameters': item.get('parameters', []),
                'contract': operation,
            })
    components = {}
    for group, entries in sorted(document.get('components', {}).items()):
        if group == 'schemas':
            components[group] = {name: schema_fields(schema, document, expand_refs=False)
                                 for name, schema in sorted(entries.items())}
        else:
            components[group] = entries
    field_status = {}
    for schema in ['ChatRequest', 'ResponsesRequest']:
        fields = document['components']['schemas'][schema].get('properties', {})
        stale = (CANONICAL[schema] | FORWARDED[schema] | NOT_INTEGRATED[schema]) - fields.keys()
        if stale:
            raise ValueError(f'Stale {schema} dispositions: {sorted(stale)}')
        unreviewed = fields.keys() - CANONICAL[schema] - FORWARDED[schema] - NOT_INTEGRATED[schema]
        if unreviewed:
            raise ValueError(f'Unreviewed {schema} fields: {sorted(unreviewed)}')
        field_status[schema] = {name: ('canonical-runtime' if name in CANONICAL[schema] else
                                      'not-integrated' if name in NOT_INTEGRATED[schema] else 'selected-output-mode' if schema == 'ChatRequest' and name == 'modalities' else 'native-forward-preserved')
                                for name in sorted(fields)}
    image_status, image_nested = image_field_status(document)
    return {'source': {'url': SOURCE, 'sha256': source_sha, 'snapshotSha256': SNAPSHOT_SHA256, 'transformation': 'Credential-shaped example strings redacted; schema fields and constraints retained.', 'reviewed': '2026-11-04',
                       'license': 'MIT', 'snapshot': 'tool/contracts/openrouter/openapi.json'},
            'scope': 'All OpenAPI operations and components. Operation contracts and component field inventories retain references; the snapshot is authoritative for complete schemas and descriptions.',
            'verification': 'Offline schema inventory, not proof of upstream model support or live API behavior. Canonical fields are runtime owned with supported shapes and history bounds; native-forward-preserved fields pass through native options without claiming full orchestration or validation. Chat modalities use typed text/image selection with buffered completed image output and private replay; normalized audio and Responses modalities remain unsupported. Stateful Responses store:true and non-null previous_response_id are rejected. Dedicated Image API generation, native SSE and buffered fallback plus model/endpoint discovery are separate selected integrations; unknown capability variants remain opaque.',
            'operationCount': len(operations), 'pathCount': len(document['paths']),
            'operations': operations, 'components': components, 'requestFieldStatus': field_status,
            'imageFieldStatus': image_status, 'imageNestedFieldStatus': image_nested,
            'imageStreamingDocumentation': {'url': 'https://openrouter.ai/docs/guides/overview/multimodal/image-generation', 'detail': 'Official guide shows direct SSE event objects while the pinned OpenAPI describes a data envelope. The dedicated client accepts both, plus actual buffered JSON fallback; this is not Chat image streaming support.'}}


def render_reference(inventory):
    lines = ['# OpenRouter API inventory', '',
             f"Source: [OpenRouter OpenAPI]({SOURCE}), reviewed 2026-11-04, SHA-256 `{inventory['source']['sha256']}`. The source declares the MIT license.", '',
             f"The pinned schema describes {inventory['operationCount']} operations across {inventory['pathCount']} paths. Chat completions, Responses and the three dedicated Image API operations have selected integrations; other operations are inventoried and not integrated.", '',
             'The [machine-readable inventory](openrouter-api-inventory.json) records each operation, request, response, parameter and header contract, and each component field, union and constraint. Credential-shaped example values are redacted. Original-source and sanitized-snapshot hashes are separate. References point to the schema snapshot in `tool/contracts/openrouter/openapi.json`. A schema entry or native field forwarding does not establish supported runtime orchestration or model behavior.', '',
             'Run `python3 tool/openrouter_contract.py --check` offline to verify the snapshot and generated outputs. `--upstream` compares the current official document without updating any files. See `tool/contracts/openrouter/README.md` for attribution and source provenance.', '',
             'Chat `modalities` has selected normalized text/image support via typed options; image output uses completed JSON assistant messages, not undocumented streaming deltas. `image_config` is preserved as model-specific JSON. Audio output, streamed Chat images, and Responses modalities remain outside this integration. The dedicated Image API has separate typed request, discovery, SSE and buffered-fallback handling; endpoint paths use encoded model segments rather than following returned URLs. See [OpenRouter images](openrouter-images.md).', '',
             'The pinned OpenAPI wraps image SSE events in `data`; the [official image guide](https://openrouter.ai/docs/guides/overview/multimodal/image-generation) shows direct events. Both forms are handled, with a separate buffered JSON fallback. Offline fixtures do not establish live provider or model behavior.', '',
             '| Method | Path | Status |', '| --- | --- | --- |']
    lines.extend(f"| {op['method']} | `{op['path']}` | {op['status']} |" for op in inventory['operations'])
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--upstream', action='store_true')
    args = parser.parse_args()
    raw = CONTRACT.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != SNAPSHOT_SHA256:
        raise SystemExit('OpenRouter snapshot hash changed; review and update the pin before regenerating.')
    if args.upstream:
        request = Request(SOURCE, headers={'User-Agent': 'AgentWeave contract check'})
        with urlopen(request, timeout=45) as response:
            upstream = response.read()
        if hashlib.sha256(upstream).hexdigest() != SHA256:
            raise SystemExit('OpenRouter upstream changed; review source, dispositions and fixtures before updating the pin.')
        sanitized = json_text(redact_source_examples(json.loads(upstream))).encode()
        if hashlib.sha256(sanitized).hexdigest() != SNAPSHOT_SHA256:
            raise SystemExit('Sanitized upstream snapshot differs; review example transformation.')
        print('Current official source and redacted snapshot match their reviewed hashes.')
    inventory = build_inventory(json.loads(raw), SHA256)
    outputs = {ROOT / 'docs/openrouter-api-inventory.json': json_text(inventory),
               ROOT / 'docs/openrouter-api-reference.md': render_reference(inventory)}
    for path, expected in outputs.items():
        if args.check or args.upstream:
            if not path.exists() or path.read_text() != expected:
                raise SystemExit(f'Stale generated contract: {path.relative_to(ROOT)}')
        else:
            path.write_text(expected)
    print(f"OpenRouter contract: {inventory['operationCount']} operations; live behavior unverified.")


if __name__ == '__main__':
    main()
