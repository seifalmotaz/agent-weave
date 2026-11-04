import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import assert from 'node:assert/strict';
import { projection, validate, validateFixture, roots } from './anthropic-mcp-inventory.mjs';
const root = new URL('../../', import.meta.url);
const bytes = await readFile(new URL('../contracts/anthropic-mcp/messages.ts', import.meta.url));
const source = bytes.toString();
const reviewed = JSON.parse(await readFile(new URL('../contracts/anthropic-mcp/reviewed-declarations.json', import.meta.url), 'utf8'));
const baseline = projection(source);
const fixture = JSON.parse(execFileSync('dart', ['run', 'tool/anthropic_mcp_contract.dart'], {cwd: fileURLToPath(root), encoding: 'utf8'}));
const digest = text => createHash('sha256').update(text).digest('hex');

test('selected pinned declarations and Dart fixture agree', () => {
  assert.equal(roots.length, 14);
  validate(baseline, bytes);
  validateFixture(baseline, fixture);
  assert.match(baseline.BetaMCPToolResultBlock.fields.find(f => f.name === 'content').type, /string \| Array<BetaTextBlock>/);
});
test('changed source bytes fail even outside the projection', () => assert.throws(() => validate(baseline, source + '\n'), /source bytes changed/));
test('new MCP root needs classification', () => assert.throws(() => projection(source + '\nexport interface BetaMCPNew { x: string; }'), /MCP root/));
test('nested declaration and result union drift require review', () => {
  for (const changed of [
    source.replace('export interface BetaMCPToolConfig {', 'export interface BetaMCPToolConfig {\n  future?: boolean;'),
    source.replace('content: string | Array<BetaTextBlock>;', 'content: string | Array<BetaTextBlock> | number;'),
  ]) {
    assert.throws(() => validate(projection(changed), changed, {...reviewed, sourceSha256: digest(changed)}), /Review changed MCP/);
  }
});
test('missing root and executable nested fields fail', () => {
  assert.throws(() => projection(source.replace('export interface BetaMCPToolset {', 'export interface BetaMCPToolsetRenamed {')), /MCP root/);
  const copy = structuredClone(fixture); delete copy.toolset.configs.read.enabled;
  assert.throws(() => validateFixture(baseline, copy), /fixture fields/);
});
test('unexpected source and fixture fields cannot silently enter coverage', () => {
  const copy = structuredClone(fixture); copy.legacy.extra = true;
  assert.throws(() => validateFixture(baseline, copy), /fixture fields/);
  copy.legacyResolvedFields.push('future');
  assert.throws(() => validateFixture(baseline, copy), /fixture fields/);
});
