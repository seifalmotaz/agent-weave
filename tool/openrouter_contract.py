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
SHA256 = '07b8b1ac91ba9e522540417420cd74004db5246d5341e5c86d68443e4438af82'
SNAPSHOT_SHA256 = 'f98a4d86ca65ca36796b67dc693d62c15609e98bf1fd45bdfba8a04901e7ea2d'
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
INTEGRATED = {('post', '/chat/completions'), ('post', '/responses')}
CANONICAL = {
    'ChatRequest': {'model', 'messages', 'max_tokens', 'max_completion_tokens', 'tools', 'tool_choice', 'response_format', 'stream', 'stream_options'},
    'ResponsesRequest': {'model', 'input', 'instructions', 'max_output_tokens', 'tools', 'tool_choice', 'text', 'stream'},
}
FORWARDED = {
    'ChatRequest': {'cache_control', 'debug', 'deferred_tools', 'frequency_penalty', 'image_config', 'logit_bias', 'logprobs', 'metadata', 'min_p', 'models', 'parallel_tool_calls', 'plugins', 'prediction', 'presence_penalty', 'prompt_cache_key', 'prompt_cache_options', 'provider', 'reasoning', 'reasoning_effort', 'repetition_penalty', 'route', 'seed', 'service_tier', 'session_id', 'stop', 'stop_server_tools_when', 'temperature', 'top_a', 'top_k', 'top_logprobs', 'top_p', 'trace', 'user'},
    'ResponsesRequest': {'access_programs', 'background', 'cache_control', 'debug', 'deferred_tools', 'frequency_penalty', 'image_config', 'include', 'max_tool_calls', 'metadata', 'models', 'parallel_tool_calls', 'plugins', 'presence_penalty', 'prompt', 'prompt_cache_key', 'prompt_cache_options', 'provider', 'reasoning', 'route', 'safety_identifier', 'service_tier', 'session_id', 'stop', 'stop_server_tools_when', 'temperature', 'top_k', 'top_logprobs', 'top_p', 'trace', 'truncation', 'user'},
}
NOT_INTEGRATED = {'ChatRequest': {'modalities'}, 'ResponsesRequest': {'modalities', 'previous_response_id', 'store'}}


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
        unreviewed = fields.keys() - CANONICAL[schema] - FORWARDED[schema] - NOT_INTEGRATED[schema]
        if unreviewed:
            raise ValueError(f'Unreviewed {schema} fields: {sorted(unreviewed)}')
        field_status[schema] = {name: ('canonical-runtime' if name in CANONICAL[schema] else
                                      'not-integrated' if name in NOT_INTEGRATED[schema] else 'native-forward-preserved')
                                for name in sorted(fields)}
    return {'source': {'url': SOURCE, 'sha256': source_sha, 'snapshotSha256': SNAPSHOT_SHA256, 'transformation': 'Credential-shaped example strings redacted; schema fields and constraints retained.', 'reviewed': '2026-11-04',
                       'license': 'MIT', 'snapshot': 'tool/contracts/openrouter/openapi.json'},
            'scope': 'All OpenAPI operations and components. Operation contracts and component field inventories retain references; the snapshot is authoritative for complete schemas and descriptions.',
            'verification': 'Offline schema inventory, not proof of upstream model support or live API behavior. Canonical fields are runtime owned with supported shapes and history bounds; native-forward-preserved fields pass through options.extra without claiming orchestration or validation. Stateful Responses store:true and non-null previous_response_id are rejected.',
            'operationCount': len(operations), 'pathCount': len(document['paths']),
            'operations': operations, 'components': components, 'requestFieldStatus': field_status}


def render_reference(inventory):
    lines = ['# OpenRouter API inventory', '',
             f"Source: [OpenRouter OpenAPI]({SOURCE}), reviewed 2026-11-04, SHA-256 `{inventory['source']['sha256']}`. The source declares the MIT license.", '',
             f"The pinned schema describes {inventory['operationCount']} operations across {inventory['pathCount']} paths. Chat completions and Responses have selected integrations; all other operations are inventoried and not integrated.", '',
             'The [machine-readable inventory](openrouter-api-inventory.json) records each operation, request, response, parameter and header contract, and each component field, union and constraint. Credential-shaped example values are redacted. Original-source and sanitized-snapshot hashes are separate. References point to the schema snapshot in `tool/contracts/openrouter/openapi.json`. A schema entry or native field forwarding does not establish supported runtime orchestration or model behavior.', '',
             'Run `python3 tool/openrouter_contract.py --check` offline to verify the snapshot and generated outputs. `--upstream` compares the current official document without updating any files. See `tool/contracts/openrouter/README.md` for attribution and source provenance.', '',
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
