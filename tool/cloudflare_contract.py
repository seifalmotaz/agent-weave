"""Pin Cloudflare AI contracts and check generated operation/field inventories.

Offline by default. Refresh only with --extract /path/to/official/openapi.json;
review the source revision and dispositions before committing regenerated output.
"""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / 'tool/contracts/cloudflare'
REVISION = '193e683baba9c46b675d91c959c3b9a726b2d184'
SOURCE_URL = f'https://raw.githubusercontent.com/cloudflare/api-schemas/{REVISION}/openapi.json'
METHODS = {'get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace'}
IMPLEMENTED = {
    ('post', '/accounts/{account_id}/ai/run/{model_name}'): 'Native JSON/binary input and raw SSE; selected typed model helpers and single-call chat adapter.',
    ('post', '/accounts/{account_id}/ai/run'): 'Gateway JSON wrapper and raw JSON/binary result. Model/options remain provider-specific.',
    ('get', '/accounts/{account_id}/ai/models/schema'): 'Authenticated model-schema lookup with model query parameter.',
    ('get', '/accounts/{account_id}/ai/models/search'): 'Model search with caller-supplied repeated query parameters.',
}
MODEL_SOURCES = {
    'bge-input.json': 'https://developers.cloudflare.com/workers-ai/models/bge-base-en-v1.5/sync-input.json',
    'bge-output.json': 'https://developers.cloudflare.com/workers-ai/models/bge-base-en-v1.5/sync-output.json',
    'whisper-input.json': 'https://developers.cloudflare.com/workers-ai/models/whisper/schema-input.json',
    'whisper-output.json': 'https://developers.cloudflare.com/workers-ai/models/whisper/schema-output.json',
    'flux-input.json': 'https://developers.cloudflare.com/workers-ai/models/flux-1-schnell/schema-input.json',
    'flux-output.json': 'https://developers.cloudflare.com/workers-ai/models/flux-1-schnell/schema-output.json',
}


def resolve(document, reference):
    if not reference.startswith('#/'):
        raise ValueError(f'External reference requires review: {reference}')
    value = document
    for token in reference[2:].split('/'):
        value = value[token.replace('~1', '/').replace('~0', '~')]
    return value


def selected_path(path):
    return any(path == prefix or path.startswith(prefix + '/')
               for prefix in ['/accounts/{account_id}/ai', '/accounts/{account_id}/ai-gateway'])


def extract(document):
    """Keep every AI/Gateway path and the complete local reference closure."""
    paths = {key: value for key, value in document['paths'].items() if selected_path(key)}
    references = set()

    def visit(value):
        if isinstance(value, dict):
            if '$ref' in value and value['$ref'] not in references:
                references.add(value['$ref'])
                visit(resolve(document, value['$ref']))
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(paths)
    components = {}
    for reference in sorted(references):
        tokens = reference[2:].split('/')
        if len(tokens) != 3 or tokens[0] != 'components':
            raise ValueError(f'Unexpected reference needs extraction review: {reference}')
        group, name = (token.replace('~1', '/').replace('~0', '~') for token in tokens[1:])
        components.setdefault(group, {})[name] = resolve(document, reference)
    return {'openapi': document['openapi'], 'info': document['info'],
            'paths': paths, 'components': components}


def schema_fields(schema, document, path='$', required=None, ancestors=frozenset()):
    """Enumerate nested properties, unions, map values and recursive references."""
    if not isinstance(schema, dict):
        return [{'path': path, 'schema': schema}]
    summary = {key: value for key, value in schema.items()
               if key not in {'properties', 'items', 'allOf', 'anyOf', 'oneOf', 'not', 'additionalProperties', 'description', 'example', 'examples'}}
    if isinstance(schema.get('additionalProperties'), bool):
        summary['additionalProperties'] = schema['additionalProperties']
    row = {'path': path, **summary}
    if required is not None:
        row['requiredByParent'] = required
    rows = [row]
    if '$ref' in schema:
        reference = schema['$ref']
        if reference in ancestors:
            row['recursiveReference'] = True
        else:
            rows += schema_fields(resolve(document, reference), document,
                                  path + '/$ref', required, ancestors | {reference})
    for name, child in sorted(schema.get('properties', {}).items()):
        escaped = name.replace('~', '~0').replace('/', '~1')
        rows += schema_fields(child, document, path + '/properties/' + escaped,
                              name in schema.get('required', []), ancestors)
    for name in ['items', 'not', 'additionalProperties']:
        if isinstance(schema.get(name), dict):
            rows += schema_fields(schema[name], document, path + '/' + name, ancestors=ancestors)
    for union in ['allOf', 'anyOf', 'oneOf']:
        for index, child in enumerate(schema.get(union, [])):
            rows += schema_fields(child, document, f'{path}/{union}/{index}', ancestors=ancestors)
    return rows


def dereference(value, document):
    return resolve(document, value['$ref']) if '$ref' in value else value


def build_inventory(document):
    operations = []
    for path, item in sorted(document['paths'].items()):
        for method, operation in sorted(item.items()):
            if method not in METHODS:
                continue
            parameters = [dereference(p, document) for p in item.get('parameters', []) + operation.get('parameters', [])]
            request_body = dereference(operation.get('requestBody', {}), document)
            response_schemas = {}
            for code, raw in sorted(operation.get('responses', {}).items()):
                response = dereference(raw, document)
                response_schemas[code] = {
                    'headers': response.get('headers', {}),
                    'content': {mime: schema_fields(value.get('schema', {}), document)
                                for mime, value in sorted(response.get('content', {}).items())},
                }
            operations.append({
                'method': method.upper(), 'path': path,
                'operationId': operation.get('operationId'),
                'summary': operation.get('summary', ''),
                'status': 'integrated-selected-behavior' if (method, path) in IMPLEMENTED else 'not-integrated',
                'implementation': IMPLEMENTED.get((method, path), 'Inventoried only. No AgentWeave API or runtime behavior is claimed.'),
                'parameters': [{**{key: value for key, value in p.items() if key != 'schema'},
                                'schemaFields': schema_fields(p.get('schema', {}), document)} for p in parameters],
                'requestBodyRequired': request_body.get('required', False),
                'requestBodies': {mime: schema_fields(value.get('schema', {}), document)
                                  for mime, value in sorted(request_body.get('content', {}).items())},
                'responses': response_schemas,
            })
    models = []
    for name, url in MODEL_SOURCES.items():
        raw = (CONTRACT / name).read_bytes()
        models.append({'snapshot': name, 'sourceUrl': url,
                       'sha256': hashlib.sha256(raw).hexdigest(),
                       'versioning': 'Unversioned public documentation schema, reviewed 2026-11-04.',
                       'license': 'CC-BY-4.0', 'attribution': 'Cloudflare documentation; unmodified snapshot, field inventory generated by AgentWeave.',
                       'fields': schema_fields(json.loads(raw), {})})
    return {'source': {'url': SOURCE_URL, 'revision': REVISION, 'reviewed': '2026-11-04',
                       'license': 'BSD-3-Clause', 'snapshot': 'tool/contracts/cloudflare/openapi-ai.json'},
            'scope': 'All AI and AI Gateway management paths in the pinned OpenAPI, plus six selected public model schemas. Compatibility endpoints are documented separately and absent from this OpenAPI revision.',
            'verification': 'Offline source inventory and serialization fixtures, not live acceptance or exhaustive runtime support.',
            'operationCount': len(operations), 'operations': operations, 'modelSchemas': models,
            'documentationOnlyEndpoints': [
                {'method': 'POST', 'path': '/accounts/{account_id}/ai/v1/chat/completions', 'status': 'integrated-selected-behavior'},
                {'method': 'POST', 'path': '/accounts/{account_id}/ai/v1/responses', 'status': 'integrated-selected-behavior'},
                {'method': 'POST', 'path': '/accounts/{account_id}/ai/v1/messages', 'status': 'not-integrated'},
            ]}


def render_reference(inventory):
    lines = ['# Cloudflare API inventory', '',
             f"Source: [Cloudflare OpenAPI]({SOURCE_URL}), revision `{REVISION}`, reviewed 2026-11-04.", '',
             f"The pinned schema contains {inventory['operationCount']} operations across {len({op['path'] for op in inventory['operations']})} Workers AI and AI Gateway paths. Four operations have selected AgentWeave integrations. The rest remain explicitly unimplemented.", '',
             'Download the [machine-readable inventory](cloudflare-api-inventory.json) for nested request and response fields, unions, required flags, defaults, enum values and parameter constraints. These are specification entries, not claims that AgentWeave executes every option.', '',
             'Model documentation schemas are attributed to Cloudflare under CC BY 4.0, with unmodified snapshots and generated field inventories. The OpenAPI source is BSD-3-Clause. See the retained licenses and attribution in `tool/contracts/cloudflare/README.md`.', '',
             'The complete selected source schemas and BSD license are retained in `tool/contracts/cloudflare/`. Run `python3 tool/cloudflare_contract.py --check` offline. Refresh with `--extract /path/to/official/openapi.json` only after reviewing the revision and upstream changes. New operations receive `not-integrated` status automatically.', '',
             'See [Cloudflare usage](cloudflare.md) for auth, native model inputs, compatible protocols, cancellation and known limits.', '',
             '## OpenAPI operations', '', '| Method | Path | AgentWeave status |', '| --- | --- | --- |']
    for operation in inventory['operations']:
        lines.append(f"| {operation['method']} | `{operation['path']}` | {operation['status']} |")
    lines += ['', '## Compatible endpoints outside this specification', '',
              'The public [Gateway REST guide](https://developers.cloudflare.com/ai-gateway/usage/rest-api/) documents the following endpoints. Their request/response types are not in the pinned OpenAPI. Chat and Responses have separate offline continuation fixtures; Messages is not implemented. Model-specific feature availability still applies.', '',
              '| Method | Path | AgentWeave status |', '| --- | --- | --- |']
    for operation in inventory['documentationOnlyEndpoints']:
        lines.append(f"| {operation['method']} | `{operation['path']}` | {operation['status']} |")
    lines += ['', '## Selected public model schemas', '',
              'The inventory retains the full input/output JSON schema for BGE base English, Whisper and Flux Schnell. Public documentation URLs are unversioned. Each downloaded snapshot has a SHA-256 hash; they are not attributed to the OpenAPI Git revision.', '',
              '| Snapshot | Official source | SHA-256 |', '| --- | --- | --- |']
    for model in inventory['modelSchemas']:
        lines.append(f"| `{model['snapshot']}` | [Schema]({model['sourceUrl']}) | `{model['sha256']}` |")
    lines += ['', 'Whisper declares a binary-string input variant, but this schema does not establish an accepted REST Content-Type. The typed binary path has serialization tests only. Native `/run` model schemas vary; forwarding raw fields does not certify those models.', '',
              'Model schemas, Gateway request headers, Workers bindings, asynchronous batch APIs and compatible endpoints require separate reviews when the OpenAPI omits them. No live Cloudflare calls were made for this inventory.', '']
    return '\n'.join(lines)


def json_text(value):
    return json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extract', type=Path)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--upstream', action='store_true', help='Read current official source and report selected-contract drift without updating snapshots')
    args = parser.parse_args()
    snapshot = CONTRACT / 'openapi-ai.json'
    if args.extract:
        if args.check:
            parser.error('--extract and --check cannot be combined')
        snapshot.write_text(json_text(extract(json.loads(args.extract.read_text()))))
    document = json.loads(snapshot.read_text())
    if args.upstream:
        if args.extract:
            parser.error('--upstream and --extract cannot be combined')
        request = Request('https://raw.githubusercontent.com/cloudflare/api-schemas/main/openapi.json',
                          headers={'User-Agent': 'AgentWeave contract check'})
        with urlopen(request, timeout=45) as response:
            upstream = extract(json.load(response))
        if upstream != document:
            raise SystemExit('Cloudflare AI OpenAPI changed. Review the upstream revision, schemas, dispositions and fixtures before updating the pin.')
        for name, url in MODEL_SOURCES.items():
            request = Request(url, headers={'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json'})
            with urlopen(request, timeout=45) as response:
                current = json.load(response)
            if current != json.loads((CONTRACT / name).read_text()):
                raise SystemExit(f'Cloudflare model schema changed: {name}; review before replacing its snapshot.')
        print('Current official AI OpenAPI and selected model schemas match the reviewed snapshots.')
    # Re-extraction also checks that every stored reference resolves.
    extract(document)
    inventory = build_inventory(document)
    outputs = {ROOT / 'docs/cloudflare-api-inventory.json': json_text(inventory),
               ROOT / 'docs/cloudflare-api-reference.md': render_reference(inventory)}
    for path, expected in outputs.items():
        if args.check:
            if not path.exists() or path.read_text() != expected:
                raise SystemExit(f'Stale generated contract: {path.relative_to(ROOT)}')
        else:
            path.write_text(expected)
    print(f"Cloudflare contract: {inventory['operationCount']} operations, {len(inventory['modelSchemas'])} model schemas; live behavior unverified.")


if __name__ == '__main__':
    main()
