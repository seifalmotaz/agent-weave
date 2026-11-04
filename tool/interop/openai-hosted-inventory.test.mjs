import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { project, projectChat, validate, validateChat } from './openai-hosted-inventory.mjs';

const source = readFileSync(new URL('../contracts/openai-computer/responses.ts', import.meta.url), 'utf8');
const fixture = JSON.parse(readFileSync(new URL('../../.dart_tool/openai-hosted-options.json', import.meta.url), 'utf8'));
test('pinned hosted declarations match executable fixture', () => validate(project(source), fixture));
test('new hosted field requires review', () => assert.throws(() => validate(project(source.replace('export interface FileSearchTool {', 'export interface FileSearchTool { future?: string;')), fixture), /Review changed hosted/));
test('changed field type requires review', () => assert.throws(() => validate(project(source.replace('vector_store_ids: Array<string>;', 'vector_store_ids: Array<number>;')), fixture), /Review changed hosted/));
test('changed union requires review', () => assert.throws(() => validate(project(source.replaceAll("memory_limit?: '1g' | '4g' | '16g' | '64g' | null;", "memory_limit?: '1g' | '4g' | '16g' | '64g' | 'future' | null;")), fixture), /Review changed hosted/));
test('missing executable field fails', () => { const copy = structuredClone(fixture); delete copy['Tool.ImageGeneration'].quality; assert.throws(() => validate(project(source), copy), /Missing executable field/); });
test('nested data loss fails', () => { const copy = structuredClone(fixture); copy['Tool.CodeInterpreter'].container.network_policy = {}; assert.throws(() => validate(project(source), copy), /nested data changed/); });
test('reference declarations retain distinct native coordinates', () => {
  const declarations = project(source);
  assert.ok(declarations['ResponseOutputText.FileCitation'].fields.some(f => f.name === 'index'));
  assert.ok(declarations['ResponseOutputText.FilePath'].fields.some(f => f.name === 'index'));
  assert.equal(declarations['ResponseOutputText.FilePath'].fields.some(f => f.name === 'filename'), false);
  assert.ok(declarations['ResponseOutputText.ContainerFileCitation'].fields.some(f => f.name === 'start_index'));
  assert.ok(declarations.ResponseOutputTextAnnotationAddedEvent.fields.find(f => f.name === 'annotation').type.includes('null'));
});
test('new annotation event field requires review', () => {
  const changed = source.replace('export interface ResponseOutputTextAnnotationAddedEvent {', 'export interface ResponseOutputTextAnnotationAddedEvent { future?: string;');
  assert.throws(() => validate(project(changed), fixture), /Review changed hosted/);
});
test('Chat URL annotation declarations have a separate reviewed contract', () => {
  const chat = readFileSync(new URL('../contracts/openai-hosted/chat-completions.ts', import.meta.url), 'utf8');
  validateChat(projectChat(chat));
  assert.ok(projectChat(chat)['ChatCompletionMessage.Annotation'].fields.some(f => f.name === 'url_citation'));
  const changed = chat.replace('export namespace ChatCompletionMessage {', 'export namespace ChatCompletionMessage { export interface FutureAnnotation { extra: string; }');
  assert.throws(() => validateChat(projectChat(changed)), /Review changed Chat/);
});

test('MCP configuration and stream changes require review', () => {
  const changed = source.replaceAll('export interface Mcp {', 'export interface Mcp { future?: string;');
  assert.throws(() => validate(project(changed), fixture), /Review changed hosted/);
  const stream = source.replace('  | ResponseMcpCallArgumentsDeltaEvent\n', '  | ResponseMcpCallArgumentsDeltaEvent\n  | FutureMcpEvent\n');
  assert.throws(() => validate(project(stream), fixture), /Review changed hosted/);
});
test('MCP executable snapshots exclude credentials', () => {
  for (const value of Object.values(fixture.Mcp)) {
    assert.equal('authorization' in value, false);
    assert.equal('headers' in value, false);
  }
  const copy = structuredClone(fixture);
  delete copy.Mcp.server.allowed_tools.read_only;
  assert.throws(() => validate(project(source), copy), /Missing executable field/);
});
