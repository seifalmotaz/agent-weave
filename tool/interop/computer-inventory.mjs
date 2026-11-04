/** Review the selected computer protocol declarations against the Dart driver. */
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';
import { declarations } from './inventory.mjs';

const root = new URL('../../', import.meta.url);
const dir = new URL('tool/contracts/openai-computer/', root);
const selected = new Set(['ComputerTool', 'ComputerUsePreviewTool', 'ResponseComputerToolCall', 'ResponseComputerToolCallOutputItem', 'ResponseComputerToolCallOutputScreenshot']);
const namespaces = new Set(['ResponseComputerToolCall', 'ResponseComputerToolCallOutputItem']);
// Each key is a reviewed field, including fields the driver deliberately does not integrate.
const coverage = {
  ComputerTool: { type: 'typed' },
  ComputerUsePreviewTool: { display_height: 'typed', display_width: 'typed', environment: 'typed', type: 'typed' },
  ResponseComputerToolCall: { id: 'private-replay', call_id: 'native-controlled', pending_safety_checks: 'native-controlled', status: 'native-controlled', type: 'native-controlled', action: 'typed', actions: 'typed' },
  'ResponseComputerToolCall.PendingSafetyCheck': { id: 'native-controlled', code: 'native-controlled', message: 'native-controlled' },
  'ResponseComputerToolCall.Click': { button: 'typed', type: 'typed', x: 'typed', y: 'typed', keys: 'typed' },
  'ResponseComputerToolCall.DoubleClick': { keys: 'typed', type: 'typed', x: 'typed', y: 'typed' },
  'ResponseComputerToolCall.Drag': { path: 'typed', type: 'typed', keys: 'typed' },
  'ResponseComputerToolCall.Drag.Path': { x: 'typed', y: 'typed' },
  'ResponseComputerToolCall.Keypress': { keys: 'typed', type: 'typed' },
  'ResponseComputerToolCall.Move': { type: 'typed', x: 'typed', y: 'typed', keys: 'typed' },
  'ResponseComputerToolCall.Screenshot': { type: 'typed' },
  'ResponseComputerToolCall.Scroll': { scroll_x: 'typed', scroll_y: 'typed', type: 'typed', x: 'typed', y: 'typed', keys: 'typed' },
  'ResponseComputerToolCall.Type': { text: 'typed', type: 'typed' },
  'ResponseComputerToolCall.Wait': { type: 'typed' },
  ResponseComputerToolCallOutputItem: { id: 'not-integrated', call_id: 'native-controlled', output: 'typed', status: 'not-integrated', type: 'native-controlled', acknowledged_safety_checks: 'native-controlled', created_by: 'not-integrated' },
  'ResponseComputerToolCallOutputItem.AcknowledgedSafetyCheck': { id: 'native-controlled', code: 'native-controlled', message: 'native-controlled' },
  ResponseComputerToolCallOutputScreenshot: { type: 'typed', file_id: 'typed', image_url: 'typed' },
};
const reviewedTypes = JSON.parse(readFileSync(new URL('reviewed-types.json', dir), 'utf8'));
const eq = (a, b) => JSON.stringify([...a].sort()) === JSON.stringify([...b].sort());
export function project(text) {
  const source = ts.createSourceFile('responses.ts', text, ts.ScriptTarget.Latest, true);
  if (source.parseDiagnostics.length) throw new Error('Invalid upstream TypeScript');
  const printer = ts.createPrinter();
  const nodes = source.statements.filter(n => (ts.isInterfaceDeclaration(n) && selected.has(n.name.text)) || (ts.isModuleDeclaration(n) && namespaces.has(n.name.text)));
  return declarations(nodes.map(n => printer.printNode(ts.EmitHint.Unspecified, n, source)).join('\n'), 'selected.ts');
}
export function validate(decls, fixture) {
  if (!eq(Object.keys(decls), Object.keys(coverage))) throw new Error('Review changed computer declarations');
  for (const [name, fields] of Object.entries(coverage)) {
    if (!eq(decls[name].fields.map(f => f.name), Object.keys(fields))) throw new Error(`Review changed fields: ${name}`);
    for (const field of decls[name].fields) {
      if (JSON.stringify({type: field.type, optional: field.optional}) !== JSON.stringify(reviewedTypes[name]?.[field.name])) throw new Error(`Review changed type: ${name}.${field.name}`);
    }
  }
  const env = decls.ComputerUsePreviewTool.fields.find(f => f.name === 'environment').type;
  const values = [...env.matchAll(/'([^']+)'/g)].map(m => m[1]);
  if (!eq(values, ['windows', 'mac', 'linux', 'ubuntu', 'browser'])) throw new Error('Review changed preview environment enum');
  if (!fixture) return;
  const keys = (obj, name, extra = []) => {
    const expected = decls[name].fields.map(f => f.name);
    if (!eq(Object.keys(obj), [...expected, ...extra])) throw new Error(`Fixture fields differ from ${name}`);
  };
  keys(fixture.ga, 'ComputerTool');
  for (const preview of fixture.preview) keys(preview, 'ComputerUsePreviewTool');
  if (!eq(fixture.preview.map(p => p.environment), values)) throw new Error('Dart preview environments differ from upstream');
  const actionNames = { click: 'Click', double_click: 'DoubleClick', drag: 'Drag', keypress: 'Keypress', move: 'Move', screenshot: 'Screenshot', scroll: 'Scroll', type: 'Type', wait: 'Wait' };
  if (!eq(fixture.call.actions.map(a => a.type), Object.keys(actionNames))) throw new Error('Fixture must exercise every action');
  for (const action of fixture.call.actions) {
    keys(action, `ResponseComputerToolCall.${actionNames[action.type]}`);
    if (action.type === 'drag') for (const point of action.path) keys(point, 'ResponseComputerToolCall.Drag.Path');
  }
  const callFields = decls.ResponseComputerToolCall.fields.map(f => f.name).filter(n => !['action', 'pending_safety_checks'].includes(n));
  if (!eq(Object.keys(fixture.call), callFields)) throw new Error('GA call fields changed');
  for (const shot of fixture.screenshots) {
    const sourceFields = decls.ResponseComputerToolCallOutputScreenshot.fields.map(f => f.name);
    if (!eq(Object.keys(shot), sourceFields.filter(n => n !== (shot.file_id ? 'image_url' : 'file_id')).concat('detail'))) throw new Error('Screenshot fixture fields changed');
    if (shot.detail !== 'original') throw new Error('Screenshot detail fixture changed');
  }
  if (!eq(Object.keys(fixture.output), ['output']) || !eq(Object.keys(fixture.outputWithCheck), ['output', 'acknowledged_safety_checks'])) throw new Error('Acknowledgment omission changed');
  const check = fixture.outputWithCheck.acknowledged_safety_checks[0];
  keys(check, 'ResponseComputerToolCallOutputItem.AcknowledgedSafetyCheck');
  if (JSON.stringify(check) !== JSON.stringify({id: 'check', code: 'warning', message: 'review'})) throw new Error('Acknowledged checks differ from the approved call');
  if (fixture.screenshots.length !== 2 || !fixture.screenshots.some(s => s.file_id) || !fixture.screenshots.some(s => s.image_url)) throw new Error('Both screenshot forms are required');
}
async function main() {
  const flag = process.argv[2];
  if (process.argv.length !== 3 || !['--write', '--check', '--upstream'].includes(flag)) throw new Error('Expected --write, --check, or --upstream');
  const source = JSON.parse(await readFile(new URL('source.json', dir), 'utf8'));
  const bytes = await readFile(new URL('responses.ts', dir));
  const projected = project(bytes.toString());
  const fixture = flag === '--upstream' ? undefined : JSON.parse(await readFile(new URL('.dart_tool/computer-options.json', root), 'utf8'));
  validate(projected, fixture);
  if (flag === '--upstream') {
    const response = await fetch(`https://raw.githubusercontent.com/${source.repository}/main/${source.path}`);
    if (!response.ok) throw new Error(`Upstream HTTP ${response.status}`);
    if (JSON.stringify(project(await response.text())) !== JSON.stringify(projected)) throw new Error('Review changed upstream computer projection');
    console.log('Upstream computer projection matches pin'); return;
  }
  const doc = { ...source, sha256: createHash('sha256').update(bytes).digest('hex'), meaning: 'Selected Responses computer declarations only; not complete SDK or endpoint coverage.', notes: ['The pinned schema requires pending_safety_checks; the GA driver accepts its absence, while legacy action calls require it.', 'Screenshot detail is a separately documented driver extension absent from this Node pin.', 'Output ID, status and created_by are not integrated; native replay and runtime-owned fields are not public options.'], coverage, declarations: projected };
  const json = JSON.stringify(doc, null, 2) + '\n';
  const guide = '# OpenAI computer protocol inventory\n\nGenerated from the pinned official Node SDK. This is a selected protocol inventory, not full computer or endpoint coverage.\n\n' + doc.notes.map(n => `- ${n}`).join('\n') + '\n\n' + Object.entries(projected).map(([name, d]) => `## ${name}\n\n| Field | Source type | Disposition |\n| --- | --- | --- |\n${d.fields.map(f => `| ${f.name}${f.optional ? '?' : ''} | \`${f.type.replaceAll('|', '\\|')}\` | ${coverage[name][f.name]} |`).join('\n')}\n`).join('\n');
  for (const [path, content] of [['docs/computer-api-inventory.json', json], ['docs/computer-parameters.md', guide]]) {
    const url = new URL(path, root);
    if (flag === '--write') await writeFile(url, content);
    else if (await readFile(url, 'utf8') !== content) throw new Error(`Generated file is stale: ${path}`);
  }
  console.log(`Computer inventory ${flag.slice(2)} passed`);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main().catch(e => { console.error(e); process.exitCode = 1; });
