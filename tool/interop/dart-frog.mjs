import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { ChatClient, GenerationClient, fetchServerSentEvents } from '@tanstack/ai-client';
import { toolDefinition } from '@tanstack/ai';

const server = spawn('dart', ['run', 'tool/interop/dart_frog_server.dart'], {
  cwd: new URL('../../', import.meta.url), stdio: ['ignore', 'pipe', 'inherit'],
});
const lines = createInterface({ input: server.stdout });
const timeout = setTimeout(() => { server.kill(); throw new Error('Interop timed out'); }, 30000);
let base;
const headers = { Authorization: 'Bearer alice' };
const schema = { type: 'object', properties: { count: { type: 'integer' } }, required: ['count'], additionalProperties: false };
try {
  for await (const line of lines) {
    try { base = `http://127.0.0.1:${JSON.parse(line).port}`; break; } catch { /* Build output can precede the port. */ }
  }
  assert.ok(base);
  assert.equal((await fetch(`${base}/chat?threadId=text`)).status, 401);
  for (const scenario of ['text', 'schema', 'approval']) {
    const path = scenario === 'schema' ? 'structured' : 'chat';
    const chat = new ChatClient({ threadId: scenario, connection: fetchServerSentEvents(`${base}/${path}`, { headers }),
      tools: [toolDefinition({ name: 'gate', description: 'Double', inputSchema: schema, outputSchema: { type: 'integer' }, needsApproval: true }).client()] });
    try {
      await chat.sendMessage(scenario);
      assert.equal(chat.getError(), undefined);
      if (scenario === 'approval') {
        assert.deepEqual(await (await fetch(`${base}/state`)).json(), {requests: 3, effects: 0, failures: []});
        const [interrupt] = chat.getInterrupts();
        assert.equal(interrupt.kind, 'tool-approval');
        interrupt.resolveInterrupt(true);
        for (let i = 0; i < 100 && !chat.getMessages().some(m => m.parts.some(p => p.type === 'text' && p.content === 'Result: 4')); i++) await new Promise(resolve => setTimeout(resolve, 10));
      }
      assert.equal(chat.getError(), undefined);
      const parts = chat.getMessages().flatMap(m => m.parts);
      if (scenario === 'schema') assert.deepEqual(parts.find(p => p.type === 'structured-output')?.data, { answer: 42 });
      else assert.ok(parts.some(p => p.type === 'text' && p.content === (scenario === 'text' ? 'Hello from Ollama' : 'Result: 4')), JSON.stringify(parts));
      const history = await (await fetch(`${base}/${path}?threadId=${scenario}`, {headers})).json();
      const serialized = JSON.stringify(history);
      for (const secret of ['private-thinking', 'private-field', 'private-native-id', 'private-meta', 'ollama.chat']) assert.equal(serialized.includes(secret), false);
      if (scenario === 'approval') assert.ok(serialized.includes('4'));
      const other = await (await fetch(`${base}/${path}?threadId=${scenario}`, {headers: {Authorization: 'Bearer bob'}})).json();
      assert.equal(other.messages.length, 0);
      console.log(`PASS official JS client through Dart Frog and Ollama: ${scenario}`);
    } finally { chat.dispose(); }
  }
  assert.deepEqual(await (await fetch(`${base}/state`)).json(), {requests: 4, effects: 1, failures: []});
  const generation = new GenerationClient({threadId: 'generation', connection: fetchServerSentEvents(`${base}/generation`, {headers})});
  try {
    await generation.generate({prompt: 'ok'});
    assert.equal(generation.getError(), undefined);
    assert.deepEqual(generation.getResult(), {answer: 42});
    console.log('PASS official JS client through Dart Frog: authenticated generation');
  } finally { generation.dispose(); }
  const failed = await fetch(`${base}/generation`, {method: 'POST', headers: {...headers, 'Content-Type': 'application/json'}, body: JSON.stringify({threadId: 'failure', runId: 'failure', forwardedProps: {prompt: 'fail'}})});
  const failedText = await failed.text();
  assert.ok(failedText.includes('GENERATION_FAILED'));
  assert.equal(failedText.includes('private-generation-error'), false);
} finally {
  clearTimeout(timeout);
  server.kill();
  lines.close();
}
