/** Selected OpenAI custom-tool contract, reviewed independently of full Responses. */
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { project as select } from './openai-hosted-inventory.mjs';
import { declarations } from './inventory.mjs';
import ts from 'typescript';

const root = new URL('../../', import.meta.url);
const dir = new URL('tool/contracts/openai-custom/', root);
const responsePath = new URL('tool/contracts/openai-computer/responses.ts', root);
const roots = ['CustomTool', 'NamespaceTool', 'ResponseCustomToolCall', 'ResponseCustomToolCallItem', 'ResponseCustomToolCallOutput', 'ResponseCustomToolCallOutputItem', 'ResponseCustomToolCallInputDeltaEvent', 'ResponseCustomToolCallInputDoneEvent', 'ResponseInputText', 'ResponseInputImage', 'ResponseInputFile', 'ImageDetail', 'ResponseOutputItemAddedEvent', 'ResponseOutputItemDoneEvent', 'ToolChoiceCustom', 'ToolChoiceAllowed'];
const unions = ['Tool', 'ResponseInputItem', 'ResponseOutputItem', 'ResponseStreamEvent'];
const sharedRoots = ['CustomToolInputFormat'];
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

export function projection(responses, shared) {
  const r = select(responses, roots), s = select(shared, sharedRoots);
  const source = ts.createSourceFile('responses.ts', responses, ts.ScriptTarget.Latest, true);
  if (source.parseDiagnostics.length) throw new Error('Invalid upstream TypeScript');
  const printer = ts.createPrinter();
  for (const name of unions) {
    const node = source.statements.find(n => ts.isTypeAliasDeclaration(n) && n.name.text === name);
    if (!node) throw new Error(`Missing response root ${name}`);
    Object.assign(r, declarations(printer.printNode(ts.EmitHint.Unspecified, node, source), 'custom-union.ts'));
  }
  for (const name of roots) if (!r[name]) throw new Error(`Missing response root ${name}`);
  for (const name of sharedRoots) if (!s[name]) throw new Error(`Missing shared root ${name}`);
  return {responses: r, shared: s};
}
export function validate(declarations, reviewed, fixture) {
  if (!eq(declarations, reviewed)) throw new Error('Review changed custom tool fields, roots or unions');
  if (!fixture) return;
  const fields = (name, value, requiredOnly = false) => {
    const schema = declarations.responses[name] ?? declarations.shared[name];
    const required = schema.fields.filter(f => !f.optional || !requiredOnly).map(f => f.name).sort();
    if (!eq(Object.keys(value).sort(), required)) throw new Error(`Executable fixture fields differ: ${name}`);
  };
  fields('NamespaceTool', fixture.namespace);
  fields('ToolChoiceCustom', fixture.customChoice);
  fields('ToolChoiceAllowed', fixture.allowedChoice);
  fields('CustomTool', fixture.namespace.tools[0]);
  fields('CustomToolInputFormat.Text', fixture.textFormat);
  fields('CustomToolInputFormat.Grammar', fixture.namespace.tools[0].format);
  fields('CustomToolInputFormat.Grammar', fixture.regexFormat);
  fields('ResponseCustomToolCallItem', {id: fixture.call.id, status: fixture.call.status, created_by: fixture.call.created_by});
  fields('ResponseCustomToolCall', Object.fromEntries(Object.entries(fixture.call).filter(([key]) => !['status', 'created_by'].includes(key))));
  fields('ResponseCustomToolCall.Direct', fixture.call.caller);
  fields('ResponseCustomToolCallOutput', fixture.outputItem);
  fields('ResponseCustomToolCallOutput.Direct', fixture.outputItem.caller);
  const blocks = fixture.contentResult.output;
  for (const [index, name] of ['ResponseInputText', 'ResponseInputImage', 'ResponseInputFile'].entries()) {
    fields(name, blocks[index]);
    fields(`${name}.PromptCacheBreakpoint`, blocks[index].prompt_cache_breakpoint);
  }
  if (!eq(fixture.textResult, {output: 'raw result', isError: false, id: 'out', caller: {type: 'direct'}}) || fixture.errorResult.isError !== true || fixture.contentResult.isError !== false || fixture.regexFormat.syntax !== 'regex') throw new Error('Executable result fixture changed');
}
export function renderDeclarations(types) {
  const cell = value => value.replace(/\s+/g, ' ').trim().replaceAll('|', '\\|').replaceAll('`', '&#96;');
  return Object.entries(types).flatMap(([group, values]) => Object.entries(values).map(([name, d]) => {
    const heading = `## ${group}.${name}\n\n`;
    if (d.fields) {
      return heading + `| Field | Type |\n| --- | --- |\n${d.fields.map(f => `| ${cell(f.name)}${f.optional ? '?' : ''} | \`${cell(f.type)}\` |`).join('\n')}\n`;
    }
    const label = unions.includes(name) && group === 'responses' ? 'Shallow union signature; variants are not all integrated.\n\n' : '';
    const displayType = label ? d.type.replaceAll(' | ', '\n  | ') : d.type;
    return `${heading}${label}\`\`\`ts\n${displayType}\n\`\`\`\n`;
  })).join('\n');
}
async function main() {
  const flag = process.argv[2];
  if (process.argv.length !== 3 || !['--check', '--write', '--upstream'].includes(flag)) throw new Error('Usage: --check|--write|--upstream');
  const source = JSON.parse(await readFile(new URL('source.json', dir), 'utf8'));
  const response = await readFile(responsePath), shared = await readFile(new URL('shared.ts', dir));
  if (!/^[a-f0-9]{40}$/.test(source.revision) || hash(response) !== source.responsesSha256 || hash(shared) !== source.sharedSha256) throw new Error('Pinned source hash mismatch');
  const types = projection(response.toString(), shared.toString());
  const reviewed = JSON.parse(await readFile(new URL('reviewed-declarations.json', dir), 'utf8'));
  validate(types, reviewed);
  if (flag === '--upstream') {
    const files = await Promise.all([source.responses, source.shared].map(async path => {
      const result = await fetch(`https://raw.githubusercontent.com/${source.repository}/main/${path}`);
      if (!result.ok) throw new Error(`Upstream HTTP ${result.status}`);
      return result.text();
    }));
    validate(projection(...files), reviewed);
    console.log('PASS upstream selected custom-tool projection'); return;
  }
  const dart = process.env.DART ?? 'dart';
  const fixture = JSON.parse(execFileSync(dart, ['run', 'tool/openai_custom_contract.dart'], {cwd: fileURLToPath(root), encoding: 'utf8'}));
  validate(types, reviewed, fixture);
  const scope = 'Selected custom-tool declarations, four shallow union signatures and output-item event envelopes only; this is not full Responses union coverage or live workflow certification. Direct synchronous custom calls, text and grammar formats, custom-only namespaces and typed string/content results are implemented; namespaced function tools, asynchronous and programmatic calls are not integrated. Grammar syntax is provider-enforced; application callbacks validate their own input.';
  const dispositions = Object.fromEntries(Object.entries(types).flatMap(([group, values]) => Object.entries(values).map(([name, d]) => [`${group}.${name}`, Object.fromEntries((d.fields ?? []).map(field => [field.name, name.startsWith('ToolChoice') ? 'native toolChoice option; selected fields reviewed' : name.startsWith('NamespaceTool.Function') ? 'not integrated: namespaced function tool' : name.endsWith('.Program') ? 'not integrated: programmatic caller' : field.name === 'async' || field.name === 'allowed_callers' || field.name === 'caller' ? 'direct-only; asynchronous and programmatic unsupported' : name.startsWith('ResponseOutputItem') ? 'reviewed event envelope' : name.startsWith('ResponseCustom') ? 'private call or replay' : 'typed configuration or result content']))])));
  const unionDispositions = Object.fromEntries(unions.map(name => [`responses.${name}`, 'union members reviewed; non-custom variants not integrated by this inventory']));
  const doc = {...source, scope, dispositions, unionDispositions, declarations: types};
  const json = JSON.stringify(doc, null, 2) + '\n';
  const guide = `# OpenAI custom tool contract\n\nGenerated from the [pinned inventory](openai-custom-inventory.json). See the [official guide](${source.documentation}).\n\n${scope}\n\n` + renderDeclarations(types);
  for (const [name, data] of [['docs/openai-custom-inventory.json', json], ['docs/openai-custom-parameters.md', guide]]) {
    const target = new URL(name, root);
    if (flag === '--write') await writeFile(target, data);
    else if (await readFile(target, 'utf8') !== data) throw new Error(`Stale custom inventory: ${name}`);
  }
  console.log(`PASS custom tool inventory: ${roots.length + sharedRoots.length + unions.length} roots, ${Object.values(types).reduce((sum, value) => sum + Object.keys(value).length, 0)} declarations`);
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
