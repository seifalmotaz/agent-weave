"""Regression checks for the Cloudflare contract extractor and field inventory."""
import json
import unittest
from pathlib import Path

from cloudflare_contract import (CONTRACT, IMPLEMENTED, build_inventory, extract,
                                 resolve, schema_fields, selected_path)


class ContractTest(unittest.TestCase):
    def test_reference_closure_preserves_escaped_and_recursive_names(self):
        schema = {'openapi': '3.0.3', 'info': {}, 'paths': {
            '/accounts/{account_id}/ai/models/schema': {'get': {
                'responses': {'200': {'content': {'application/json': {
                    'schema': {'$ref': '#/components/schemas/a~1b~0c'}}}}}}},
            '/unrelated': {'get': {}}}, 'components': {'schemas': {
                'a/b~c': {'type': 'object', 'properties': {
                    'next': {'$ref': '#/components/schemas/a~1b~0c'}}},
                'unused': {'type': 'string'}}}}
        selected = extract(schema)
        self.assertEqual(len(selected['paths']), 1)
        self.assertEqual(set(selected['components']['schemas']), {'a/b~c'})
        rows = schema_fields({'$ref': '#/components/schemas/a~1b~0c'}, selected)
        self.assertTrue(any(row.get('recursiveReference') for row in rows))
        self.assertEqual(resolve(selected, '#/components/schemas/a~1b~0c')['type'], 'object')

    def test_nested_union_constraints_and_required_fields_are_inventoried(self):
        rows = schema_fields({'type': 'object', 'required': ['audio'], 'properties': {
            'audio': {'oneOf': [{'type': 'string', 'format': 'binary'},
                                {'type': 'array', 'maxItems': 100,
                                 'items': {'type': 'integer', 'minimum': 0, 'maximum': 255}}]},
            'pooling': {'type': 'string', 'enum': ['cls', 'mean'], 'default': 'mean'},
        }}, {})
        by_path = {row['path']: row for row in rows}
        self.assertTrue(by_path['$/properties/audio']['requiredByParent'])
        self.assertFalse(by_path['$/properties/pooling']['requiredByParent'])
        self.assertEqual(by_path['$/properties/audio/oneOf/1/items']['maximum'], 255)
        self.assertEqual(by_path['$/properties/pooling']['default'], 'mean')

    def test_root_paths_are_included_without_matching_unrelated_prefixes(self):
        for path in ['/accounts/{account_id}/ai', '/accounts/{account_id}/ai-gateway',
                     '/accounts/{account_id}/ai/new-endpoint']:
            self.assertTrue(selected_path(path))
        self.assertFalse(selected_path('/accounts/{account_id}/ai-search'))
        fields = schema_fields({'type': 'object', 'additionalProperties': False}, {})
        self.assertFalse(fields[0]['additionalProperties'])

    def test_external_and_unresolved_references_fail(self):
        for reference in ['https://example.test/schema.json', '#/missing']:
            with self.assertRaises((ValueError, KeyError)):
                schema_fields({'$ref': reference}, {})

    def test_pinned_operations_and_helper_schemas_have_explicit_status(self):
        inventory = build_inventory(json.loads((CONTRACT / 'openapi-ai.json').read_text()))
        self.assertEqual(inventory['operationCount'], 82)
        implemented = [op for op in inventory['operations'] if op['status'] != 'not-integrated']
        self.assertEqual(len(implemented), len(IMPLEMENTED))
        self.assertEqual(len(inventory['modelSchemas']), 6)
        for model in inventory['modelSchemas']:
            self.assertEqual(len(model['sha256']), 64)
            self.assertTrue(model['fields'])
        gateway = next(op for op in inventory['operations']
                       if op['path'].endswith('/ai/run') and op['method'] == 'POST')
        self.assertTrue(any(row['path'].endswith('/properties/cacheTtl')
                            for row in gateway['requestBodies']['application/json']))
        self.assertTrue(any(op['status'] == 'not-integrated' and '/billing/' in op['path']
                            for op in inventory['operations']))


if __name__ == '__main__':
    unittest.main()
