"""Use canonical repository guides as virtual MkDocs pages, without copies."""
import re
from pathlib import Path
from mkdocs.structure.files import File

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    **{path.name: path for path in (ROOT / 'docs').glob('*.md')},
    'getting-started/serverpod.md': ROOT / 'examples/serverpod/README.md',
    'contributing.md': ROOT / 'CONTRIBUTING.md',
    'agent-guide.md': ROOT / 'AGENTS.md',
}


def adapt_links(content, destination):
    """Canonical guides share root-level routes in the documentation site."""
    replacements = {
        'AGENTS.md': 'agent-guide.md', 'CONTRIBUTING.md': 'contributing.md',
        '../examples/serverpod/README.md': 'getting-started/serverpod.md',
        '../README.md': 'index.md',
    }
    for filename in (ROOT / 'docs').glob('*.md'):
        replacements['docs/' + filename.name] = filename.name
    # Source guides inserted at the root can link directly to sibling pages.
    if '/' not in destination:
        content = re.sub(r'\]\(([^)#]+)(#[^)]*)?\)',
                         lambda match: '](' + replacements.get(match[1], match[1]) +
                         (match[2] or '') + ')', content)
    return content


def on_files(files, config):
    for destination, source in SOURCES.items():
        if files.get_file_from_path(destination) is not None:
            raise ValueError(f'Documentation route collides with canonical source: {destination}')
        files.append(File.generated(config, destination,
            content=adapt_links(source.read_text(encoding='utf-8'), destination)))
    for name in ['llms.txt', 'llms-full.txt']:
        files.append(File.generated(config, name,
            content=(ROOT / name).read_text(encoding='utf-8')))
    for name in ['openai-api-inventory.json', 'together-chat-inventory.json', 'gateway-options-inventory.json', 'cloudflare-api-inventory.json', 'openrouter-api-inventory.json']:
        inventory = ROOT / 'docs' / name
        files.append(File.generated(config, inventory.name,
            content=inventory.read_text(encoding='utf-8')))
    return files
