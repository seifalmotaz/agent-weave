import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import ts from 'typescript';
import { declarations } from './inventory.mjs';

const root = new URL('../../', import.meta.url);
const dir = new URL('tool/contracts/anthropic/', root);
const additional = new Set(['ToolResultBlockParam', 'ToolUseBlock', 'ToolUseBlockParam', 'ToolUseCaller', 'DirectCaller', 'ServerToolCaller', 'ServerToolCaller20260120', 'ImageBlockParam', 'Base64ImageSource', 'URLImageSource', 'CacheControlEphemeral']);
export function projection(text) {
  const source = ts.createSourceFile('messages.ts', text, ts.ScriptTarget.Latest, true);
  if (source.parseDiagnostics.length) throw new Error('Invalid TypeScript source');
  const printer = ts.createPrinter({newLine: ts.NewLineKind.LineFeed});
  const result = {};
  for (const node of source.statements) {
    if (!(ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node))) continue;
    const name = node.name.text;
    if (!name.startsWith('Computer') && !additional.has(name)) continue;
    Object.assign(result, declarations(printer.printNode(ts.EmitHint.Unspecified, node, source), name + '.ts'));
  }
  for (const name of [...additional, 'ComputerMemberInput', 'ComputerMemberName', 'ComputerToolUseBlock', 'ComputerToolset20260801', 'ComputerToolsetConfigs']) {
    if (!result[name]) throw new Error(`Missing declaration: ${name}`);
  }
  return Object.fromEntries(Object.entries(result).sort(([a], [b]) => a.localeCompare(b, 'en')));
}

async function main() {
  const [flag, ...extra] = process.argv.slice(2);
  if (extra.length || !['--write', '--check', '--upstream'].includes(flag)) throw new Error('Usage: --write|--check|--upstream');
  const source = JSON.parse(await readFile(new URL('source.json', dir), 'utf8'));
  if (!/^[a-f0-9]{40}$/.test(source.revision)) throw new Error('Expected full commit SHA');
  const snapshot = await readFile(new URL('messages.ts', dir), 'utf8');
  const types = projection(snapshot);
  if (flag === '--upstream') {
    const response = await fetch(`https://raw.githubusercontent.com/${source.repository}/main/${source.path}`);
    if (!response.ok) throw new Error(`Upstream request failed: ${response.status}`);
    if (JSON.stringify(projection(await response.text())) !== JSON.stringify(types)) throw new Error('Selected upstream declarations changed; review contract drift');
  }
  if (flag === '--check') {
    const dart = 'dart';
    const fixture = JSON.parse(execFileSync(dart, ['run', 'tool/anthropic_computer_contract.dart'], {cwd: fileURLToPath(root), encoding: 'utf8'}));
    const members = types.ComputerToolsetConfigs.fields.map(field => field.name).sort();
    const directions = [...types.ComputerScrollDirection.type.matchAll(/'([^']+)'/g)].map(match => match[1]).sort();
    if (JSON.stringify([...fixture.directions].sort()) !== JSON.stringify(directions)) throw new Error('Dart scroll directions differ from upstream');
    const definitionFields = types.ComputerToolset20260801.fields.map(field => field.name).concat('allowed_callers').sort();
    if (JSON.stringify(Object.keys(fixture.definition).sort()) !== JSON.stringify(definitionFields) || JSON.stringify(fixture.definition.allowed_callers) !== JSON.stringify(['direct'])) throw new Error('Dart toolset fields differ from source and documented direct-caller override');
    if (JSON.stringify(Object.keys(fixture.inputs).sort()) !== JSON.stringify(members)) throw new Error('Dart fixture must exercise all computer members');
    for (const [name, input] of Object.entries(fixture.inputs)) {
      const declaration = 'Computer' + name.split('_').map(part => part[0].toUpperCase() + part.slice(1)).join('') + 'Input';
      const fields = types[declaration].fields.map(field => field.name).sort();
      if (JSON.stringify(Object.keys(input).sort()) !== JSON.stringify(fields)) throw new Error(`Dart fixture fields differ from ${declaration}`);
      const required = types[declaration].fields.filter(field => !field.optional).map(field => field.name).sort();
      if (JSON.stringify(fixture.required[name].sort()) !== JSON.stringify(required)) throw new Error(`Dart required fields differ from ${declaration}`);
    }
    if (JSON.stringify(Object.keys(fixture.configs).sort()) !== JSON.stringify(members)) throw new Error('Dart fixture config members differ');
    for (const [name, config] of Object.entries(fixture.configs)) {
      const type = types.ComputerToolsetConfigs.fields.find(field => field.name === name).type.split(' ')[0];
      if (JSON.stringify(Object.keys(config).sort()) !== JSON.stringify(types[type].fields.map(field => field.name).sort())) throw new Error(`Dart config fields differ from ${type}`);
    }
    for (const value of [fixture.text, fixture.error, fixture.image]) {
      const known = types.ToolResultBlockParam.fields.map(field => field.name);
      if (Object.keys(value).some(field => !known.includes(field))) throw new Error('Unknown result wire field');
    }
    const image = fixture.image.content[0];
    if (image.type !== 'image' || image.source.type !== 'base64' || JSON.stringify(Object.keys(image.source).sort()) !== JSON.stringify(types.Base64ImageSource.fields.map(field => field.name).sort())) throw new Error('Image result differs from base64 wire source');
    if (fixture.text.content[0].type !== 'text' || fixture.error.is_error !== true) throw new Error('Text/error result mismatch');
  }
  const overrides = {
    allowed_callers: 'Official computer-use documentation permits ["direct"] only; this field is absent from the pinned ComputerToolset20260801 SDK declaration.',
    limits: 'Official docs specify key repeat 1..100 (default 1), and hold_key/wait duration up to 300 seconds. The driver must validate fields and bound duration, repeat and scroll_amount.',
    batching: 'Run in order; after first failure, answer all remaining calls as errors with exactly: Not executed: an earlier computer action in this turn failed.',
  };
  const doc = {...source, sha256: createHash('sha256').update(snapshot).digest('hex'), scope: 'Selected Computer declarations and root tool result, caller and image wire types; documentation-only constraints are listed separately.', documentation: 'https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool', documentationOverrides: overrides, declarations: types};
  const json = `${JSON.stringify(doc, null, 2)}\n`;
  const guide = `# Anthropic computer toolset contract\n\nGenerated from the [inventory](anthropic-computer-inventory.json), pinned to official TypeScript SDK commit \`${source.revision}\`. Run \`node tool/interop/anthropic-computer-inventory.mjs --write\` after review. See the [computer use documentation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool) and [SDK driver guidance](https://platform.claude.com/docs/en/agents-and-tools/tool-use/browser-use-sdk).\n\nThe 17 member calls use \`toolset_name: computer\`, the member name, and member-specific input with no action field. Dispatch by both names. Configs are sparse: each member defaults to enabled with defer_loading false. The toolset accepts cache_control. The documentation additionally permits allowed_callers with only [\"direct\"]; the pinned SDK declaration omits that field.\n\nRun a batch sequentially. On failure, return an error for that action and for every subsequent unexecuted action, with the exact halt text in the inventory. Return one result for every call with its tool_use_id and toolset_name. Screenshot and zoom return an image; cursor_position returns coordinates as text. Coordinates always refer to the full screenshot, including after zoom.\n\nThe driver owns validation, coordinate conversion, image sizing, environment isolation and approval policy. Documentation specifies key repeat 1–100 (default 1), and hold_key and wait duration up to 300 seconds; the official driver guidance leaves these checks to applications. AgentWeave validates selected repeat and duration bounds before invoking the executor. These declarations and offline fixtures do not demonstrate model acceptance, desktop execution, or live behavior.\n`;
  for (const [path, value] of [[new URL('docs/anthropic-computer-inventory.json', root), json], [new URL('docs/anthropic-computer-parameters.md', root), guide]]) {
    if (flag === '--write') await writeFile(path, value);
    else if (await readFile(path, 'utf8') !== value) throw new Error('Stale computer inventory; review and run --write');
  }
  console.log(`PASS Anthropic computer inventory: ${Object.keys(types).length} declarations`);
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
