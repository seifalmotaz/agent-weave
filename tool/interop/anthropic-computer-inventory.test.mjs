import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { projection } from './anthropic-computer-inventory.mjs';

const source = await readFile(new URL('../contracts/anthropic/messages.ts', import.meta.url), 'utf8');
const baseline = projection(source);
test('covers all members and wire result and caller declarations', () => {
  assert.equal(baseline.ComputerToolsetConfigs.fields.length, 17);
  assert.equal(Object.keys(baseline).filter(name => /^Computer.*Input$/.test(name) && name !== 'ComputerMemberInput').length, 17);
  assert.ok(baseline.ToolResultBlockParam.fields.some(field => field.name === 'toolset_name'));
  assert.ok(baseline.ToolUseCaller.type.includes('DirectCaller'));
});
test('detects input, union, config and result drift', () => {
  for (const [before, after] of [
    ['export interface ComputerKeyInput {', 'export interface ComputerKeyInput {\n  extra: string;'],
    ['export type ComputerMemberName =\n  |', 'export type ComputerMemberName =\n  | \'new_action\'\n  |'],
    ['export interface ComputerToolsetConfigs {', 'export interface ComputerToolsetConfigs {\n  extra?: string;'],
    ['export interface ToolResultBlockParam {', 'export interface ToolResultBlockParam {\n  extra?: string;'],
  ]) {
    assert.ok(source.includes(before));
    assert.notDeepEqual(projection(source.replace(before, after)), baseline);
  }
});
