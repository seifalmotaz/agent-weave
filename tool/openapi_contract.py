"""Shared OpenAPI reference and field inspection helpers."""

def resolve(document, reference):
    if not reference.startswith('#/'):
        raise ValueError(f'External reference requires review: {reference}')
    value = document
    for token in reference[2:].split('/'):
        token = token.replace('~1', '/').replace('~0', '~')
        value = value[int(token)] if isinstance(value, list) else value[token]
    return value


def schema_fields(schema, document, path='$', required=None, ancestors=frozenset(), expand_refs=True):
    """Enumerate nested properties, unions, map values and recursive references."""
    if not isinstance(schema, dict):
        return [{'path': path, 'schema': schema}]
    summary = {key: value for key, value in schema.items()
               if key not in {'properties', 'items', 'allOf', 'anyOf', 'oneOf', 'not', 'additionalProperties', 'prefixItems', '$defs', 'description', 'example', 'examples'}}
    if isinstance(schema.get('additionalProperties'), bool):
        summary['additionalProperties'] = schema['additionalProperties']
    row = {'path': path, **summary}
    if required is not None:
        row['requiredByParent'] = required
    rows = [row]
    if '$ref' in schema:
        reference = schema['$ref']
        if not expand_refs:
            resolve(document, reference)
        elif reference in ancestors:
            row['recursiveReference'] = True
        else:
            rows += schema_fields(resolve(document, reference), document,
                                  path + '/$ref', required, ancestors | {reference}, expand_refs)
    for name, child in sorted(schema.get('properties', {}).items()):
        escaped = name.replace('~', '~0').replace('/', '~1')
        rows += schema_fields(child, document, path + '/properties/' + escaped,
                              name in schema.get('required', []), ancestors, expand_refs)
    for name in ['items', 'not', 'additionalProperties']:
        if isinstance(schema.get(name), dict):
            rows += schema_fields(schema[name], document, path + '/' + name, ancestors=ancestors, expand_refs=expand_refs)
    for union in ['allOf', 'anyOf', 'oneOf']:
        for index, child in enumerate(schema.get(union, [])):
            rows += schema_fields(child, document, f'{path}/{union}/{index}', ancestors=ancestors, expand_refs=expand_refs)
    for index, child in enumerate(schema.get('prefixItems', [])):
        rows += schema_fields(child, document, f'{path}/prefixItems/{index}', ancestors=ancestors, expand_refs=expand_refs)
    for name, child in sorted(schema.get('$defs', {}).items()):
        escaped = name.replace('~', '~0').replace('/', '~1')
        rows += schema_fields(child, document, path + '/$defs/' + escaped, ancestors=ancestors, expand_refs=expand_refs)
    return rows



def validate_references(document):
    """Check every local reference, including cycles, without expanding schemas."""
    seen = set()
    def visit(value):
        if isinstance(value, dict):
            if '$ref' in value and value['$ref'] not in seen:
                reference = value['$ref']
                seen.add(reference)
                visit(resolve(document, reference))
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)
    visit(document)
    return seen
