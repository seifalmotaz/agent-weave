/** Review the selected hosted Responses declarations and executable Dart definitions. */
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';
import { declarations } from './inventory.mjs';

const root = new URL('../../', import.meta.url);
const dir = new URL('tool/contracts/openai-computer/', root);
const reviewed = JSON.parse(readFileSync(new URL('tool/contracts/openai-hosted/reviewed-declarations.json', root), 'utf8'));
const prefixes = ['FileSearchTool', 'WebSearchTool', 'WebSearchPreviewTool', 'ToolSearchTool', 'Tool.CodeInterpreter', 'Tool.ImageGeneration', 'ResponseFunctionWebSearch', 'ResponseFileSearchToolCall', 'ResponseCodeInterpreterToolCall', 'ResponseOutputItem.ImageGenerationCall', 'ResponseToolSearchCall', 'ResponseToolSearchOutputItem'];
const requestNames = ['FileSearchTool', 'WebSearchTool', 'WebSearchPreviewTool', 'ToolSearchTool', 'Tool.CodeInterpreter', 'Tool.ImageGeneration'];
export function project(text) {
  const source = ts.createSourceFile('responses.ts', text, ts.ScriptTarget.Latest, true);
  if (source.parseDiagnostics.length) throw new Error('Invalid upstream TypeScript');
  const printer = ts.createPrinter();
  const print = n => printer.printNode(ts.EmitHint.Unspecified, n, source);
  function visit(nodes, scope = []) {
    const output = [];
    for (const node of nodes) {
      if (!node.name || !(ts.isModuleDeclaration(node) || ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node))) continue;
      const path = [...scope, node.name.text].join('.');
      const selected = prefixes.some(p => path === p || path.startsWith(p + '.'));
      if (ts.isModuleDeclaration(node)) {
        if (!node.body || !ts.isModuleBlock(node.body)) throw new Error('Unexpected namespace shape');
        if (selected || prefixes.some(p => p.startsWith(path + '.'))) {
          output.push(`namespace ${node.name.text} {\n${visit(node.body.statements, [...scope, node.name.text])}\n}`);
        }
      } else if (selected) output.push(print(node));
    }
    return output.join('\n');
  }
  return declarations(visit(source.statements), 'hosted-selected.ts');
}
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export function validate(decls, fixture) {
  if (!equal(decls, reviewed)) throw new Error('Review changed hosted declarations, fields, types or unions');
  if (!fixture) return;
  for (const name of requestNames) {
    const value = fixture[name];
    const fields = decls[name].fields.map(f => f.name).sort();
    if (!value || !equal(Object.keys(value).sort(), fields)) throw new Error(`Missing executable field: ${name}`);
  }
  const nested = [
    ['Tool.CodeInterpreter.CodeInterpreterToolAuto', fixture['Tool.CodeInterpreter'].container],
    ['Tool.ImageGeneration.InputImageMask', fixture['Tool.ImageGeneration'].input_image_mask],
    ['FileSearchTool.RankingOptions', fixture.FileSearchTool.ranking_options],
    ['FileSearchTool.RankingOptions.HybridSearch', fixture.FileSearchTool.ranking_options.hybrid_search],
    ['WebSearchTool.Filters', fixture.WebSearchTool.filters],
    ['WebSearchTool.UserLocation', fixture.WebSearchTool.user_location],
    ['WebSearchPreviewTool.UserLocation', fixture.WebSearchPreviewTool.user_location],
  ];
  for (const [name, value] of nested) {
    if (!decls[name] || !value || !equal(Object.keys(value).sort(), decls[name].fields.map(f => f.name).sort())) throw new Error(`Missing executable field: ${name}`);
  }
  if (!equal(fixture['Tool.CodeInterpreter'].container.network_policy, {type: 'disabled'}) ||
      !equal(fixture['Tool.CodeInterpreter'].container.file_ids, ['file']) ||
      fixture['Tool.CodeInterpreter'].container.memory_limit !== '4g' ||
      !equal(fixture['Tool.ImageGeneration'].input_image_mask, {file_id: 'mask', image_url: 'data:image/png;base64,bWFzaw=='})) {
    throw new Error('Executable nested data changed');
  }
}
async function main() {
  const flag = process.argv[2];
  if (process.argv.length !== 3 || !['--write', '--check', '--upstream'].includes(flag)) throw new Error('Expected --write, --check, or --upstream');
  const source = JSON.parse(await readFile(new URL('source.json', dir), 'utf8'));
  const bytes = await readFile(new URL('responses.ts', dir));
  const selected = project(bytes.toString());
  const fixture = flag === '--upstream' ? undefined : JSON.parse(await readFile(new URL('.dart_tool/openai-hosted-options.json', root), 'utf8'));
  validate(selected, fixture);
  if (flag === '--upstream') {
    const response = await fetch(`https://raw.githubusercontent.com/${source.repository}/main/${source.path}`);
    if (!response.ok) throw new Error(`Upstream HTTP ${response.status}`);
    if (!equal(project(await response.text()), selected)) throw new Error('Review changed upstream hosted projection');
    console.log('Upstream hosted projection matches pin'); return;
  }
  const disposition = name => name.startsWith('Response') ? 'private-replay' : 'raw-native-options';
  const meaning = 'Selected hosted Responses declarations and executable request fields only; not a claim of nested semantics, live model behavior, or endpoint parity. Only completed image result bytes become public ImagePart content; other image metadata stays private. Partial images, public citations, hosted progress and downloaded container files are not normalized. External type references are retained, not expanded. Other tools, local executors, and unselected declarations are excluded.';
  const doc = {...source, sha256: createHash('sha256').update(bytes).digest('hex'), meaning, dispositions: Object.fromEntries(Object.keys(selected).map(name => [name, disposition(name)])), declarations: selected};
  const json = JSON.stringify(doc, null, 2) + '\n';
  const guide = '# OpenAI hosted tool inventory\n\nGenerated from the pinned [official Node SDK declarations](openai-hosted-inventory.json). See [the usage guide](openai-hosted.md).\n\n' + meaning + '\n\n' + Object.entries(selected).map(([name, d]) => `## ${name}\n\nDisposition: ${disposition(name)}\n\n` + (d.fields ? `| Field | Source type |\n| --- | --- |\n${d.fields.map(f => `| ${f.name}${f.optional ? '?' : ''} | \`${f.type.replaceAll('|', '\\|')}\` |`).join('\n')}\n` : `\`${d.type}\`\n`)).join('\n');
  for (const [path, content] of [['docs/openai-hosted-inventory.json', json], ['docs/openai-hosted-parameters.md', guide]]) {
    const url = new URL(path, root);
    if (flag === '--write') await writeFile(url, content);
    else if (await readFile(url, 'utf8') !== content) throw new Error(`Generated file is stale: ${path}`);
  }
  console.log(`Hosted inventory ${flag.slice(2)} passed`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main().catch(e => { console.error(e); process.exitCode = 1; });
