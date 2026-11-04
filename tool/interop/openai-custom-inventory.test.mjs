import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { projection, validate, renderDeclarations } from './openai-custom-inventory.mjs';

const response = readFileSync(new URL('../contracts/openai-computer/responses.ts', import.meta.url), 'utf8');
const shared = readFileSync(new URL('../contracts/openai-custom/shared.ts', import.meta.url), 'utf8');
const reviewed = JSON.parse(readFileSync(new URL('../contracts/openai-custom/reviewed-declarations.json', import.meta.url), 'utf8'));
const source = JSON.parse(readFileSync(new URL('../contracts/openai-custom/source.json', import.meta.url), 'utf8'));
const digest = value => createHash('sha256').update(value).digest('hex');

test('pinned source and selected declarations match review', () => {
  assert.equal(digest(response), source.responsesSha256);
  assert.equal(digest(shared), source.sharedSha256);
  validate(projection(response, shared), reviewed);
});
test('new custom field requires review', () => {
  assert.throws(() => validate(projection(response.replace('export interface CustomTool {', 'export interface CustomTool { future?: string;'), shared), reviewed), /Review changed/);
});
test('new nested grammar field requires review', () => {
  assert.throws(() => validate(projection(response, shared.replace('export interface Grammar {', 'export interface Grammar { future?: boolean;')), reviewed), /Review changed/);
});
test('changed grammar union requires review', () => {
  assert.throws(() => validate(projection(response, shared.replace("syntax: 'lark' | 'regex';", "syntax: 'lark' | 'regex' | 'future';")), reviewed), /Review changed/);
});
test('removed root is rejected', () => {
  assert.throws(() => projection(response.replace('export interface ResponseCustomToolCallInputDoneEvent {', 'export interface RemovedCustomToolCallInputDoneEvent {'), shared), /Missing response root/);
});
test('changed call event identity field requires review', () => {
  const changed = response.replace('export interface ResponseCustomToolCallInputDoneEvent {', 'export interface ResponseCustomToolCallInputDoneEvent { extra_id?: string;');
  assert.throws(() => validate(projection(changed, shared), reviewed), /Review changed/);
});
test('fixture catches missing executable keys', () => {
  assert.throws(() => validate(projection(response, shared), reviewed, {namespace: {type: 'namespace'}}), /Executable fixture fields differ/);
});

test('namespaced functions and program callers are not declared integrated', () => {
  const doc = JSON.parse(readFileSync(new URL('../../docs/openai-custom-inventory.json', import.meta.url), 'utf8'));
  assert.match(doc.scope, /namespaced function tools.*not integrated/);
  assert.equal(doc.dispositions['responses.NamespaceTool.Function'].name, 'not integrated: namespaced function tool');
  assert.equal(doc.dispositions['responses.ResponseCustomToolCall.Program'].caller_id, 'not integrated: programmatic caller');
});

for (const name of ['Tool', 'ResponseInputItem', 'ResponseOutputItem', 'ResponseStreamEvent']) {
  test(`new ${name} union member requires review`, () => {
    const changed = response.replace(`export type ${name} =`, `export type ${name} =\n  | FutureCustomMember`);
    assert.notEqual(changed, response);
    assert.throws(() => validate(projection(changed, shared), reviewed), /Review changed/);
  });
}
test('removed union root is rejected', () => {
  assert.throws(() => projection(response.replace('export type ResponseOutputItem =', 'export type RemovedOutputItem ='), shared), /Missing response root ResponseOutputItem/);
});
test('choice declaration changes require review', () => {
  assert.throws(() => validate(projection(response.replace('export interface ToolChoiceCustom {', 'export interface ToolChoiceCustom { future?: boolean;'), shared), reviewed), /Review changed/);
});

test('Markdown renders every field in one intact table row', () => {
  const rendered = renderDeclarations(projection(response, shared));
  const rows = rendered.split('\n').filter(line => line.startsWith('| '));
  const expected = Object.values(reviewed).flatMap(group => Object.values(group)).filter(d => d.fields).reduce((sum, d) => sum + d.fields.length, 0);
  assert.equal(rows.filter(line => !line.startsWith('| Field |') && !line.startsWith('| --- |')).length, expected);
  assert.ok(rows.every(line => line.endsWith(' |')));
  assert.match(rendered, /\| output_schema\? \| `\{ \[key: string\]: unknown; \} \\\| null` \|/);
  assert.match(rendered, /Shallow union signature; variants are not all integrated\.\n\n```ts/);
  assert.match(renderDeclarations({test: {X: {fields: [{name: 'x', type: '`x` | y\n  z'}]}}}), /&#96;x&#96; \\\| y z/);
});
