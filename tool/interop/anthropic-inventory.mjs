import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';
import { declarations } from './inventory.mjs';

const root = new URL('../../', import.meta.url);
const dir = new URL('tool/contracts/anthropic/', root);
const roots = ['MessageCreateParams', 'RawMessageStreamEvent', 'Message'];

// Resolve the selected declarations and their locally declared type dependencies.
export function projection(text, selectedRoots = roots) {
  const source = ts.createSourceFile('messages.ts', text, ts.ScriptTarget.Latest, true);
  if (source.parseDiagnostics.length) throw new Error('Invalid TypeScript source');
  const nodes = new Map();
  function collect(statements, scope = '') {
    for (const node of statements) {
      if (ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node)) nodes.set(scope + node.name.text, node);
      if (ts.isModuleDeclaration(node) && node.body && ts.isModuleBlock(node.body)) collect(node.body.statements, `${scope}${node.name.text}.`);
    }
  }
  collect(source.statements);
  const printer = ts.createPrinter({ newLine: ts.NewLineKind.LineFeed });
  const output = {};
  const pending = [...selectedRoots];
  while (pending.length) {
    const name = pending.pop();
    if (output[name]) continue;
    const node = nodes.get(name);
    if (!node) throw new Error(`Missing declaration: ${name}`);
    function references(n) {
      if (ts.isExpressionWithTypeArguments(n) && ts.isIdentifier(n.expression) && nodes.has(n.expression.text)) pending.push(n.expression.text);
      if (ts.isTypeReferenceNode(n)) {
        const target = n.typeName.getText(source);
        const scoped = name.includes('.') ? `${name.slice(0, name.lastIndexOf('.') + 1)}${target}` : target;
        const found = nodes.has(scoped) ? scoped : target;
        if (nodes.has(found) && !output[found]) pending.push(found);
      }
      ts.forEachChild(n, references);
    }
    references(node);
    // The shared declaration helper accepts named properties. Keep index
    // signatures as named entries containing their exact signature and type.
    let declaration = node;
    if (ts.isInterfaceDeclaration(node)) {
      const members = node.members.map(member => ts.isIndexSignatureDeclaration(member)
        ? ts.factory.createPropertySignature(undefined, ts.factory.createStringLiteral(printer.printNode(ts.EmitHint.Unspecified, member, source)), undefined, member.type)
        : member);
      declaration = ts.factory.updateInterfaceDeclaration(node, node.modifiers, node.name, node.typeParameters, node.heritageClauses, members);
    }
    const printed = printer.printNode(ts.EmitHint.Unspecified, declaration, source);
    output[name] = declarations(printed, `${name}.ts`)[node.name.text];
  }
  return Object.fromEntries(Object.entries(output).sort(([a], [b]) => a.localeCompare(b, 'en')));
}

export function validateCoverage(fields, coverage) {
  if (JSON.stringify(fields.map(x => x.name).sort()) !== JSON.stringify(Object.keys(coverage).sort())) {
    throw new Error('Every request field needs a disposition; remove stale entries');
  }
  for (const [name, item] of Object.entries(coverage)) {
    if (!['runtime-owned', 'sdk-configure', 'native-json', 'mixed'].includes(item.status) || !item.detail) throw new Error(`Invalid disposition: ${name}`);
  }
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
  const coverage = JSON.parse(await readFile(new URL('coverage.json', dir), 'utf8'));
  validateCoverage(types.MessageCreateParamsBase.fields, coverage);
  const doc = { ...source, sha256: createHash('sha256').update(snapshot).digest('hex'), scope: 'Selected request, response and stream declarations and their local type references. Dispositions describe top-level access only, not nested semantics or live model support.', dispositions: coverage, declarations: types };
  const json = `${JSON.stringify(doc, null, 2)}\n`;
  const rows = Object.entries(coverage).map(([key, value]) => `| ${key} | ${value.status} | ${value.detail} |`).join('\n');
  const guide = `# Anthropic Messages request fields\n\nGenerated from the [contract inventory](anthropic-api-inventory.json), pinned to official TypeScript SDK commit \`${source.revision}\`. Run \`node tool/interop/anthropic-inventory.mjs --write\` after reviewing changes.\n\nThese dispositions describe top-level access only. Arbitrary native JSON does not validate nested unions or establish agent orchestration, model acceptance, or live behavior. The SDK adapter owns messages, execution bounds, system instructions and tools; its output schema is protected when supplied by the runtime.\n\n| Field | Disposition | Access and limits |\n| --- | --- | --- |\n${rows}\n\nThe inventory follows selected local type references for Messages requests, responses and stream events. Imported declarations and unrelated endpoints are outside its scope. Review protocol behavior and provider documentation separately.\n`;
  const targets = [[new URL('docs/anthropic-api-inventory.json', root), json], [new URL('docs/anthropic-parameters.md', root), guide]];
  for (const [path, value] of targets) {
    if (flag === '--write') await writeFile(path, value);
    else if (await readFile(path, 'utf8') !== value) throw new Error('Stale Anthropic inventory; review and run --write');
  }
  console.log(`PASS Anthropic inventory: ${types.MessageCreateParamsBase.fields.length} fields, ${Object.keys(types).length} declarations`);
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
