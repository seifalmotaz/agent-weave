"""Tests for selected Ollama source and nested schema inventory."""
import json
import unittest
from ollama_contract import CONTRACT, GO_SUPPLEMENT, HASHES, PATHS, build_inventory, digest
from openapi_contract import schema_fields


class OllamaContractTest(unittest.TestCase):
    def test_pinned_sources_and_operations(self):
        for name, expected in HASHES.items():
            self.assertEqual(digest((CONTRACT / name).read_bytes()), expected)
        inventory = build_inventory(json.loads((CONTRACT / 'openapi.json').read_text()))
        self.assertEqual(set(inventory['paths']), set(PATHS))
        self.assertTrue(all('disposition' in row for rows in inventory['schemas'].values() for row in rows))
        self.assertIn('tool_call_id', GO_SUPPLEMENT['Message'].split())
        self.assertIn('index', GO_SUPPLEMENT['ToolCallFunction'].split())
        self.assertIn('prompt_eval_cached_count', GO_SUPPLEMENT['Metrics'].split())

    def test_nested_unions_and_recursive_reference(self):
        doc = {'components': {'schemas': {'Node': {'type': 'object', 'properties': {
            'value': {'oneOf': [{'type': 'string'}, {'type': 'array', 'items': {'type': 'integer'}}]},
            'next': {'$ref': '#/components/schemas/Node'}}}}}}
        rows = schema_fields({'$ref': '#/components/schemas/Node'}, doc)
        self.assertTrue(any(r.get('recursiveReference') for r in rows))
        self.assertTrue(any(r['path'].endswith('/oneOf/1/items') and r['type'] == 'integer' for r in rows))
        with self.assertRaises((ValueError, KeyError)):
            schema_fields({'$ref': '#/missing'}, doc)

    def test_real_nested_fields_and_duration_union(self):
        inv = build_inventory(json.loads((CONTRACT / 'openapi.json').read_text()))
        paths = [row['path'] for row in inv['schemas']['ChatRequest']]
        self.assertTrue(any('/properties/messages/items/$ref/properties/images/items' in p for p in paths))
        self.assertTrue(any('/properties/keep_alive/oneOf/1' in p for p in paths))
        self.assertTrue(any('/properties/tools/items/$ref/properties/function' in p for p in paths))


if __name__ == '__main__':
    unittest.main()
