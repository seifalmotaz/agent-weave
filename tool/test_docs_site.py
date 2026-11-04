"""Offline contract checks for canonical guide routing and generated output."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from mkdocs.config import load_config
from mkdocs.commands.build import build

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('docs_hook', ROOT / 'tool/docs_hook.py')
hook = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hook)


class DocumentationTest(unittest.TestCase):
    def test_canonical_links_keep_fragments_and_external_urls(self):
        text = ('[Update](docs/updating.md#releases) '
                '[Agent](AGENTS.md) [Web](https://example.com/docs/x.md)')
        self.assertEqual(hook.adapt_links(text, 'contributing.md'),
            '[Update](updating.md#releases) [Agent](agent-guide.md) '
            '[Web](https://example.com/docs/x.md)')

    def test_canonical_guides_are_present_and_searchable_in_project_site(self):
        with tempfile.TemporaryDirectory() as output:
            config = load_config(str(ROOT / 'mkdocs.yml'), site_dir=output)
            build(config)
            target = Path(output)
            for path in ['index.html', 'getting-started/serverpod/index.html',
                         'getting-started/dart/index.html', 'tools/index.html',
                         'providers/index.html', 'compatibility/index.html',
                         'documents/index.html', 'openrouter/index.html',
                         'together/index.html', 'together-options/index.html', 'together-chat-inventory.json',
                         'vercel-gateway/index.html', 'gateway-options/index.html', 'gateway-options-inventory.json',
                         'cloudflare/index.html', 'cloudflare-api-reference/index.html',
                         'cloudflare-api-inventory.json', 'openrouter-api-reference/index.html',
                         'openrouter-api-inventory.json', 'computer-use/index.html',
                         'computer-parameters/index.html', 'computer-api-inventory.json',
                         'ollama/index.html', 'ollama-parameters/index.html', 'ollama-api-inventory.json', 'dart-frog/index.html',
                         'anthropic/index.html', 'anthropic-parameters/index.html', 'anthropic-api-inventory.json', 'anthropic-computer/index.html', 'anthropic-computer-parameters/index.html', 'anthropic-computer-inventory.json', 'assets/styles.css', 'llms.txt']:
                self.assertTrue((target / path).is_file(), path)
            html = (target / 'index.html').read_text()
            self.assertIn('Your AI logic.', html)
            self.assertIn('getting-started/serverpod/', html)
            self.assertNotIn('href="/assets/', html)
            search = json.loads((target / 'search/search_index.json').read_text())
            locations = {doc['location'] for doc in search['docs']}
            self.assertIn('tools/', locations)
            self.assertIn('documents/', locations)
            self.assertIn('openrouter/', locations)
            self.assertIn('together/', locations)
            self.assertIn('together-options/', locations)
            self.assertIn('vercel-gateway/', locations)
            self.assertIn('gateway-options/', locations)
            self.assertIn('cloudflare/', locations)
            self.assertIn('cloudflare-api-reference/', locations)
            self.assertIn('openrouter-api-reference/', locations)
            self.assertIn('computer-use/', locations)
            self.assertIn('computer-parameters/', locations)
            self.assertIn('ollama/', locations)
            self.assertIn('ollama-parameters/', locations)
            self.assertIn('dart-frog/', locations)
            ollama = json.loads((target / 'ollama-api-inventory.json').read_text())
            self.assertEqual(len(ollama['paths']), 4)
            self.assertIn('ToolCallFunction', ollama['goSupplement'])
            self.assertIn('anthropic/', locations)
            self.assertIn('anthropic-parameters/', locations)
            self.assertIn('anthropic-computer/', locations)
            self.assertIn('anthropic-computer-parameters/', locations)
            anthropic = json.loads((target / 'anthropic-api-inventory.json').read_text())
            self.assertEqual(len(anthropic['dispositions']), 19)
            openrouter = json.loads((target / 'openrouter-api-inventory.json').read_text())
            self.assertEqual(openrouter['operationCount'], 146)
            cloudflare = json.loads((target / 'cloudflare-api-inventory.json').read_text())
            self.assertEqual(cloudflare['operationCount'], 82)
            self.assertEqual(len(cloudflare['modelSchemas']), 6)
            inventory = json.loads((target / 'together-chat-inventory.json').read_text())
            self.assertEqual(inventory['dispositions']['logprobs']['status'], 'typed-option')
            self.assertIn('architecture/', locations)
            self.assertIn('getting-started/serverpod/', locations)
            serverpod = (target / 'getting-started/serverpod/index.html').read_text()
            self.assertIn('AGENT_WEAVE_DEMO_MODE', serverpod)
            self.assertIn('../../assets/styles.css', serverpod)


if __name__ == '__main__':
    unittest.main()
