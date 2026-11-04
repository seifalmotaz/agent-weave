import assert from 'node:assert/strict';
import { ChatClient, GenerationClient, fetchServerSentEvents } from '@tanstack/ai-client';

const base = process.argv[2];
assert.ok(base?.startsWith('http://localhost:'), 'Pass the local Serverpod test URL');
const chat = new ChatClient({ threadId: 'official-js-serverpod',
  connection: fetchServerSentEvents(`${base}/test/chat`) });
try {
  await chat.sendMessage('Hello from JavaScript');
  assert.equal(chat.getError(), undefined);
  assert.equal(chat.getMessages().at(-1).parts.find(p => p.type === 'text').content,
    'AgentWeave received: Hello from JavaScript');
  await chat.sendMessage('Second turn');
  assert.equal(chat.getError(), undefined);
  const response = await fetch(`${base}/test/chat?threadId=official-js-serverpod`);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).messages.length, 4);
  console.log('PASS official JS client: real Serverpod chat, second turn, history');
} finally { chat.dispose(); }
const generation = new GenerationClient({ threadId: 'official-generation-serverpod',
  connection: fetchServerSentEvents(`${base}/test/generation`) });
try {
  await generation.generate({ count: 21 });
  assert.equal(generation.getError(), undefined);
  assert.deepEqual(generation.getResult(), { answer: 42 });
  console.log('PASS official JS client: real Serverpod generation');
} finally { generation.dispose(); }
