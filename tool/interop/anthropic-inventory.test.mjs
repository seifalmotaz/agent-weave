import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { projection, validateCoverage } from './anthropic-inventory.mjs';

const source = await readFile(new URL('../contracts/anthropic/messages.ts', import.meta.url), 'utf8');
const coverage = JSON.parse(await readFile(new URL('../contracts/anthropic/coverage.json', import.meta.url), 'utf8'));
const baseline = projection(source);

test('includes request, nested content unions and stream declarations', () => {
  assert.ok(baseline.MessageCreateParamsBase.fields.some(f => f.name === 'messages'));
  assert.ok(baseline.ContentBlockParam.type.includes('ToolUseBlockParam'));
  assert.ok(baseline.ToolUseBlockParam.fields.some(f => f.name === 'input'));
  assert.ok(baseline.RawMessageStreamEvent.type.includes('RawMessageDeltaEvent'));
  assert.ok(baseline['Tool.InputSchema']);
});
test('detects nested type drift', () => {
  const changed = source.replace('export interface ToolUseBlockParam {', 'export interface ToolUseBlockParam {\n  added_field?: string;');
  assert.notDeepEqual(projection(changed), baseline);
});
test('detects changes to selected union', () => {
  const changed = source.replace('export type RawMessageStreamEvent =\n  | RawMessageStartEvent', 'export type RawMessageStreamEvent =\n  | string\n  | RawMessageStartEvent');
  assert.notDeepEqual(projection(changed), baseline);
});
test('requires exact request field dispositions', () => {
  validateCoverage(baseline.MessageCreateParamsBase.fields, coverage);
  assert.throws(() => validateCoverage([...baseline.MessageCreateParamsBase.fields, {name: 'new_field'}], coverage), /disposition/);
  assert.throws(() => validateCoverage(baseline.MessageCreateParamsBase.fields, {...coverage, stale: {status: 'native-json', detail: 'x'}}), /disposition/);
});
