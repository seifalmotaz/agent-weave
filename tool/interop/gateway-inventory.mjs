/** Reviewed Vercel option declarations, not a public endpoint completeness claim. */
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import ts from 'typescript';

const root = new URL('../../', import.meta.url);
const dir = new URL('tool/contracts/vercel-gateway/', root);
export function gatewayFields(text) {
  const source = ts.createSourceFile('gateway.ts', text, ts.ScriptTarget.Latest, true);
  assert.equal(source.parseDiagnostics.length, 0, 'Invalid TypeScript contract');
  const alias = source.statements.find(node => ts.isTypeAliasDeclaration(node) && node.name.text === 'GatewayProviderOptions');
  assert.ok(alias && ts.isTypeLiteralNode(alias.type), 'Review changed GatewayProviderOptions shape');
  const printer = ts.createPrinter();
  const fields = [];
  const extensions = [];
  for (const member of alias.type.members) {
    if (ts.isIndexSignatureDeclaration(member)) {
      extensions.push(printer.printNode(ts.EmitHint.Unspecified, member, source));
    } else {
      assert.ok(ts.isPropertySignature(member) && member.type && ts.isIdentifier(member.name), 'Unsupported gateway member');
      fields.push({ name: member.name.text, optional: !!member.questionToken,
        type: printer.printNode(ts.EmitHint.Unspecified, member.type, source) });
    }
  }
  return { fields, extensions };
}
async function main() {
  const flag = process.argv[2];
  assert.ok(['--write', '--check', '--upstream'].includes(flag) && process.argv.length === 3, 'Use --write|--check|--upstream');
  const source = JSON.parse(await readFile(new URL('source.json', dir), 'utf8'));
  const coverage = JSON.parse(await readFile(new URL('coverage.json', dir), 'utf8'));
  assert.match(source.revision, /^[a-f0-9]{40}$/);
  const bytes = await readFile(new URL('gateway-provider-options.ts', dir));
  const parsed = gatewayFields(bytes.toString('utf8'));
  assert.deepEqual(parsed.fields.map(f => f.name).sort(), Object.keys(coverage.fields).sort(), 'Classify every named upstream option; remove stale entries');
  for (const record of Object.values(coverage.fields)) {
    assert.ok(['typed-option','request-credentials','native-extension','sdk-client-only'].includes(record.status) && record.api);
  }
  if (flag === '--upstream') {
    const response = await fetch(`https://raw.githubusercontent.com/${source.repository}/main/${source.source_path}`);
    assert.ok(response.ok, `Upstream source fetch: ${response.status}`);
    assert.ok(bytes.equals(Buffer.from(await response.arrayBuffer())), 'Review changed upstream gateway options');
  }
  if (flag === '--check') {
    const actual = JSON.parse(await readFile(new URL('.dart_tool/gateway-options.json', root), 'utf8'));
    assert.deepEqual(Object.keys(actual).sort(), Object.entries(coverage.fields).filter(([,r]) => r.status === 'typed-option').map(([k]) => k).sort());
    assert.deepEqual(actual.providerTimeouts, {byok: {openai: 15000}});
    assert.equal(actual.caching, 'auto');
  }
  const result = { ...source, source: `https://raw.githubusercontent.com/${source.repository}/${source.revision}/${source.source_path}`,
    sha256: createHash('sha256').update(bytes).digest('hex'),
    meaning: 'SDK option declarations and reviewed dispositions. Does not prove public HTTP, nested, model or live parity.',
    ...parsed, dispositions: coverage.fields, remaining: coverage.remaining };
  const rows = parsed.fields.map(field => { const record = coverage.fields[field.name]; return `| ${field.name} | ${record.api} | ${record.status} |`; }).join('\n');
  const guide = `# Gateway option reference\n\nGenerated from Vercel's SDK commit \`${source.revision}\`. This is an\noption inventory, not a certificate of public endpoint behavior. Read the\n[Gateway guide](vercel-gateway.md) for setup and limits.\n\n| Wire option | Dart entry point | Disposition |\n| --- | --- | --- |\n${rows}\n\nThe public Chat and Responses extension uses \`providerOptions.gateway\`.\nBYOK credentials are resolved per request and are excluded from ordinary option\nserialization. Unknown service-owned options can use \`GatewayOptions.extra\`;\nthat does not prove their endpoint applicability. Conditional decision fallbacks\nand the SDK's image decoder are outside these adapters.\n\nSee the [machine-readable inventory](gateway-options-inventory.json). Do not\nedit this generated page by hand; review the pin and run\n\`node tool/interop/gateway-inventory.mjs --write\`.\n`;
  for (const [path, text] of [['docs/gateway-options-inventory.json', `${JSON.stringify(result,null,2)}\n`], ['docs/gateway-options.md',guide]]) {
    const target = new URL(path, root);
    if (flag === '--write') await writeFile(target, text);
    else assert.equal(await readFile(target,'utf8'), text, `Stale ${path}`);
  }
  console.log(`PASS Gateway contract inventory: ${parsed.fields.length} named SDK options`);
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) await main();
