"""OpenRouter inventory and shared OpenAPI traversal regression tests."""
import json
import subprocess
import sys
import unittest
from pathlib import Path

from openapi_contract import resolve, schema_fields, validate_references
from openrouter_contract import CONTRACT, ROOT, build_inventory, redact_source_examples


class ContractTest(unittest.TestCase):
    def test_closure_escaping_cycles_and_invalid_references(self):
        doc = {'components': {'schemas': {'a/b~c': {'$ref': '#/components/schemas/a~1b~0c'}}}}
        self.assertEqual(validate_references(doc), {'#/components/schemas/a~1b~0c'})
        self.assertEqual(resolve({'items': ['x', 'y']}, '#/items/1'), 'y')
        for ref in ['https://example.test/a', '#/missing']:
            with self.assertRaises((ValueError, KeyError)):
                validate_references({'$ref': ref})

    def test_nested_openapi_31_fields(self):
        schema = {'$defs': {'a/b': {'oneOf': [False, {'type': 'string'}]}},
                  'prefixItems': [{'additionalProperties': False}],
                  'anyOf': [{'items': {'type': 'integer', 'minimum': 2}}]}
        rows = {row['path']: row for row in schema_fields(schema, {}, expand_refs=False)}
        self.assertEqual(rows['$/$defs/a~1b/oneOf/0']['schema'], False)
        self.assertFalse(rows['$/prefixItems/0']['additionalProperties'])
        self.assertEqual(rows['$/anyOf/0/items']['minimum'], 2)

    def test_unknown_operation_defaults_to_not_integrated(self):
        doc = json.loads(CONTRACT.read_text())
        doc['paths']['/new'] = {'get': {'responses': {}}}
        inventory = build_inventory(doc)
        self.assertEqual(next(op for op in inventory['operations'] if op['path'] == '/new')['status'], 'not-integrated')
        self.assertEqual(inventory['operationCount'], 147)

    def test_selected_chat_image_modes_are_distinct_from_raw_fields(self):
        inventory = build_inventory(json.loads(CONTRACT.read_text()))
        status = inventory['requestFieldStatus']
        self.assertEqual(status['ChatRequest']['modalities'], 'selected-output-mode')
        self.assertEqual(status['ChatRequest']['image_config'], 'native-forward-preserved')
        self.assertEqual(status['ResponsesRequest']['modalities'], 'not-integrated')

    def test_removed_request_field_requires_review(self):
        doc = json.loads(CONTRACT.read_text())
        del doc['components']['schemas']['ChatRequest']['properties']['modalities']
        with self.assertRaisesRegex(ValueError, 'Stale ChatRequest dispositions.*modalities'):
            build_inventory(doc)

    def test_new_request_field_requires_review(self):
        doc = json.loads(CONTRACT.read_text())
        doc['components']['schemas']['ChatRequest']['properties']['future_request_mode'] = {'type': 'string'}
        with self.assertRaisesRegex(ValueError, 'Unreviewed ChatRequest fields.*future_request_mode'):
            build_inventory(doc)

    def test_example_redaction_preserves_schema_fields(self):
        fake_key = 'sk-or-' + 'v1-' + ('0' * 64)
        source = {'type': 'string', 'example': fake_key,
                  'description': 'Example: ' + fake_key, 'nested': [fake_key],
                  'properties': {'api_key': {'type': 'string'}}}
        redacted = redact_source_examples(source)
        self.assertEqual(redacted['example'], '[OPENROUTER_API_KEY_REDACTED]')
        self.assertNotIn(fake_key, json.dumps(redacted))
        self.assertEqual(redacted['properties'], source['properties'])
        self.assertEqual(source['example'], fake_key)

    def test_offline_check_and_stale_detection(self):
        # Run against a disposable copy so the actual generated files remain untouched.
        import tempfile
        import shutil
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            shutil.copytree(ROOT / 'tool', root / 'tool', ignore=shutil.ignore_patterns('__pycache__'))
            (root / 'docs').mkdir()
            for name in ['openrouter-api-inventory.json', 'openrouter-api-reference.md']:
                shutil.copy(ROOT / 'docs' / name, root / 'docs' / name)
            command = [sys.executable, str(root / 'tool/openrouter_contract.py'), '--check']
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            (root / 'docs/openrouter-api-reference.md').write_text('stale')
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Stale generated contract', result.stderr)


if __name__ == '__main__':
    unittest.main()
