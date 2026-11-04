import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { project, validate } from './openai-hosted-inventory.mjs';

const source = readFileSync(new URL('../contracts/openai-computer/responses.ts', import.meta.url), 'utf8');
const fixture = JSON.parse(readFileSync(new URL('../../.dart_tool/openai-hosted-options.json', import.meta.url), 'utf8'));
test('pinned hosted declarations match executable fixture', () => validate(project(source), fixture));
test('new hosted field requires review', () => assert.throws(() => validate(project(source.replace('export interface FileSearchTool {', 'export interface FileSearchTool { future?: string;')), fixture), /Review changed hosted/));
test('changed field type requires review', () => assert.throws(() => validate(project(source.replace('vector_store_ids: Array<string>;', 'vector_store_ids: Array<number>;')), fixture), /Review changed hosted/));
test('changed union requires review', () => assert.throws(() => validate(project(source.replaceAll("memory_limit?: '1g' | '4g' | '16g' | '64g' | null;", "memory_limit?: '1g' | '4g' | '16g' | '64g' | 'future' | null;")), fixture), /Review changed hosted/));
test('missing executable field fails', () => { const copy = structuredClone(fixture); delete copy['Tool.ImageGeneration'].quality; assert.throws(() => validate(project(source), copy), /Missing executable field/); });
test('nested data loss fails', () => { const copy = structuredClone(fixture); copy['Tool.CodeInterpreter'].container.network_policy = {}; assert.throws(() => validate(project(source), copy), /nested data changed/); });
