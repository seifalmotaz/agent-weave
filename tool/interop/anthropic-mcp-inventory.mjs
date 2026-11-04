/** Review the pinned Messages MCP projection and its executable Dart options. */
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import ts from 'typescript';
import { projection as anthropicProjection } from './anthropic-inventory.mjs';

const root = new URL('../../', import.meta.url);
const dir = new URL('tool/contracts/anthropic-mcp/', root);
const reviewed = JSON.parse(readFileSync(new URL('reviewed-declarations.json', dir), 'utf8'));
export const roots = [
  'BetaMCPTool', 'BetaMCPToolParam', 'BetaMCPToolConfig', 'BetaMCPToolDefaultConfig',
  'BetaMCPToolListingBlock', 'BetaMCPToolListingBlockParam', 'BetaMCPToolResultBlock',
  'BetaMCPToolUseBlock', 'BetaMCPToolUseBlockParam', 'BetaMCPToolset',
  'BetaRequestMCPServerToolConfiguration', 'BetaRequestMCPServerURLDefinition',
  'BetaRequestMCPToolResultBlockParam', 'BetaCacheControlEphemeral',
];
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);

/** Guard MCP roots, then reuse the Messages declaration projector. */
export function projection(text, selected = roots) {
  const source = ts.createSourceFile('messages.ts', text, ts.ScriptTarget.Latest, true);
  if (source.parseDiagnostics.length) throw new Error('Invalid TypeScript source');
  if (selected === roots) {
    const discovered = source.statements
      .filter(node => ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node))
      .map(node => node.name.text)
      .filter(name => name.startsWith('BetaMCP') || name.startsWith('BetaRequestMCP'))
      .sort();
    const classified = roots.filter(name => name.startsWith('BetaMCP') || name.startsWith('BetaRequestMCP')).sort();
    if (!equal(discovered, classified)) throw new Error('Review new or removed MCP root declarations');
  }
  return anthropicProjection(text, selected);
}
export function validate(types, bytes, expected = reviewed) {
  const hash = createHash('sha256').update(bytes).digest('hex');
  if (hash !== expected.sourceSha256) throw new Error('Pinned source bytes changed; review source and hash');
  if (!equal(types, expected.declarations)) throw new Error('Review changed MCP declarations or unions');
}
function fields(types, name) { return types[name].fields.map(f => f.name).sort(); }
function exact(value, expected, label) {
  if (!value || !equal(Object.keys(value).sort(), expected)) throw new Error(`MCP fixture fields differ: ${label}`);
}
export function validateFixture(types, fixture) {
  const serverFields = fields(types, 'BetaRequestMCPServerURLDefinition');
  if (!equal([...fixture.legacyResolvedFields].sort(), serverFields)) throw new Error('MCP fixture fields differ: resolved server');
  exact(fixture.legacy, serverFields.filter(x => x !== 'authorization_token'), 'legacy server');
  exact(fixture.modern, serverFields.filter(x => !['authorization_token', 'tool_configuration'].includes(x)), 'modern server');
  exact(fixture.legacy.tool_configuration, fields(types, 'BetaRequestMCPServerToolConfiguration'), 'legacy configuration');
  const toolsetFields = fields(types, 'BetaMCPToolset');
  if (!equal([...new Set([...Object.keys(fixture.toolset), ...Object.keys(fixture.pinned)])].sort(), toolsetFields)) throw new Error('MCP fixture fields differ: toolset');
  exact(fixture.toolset.default_config, fields(types, 'BetaMCPToolDefaultConfig'), 'default config');
  exact(fixture.toolset.configs.read, fields(types, 'BetaMCPToolConfig'), 'per-tool config');
  exact(fixture.toolset.cache_control, fields(types, 'BetaCacheControlEphemeral'), 'cache control');
  exact(fixture.pinned.tools[0], fields(types, 'BetaMCPToolParam'), 'pinned tool');
  if (!equal(fixture.headers, ['mcp-client-2025-04-04', 'mcp-client-2025-11-20', 'mcp-client-2026-09-15'])) throw new Error('MCP beta modes differ');
}
async function main() {
  const [flag, ...extra] = process.argv.slice(2);
  if (extra.length || !['--write', '--check', '--upstream'].includes(flag)) throw new Error('Usage: --write|--check|--upstream');
  const source = JSON.parse(await readFile(new URL('source.json', dir), 'utf8'));
  if (!/^[a-f0-9]{40}$/.test(source.revision)) throw new Error('Expected full commit SHA');
  const bytes = await readFile(new URL('messages.ts', dir));
  const types = projection(bytes.toString());
  validate(types, bytes);
  if (flag === '--upstream') {
    const response = await fetch(`https://raw.githubusercontent.com/${source.repository}/main/${source.path}`);
    if (!response.ok || !equal(projection(await response.text()), types)) throw new Error('Selected upstream MCP declarations changed; review drift');
    console.log('PASS upstream MCP projection'); return;
  }
  const fixture = JSON.parse(execFileSync('dart', ['run', 'tool/anthropic_mcp_contract.dart'], {cwd: fileURLToPath(root), encoding: 'utf8'}));
  validateFixture(types, fixture);
  const modes = {
    'mcp-client-2025-04-04': 'Deprecated legacy server tool_configuration; provider availability is not established.',
    'mcp-client-2025-11-20': 'Modern matching server and toolset; supported cloud platforms vary.',
    'mcp-client-2026-09-15': 'Claude API listing and pinned tool descriptors; replay listings with this beta.',
  };
  const scope = 'Selected MCP Messages declarations and recursively referenced local types. The Dart fixture exercises owned configuration and credential separation, not SSE normalization, provider acceptance or live execution. MCP result content in this pinned contract is string or an array of text blocks; private replay and continuation are tested separately.';
  const doc = {...source, sha256: reviewed.sourceSha256, scope, betaModes: modes, declarations: types};
  const json = JSON.stringify(doc, null, 2) + '\n';
  const guide = `# Anthropic MCP Messages contract\n\nGenerated from the [pinned inventory](anthropic-mcp-inventory.json). See the [official connector guide](${source.documentation[0]}).\n\n${scope}\n\n` + Object.entries(modes).map(([name, detail]) => `- \`${name}\`: ${detail}`).join('\n') + '\n\n' + Object.entries(types).map(([name, d]) => `## ${name}\n\n` + (d.fields ? `| Field | Source type |\n| --- | --- |\n${d.fields.map(f => `| ${f.name}${f.optional ? '?' : ''} | \`${f.type.replaceAll('|', '\\|')}\` |`).join('\n')}\n` : `\`${d.type}\`\n`)).join('\n');
  for (const [path, content] of [['docs/anthropic-mcp-inventory.json', json], ['docs/anthropic-mcp-parameters.md', guide]]) {
    const url = new URL(path, root);
    if (flag === '--write') await writeFile(url, content);
    else if (await readFile(url, 'utf8') !== content) throw new Error(`Stale MCP inventory: ${path}`);
  }
  console.log(`PASS Anthropic MCP inventory: ${roots.length} roots, ${Object.keys(types).length} declarations`);
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
