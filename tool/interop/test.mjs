import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { ChatClient, GenerationClient, fetchServerSentEvents } from '@tanstack/ai-client';
import { toolDefinition } from '@tanstack/ai';

const server = spawn('dart', ['run', 'tool/interop/server.dart'], {
  cwd: new URL('../../', import.meta.url), stdio: ['ignore', 'pipe', 'inherit'],
});
const lines = createInterface({ input: server.stdout });
const timeout = setTimeout(() => { server.kill(); throw new Error('Interop timed out'); }, 30000);
let base;
try {
  for await (const line of lines) {
    try { base = `http://127.0.0.1:${JSON.parse(line).port}`; break; }
    catch { /* Dart may print its build-hook status before the server address. */ }
  }
  assert.ok(base, 'Dart server must start');
  const inputSchema = { type: 'object', properties: { count: { type: 'integer' } },
    required: ['count'], additionalProperties: false };
  for (const scenario of ['text', 'tool', 'approval', 'client', 'reasoning', 'structured']) {
    const chat = new ChatClient({
      threadId: scenario, connection: fetchServerSentEvents(`${base}/${scenario === 'structured' ? 'structured' : 'chat'}`),
      tools: [toolDefinition({ name: 'gate', description: 'Double', inputSchema,
        outputSchema: { type: 'integer' }, needsApproval: true }).client(),
        toolDefinition({ name: 'clientDouble', description: 'Double on the client',
          inputSchema, outputSchema: { type: 'integer' } }).client(({ count }) => count * 2)],
    });
    try {
      await chat.sendMessage(scenario === 'text' ? 'Hello' : scenario);
      assert.equal(chat.getError(), undefined);
      if (scenario === 'approval') {
        const [interrupt] = chat.getInterrupts();
        assert.equal(interrupt.kind, 'tool-approval');
        assert.equal(interrupt.canResolve, true);
        interrupt.resolveInterrupt(true);
      }
      if (scenario === 'approval' || scenario === 'client') {
        for (let i = 0; i < 100; i++) {
          if (chat.getMessages().some(m => m.parts.some(p => p.type === 'text' && p.content === 'Result: 4'))) break;
          await new Promise(resolve => setTimeout(resolve, 10));
        }
      }
      const text = chat.getMessages().flatMap(m => m.parts)
        .filter(p => p.type === 'text').map(p => p.content).join('|');
      if (scenario === 'structured') {
        const part = chat.getMessages().flatMap(m => m.parts).find(p => p.type === 'structured-output');
        assert.deepEqual(part?.data, { answer: 42 });
      } else {
        assert.ok(text.includes(['text', 'reasoning'].includes(scenario) ? 'Hello from Dart' : 'Result: 4'), JSON.stringify({text, error: chat.getError()?.message, interrupts: chat.getInterruptState()}));
      }
      assert.equal(chat.getError(), undefined);
      console.log(`PASS official JS client: ${scenario}`);
    } finally { chat.dispose(); }
  }
  const generation = new GenerationClient({ threadId: 'generation',
    connection: fetchServerSentEvents(`${base}/generation`) });
  try {
    await generation.generate({ prompt: 'Offline fixture' });
    assert.equal(generation.getError(), undefined);
    assert.deepEqual(generation.getResult(), { answer: 42 });
    console.log('PASS official JS client: generation');
  } finally { generation.dispose(); }
} finally {
  clearTimeout(timeout);
  if (base) await fetch(`${base}/shutdown`).catch(() => {});
  server.kill();
  lines.close();
}
