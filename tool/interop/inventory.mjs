/** Build a reviewable contract index from pinned official TypeScript declarations. */
// Pin the stable TypeScript 6 compiler API; TypeScript 7 exposes a different unstable API.
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const root = new URL('../../', import.meta.url);
const directory = new URL('tool/contracts/together/', root);
const target = new URL('docs/together-chat-inventory.json', root);
const guideTarget = new URL('docs/together-options.md', root);

export function validateCoverage(fields, coverage, serializedOptions) {
  const names = fields.map(field => field.name).sort();
  if (JSON.stringify(names) !== JSON.stringify(Object.keys(coverage).sort())) {
    throw new Error('Every upstream request field needs an explicit disposition; remove stale entries too');
  }
  for (const [name, record] of Object.entries(coverage)) {
    if (!['typed-option', 'runtime-owned', 'native-only'].includes(record.status) || !record.api) {
      throw new Error(`Invalid coverage disposition: ${name}`);
    }
  }
  if (serializedOptions !== undefined) {
    const typed = Object.entries(coverage).filter(([, record]) => record.status === 'typed-option').map(([name]) => name).sort();
    if (JSON.stringify(typed) !== JSON.stringify(Object.keys(serializedOptions).sort())) {
      throw new Error('The executable options fixture must serialize every typed option exactly once');
    }
  }
}

export function declarations(text, filename) {
  const source = ts.createSourceFile(filename, text, ts.ScriptTarget.Latest, true);
  if (source.parseDiagnostics.length) throw new Error(`Invalid TypeScript source: ${filename}`);
  const printer = ts.createPrinter({ newLine: ts.NewLineKind.LineFeed });
  const print = node => printer.printNode(ts.EmitHint.Unspecified, node, source).trim();
  const result = {};
  function visit(nodes, scope = []) {
    for (const node of nodes) {
      if (ts.isModuleDeclaration(node)) {
        if (!node.body || !ts.isModuleBlock(node.body)) throw new Error('Unexpected namespace shape');
        visit(node.body.statements, [...scope, node.name.text]);
      } else if (ts.isInterfaceDeclaration(node)) {
        const name = [...scope, node.name.text].join('.');
        if (result[name]) throw new Error(`Duplicate interface: ${name}`);
        result[name] = {
          kind: 'interface',
          extends: node.heritageClauses?.flatMap(clause => clause.types.map(print)) ?? [],
          fields: node.members.map(member => {
            if (!ts.isPropertySignature(member) || !member.name || !member.type) {
              throw new Error(`Unsupported interface member: ${name}: ${print(member)}`);
            }
            if (!ts.isIdentifier(member.name) && !ts.isStringLiteral(member.name)) {
              throw new Error(`Unsupported property name: ${name}`);
            }
            return { name: member.name.text, optional: !!member.questionToken, type: print(member.type) };
          }),
        };
      } else if (ts.isTypeAliasDeclaration(node)) {
        const name = [...scope, node.name.text].join('.');
        if (result[name]) throw new Error(`Duplicate type: ${name}`);
        result[name] = { kind: 'alias', type: print(node.type) };
      }
    }
  }
  visit(source.statements);
  return result;
}

async function main() {
  const flags = process.argv.slice(2);
  if (flags.length !== 1 || !['--write', '--check', '--upstream'].includes(flags[0])) {
    throw new Error('Usage: node tool/interop/inventory.mjs --write|--check|--upstream');
  }
  const source = JSON.parse(await readFile(new URL('source.json', directory), 'utf8'));
  if (!/^[a-f0-9]{40}$/.test(source.revision)) throw new Error('Expected a full upstream commit pin');
  const files = {};
  for (const [filename, path] of Object.entries(source.files)) {
    const bytes = await readFile(new URL(filename, directory));
    const url = `https://raw.githubusercontent.com/${source.repository}/${source.revision}/${path}`;
    if (flags[0] === '--upstream') {
      const response = await fetch(`https://raw.githubusercontent.com/${source.repository}/main/${path}`);
      if (!response.ok) throw new Error(`Upstream request failed: ${response.status}`);
      const latest = Buffer.from(await response.arrayBuffer());
      if (!bytes.equals(latest)) throw new Error(`Review changed upstream contract: ${path}`);
    }
    files[filename] = {
      source: url,
      sha256: createHash('sha256').update(bytes).digest('hex'),
      declarations: declarations(bytes.toString('utf8'), filename),
    };
  }
  const coverage = JSON.parse(await readFile(new URL('coverage.json', directory), 'utf8'));
  const document = {
    ...source,
    meaning: 'Declarations and reviewed top-level field dispositions. Not a claim of nested semantics, runtime, model, live or endpoint parity. Review provider tests and remaining limits separately.',
    dispositions: coverage.request,
    remaining: coverage.remaining,
    files,
  };
  const encoded = `${JSON.stringify(document, null, 2)}\n`;
  const rows = Object.entries(coverage.request).map(([name, record]) =>
    `| ${name} | ${record.api} | ${record.status} |`).join('\n');
  const guide = `# Together chat request fields\n\nGenerated from the reviewed [contract inventory](together-chat-inventory.json) at\nTogether SDK commit \`${source.revision}\`. Do not edit this table by hand;\nreview the source pin and run \`node tool/interop/inventory.mjs --write\`.\n\nThe agent adapter owns conversation history, tools, schema and execution bounds.\nUse the native JSON client where indicated. A field disposition does not prove\nnested semantics, model acceptance, or coverage of other endpoints. See the\n[Together guide](together.md) for complete setup, errors and known limits.\n\n| Wire field | Dart entry point or runtime behavior | Disposition |\n| --- | --- | --- |\n${rows}\n\nThe native client accepts arbitrary JSON fields; it does not statically validate\nthe whole provider API. Typed options cover common agent requests. Native response\nmetadata is available from raw methods; not all fields are normalized by the agent.\n`;
  if (flags[0] === '--write') {
    await writeFile(target, encoded);
    await writeFile(guideTarget, guide);
  } else {
    if (await readFile(target, 'utf8') !== encoded || await readFile(guideTarget, 'utf8') !== guide) {
      throw new Error('Stale Together contract artifacts; review changes, then run --write');
    }
  }
  const fields = files['chat-completions.ts'].declarations.CompletionCreateParamsBase.fields;
  if (flags[0] === '--check') {
    const serialized = JSON.parse(await readFile(new URL('.dart_tool/together-options.json', root), 'utf8'));
    validateCoverage(fields, coverage.request, serialized);
    if (serialized.logprobs !== 5 || serialized.reasoning?.enabled !== false) {
      throw new Error('Together numeric logprobs and reasoning must retain their native types');
    }
  } else validateCoverage(fields, coverage.request);
  console.log(`PASS Together contract inventory: ${fields.length} chat request fields at ${source.revision}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
