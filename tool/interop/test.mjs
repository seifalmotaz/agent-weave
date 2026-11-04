import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { ChatClient, GenerationClient, fetchServerSentEvents } from '@tanstack/ai-client';
import { toolDefinition } from '@tanstack/ai';
import { ContentPartSchema, CustomEventSchema } from '@ag-ui/core/schemas';

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
  const refSchema = { type: 'object', $defs: { number: { type: 'integer', minimum: 1 } },
    properties: { count: { $ref: '#/$defs/number' } }, required: ['count'], additionalProperties: false };
  for (const [scenario, value, valid] of [['ref-valid', 3, true], ['ref-invalid', 'invalid', false]]) {
    const chat = new ChatClient({ threadId: scenario, connection: fetchServerSentEvents(`${base}/chat`),
      tools: [toolDefinition({ name: 'refGate', description: 'Double with local ref', inputSchema: refSchema,
        outputSchema: { type: 'integer' }, needsApproval: true }).client()] });
    try {
      await chat.sendMessage('ref-approval');
      assert.equal(chat.getError(), undefined);
      const before = await (await fetch(`${base}/ref-state`)).json();
      assert.deepEqual(before, valid ? [] : [3]);
      const [interrupt] = chat.getInterrupts();
      assert.equal(interrupt.kind, 'tool-approval');
      assert.equal(interrupt.canResolve, true);
      assert.deepEqual(await (await fetch(`${base}/ref-state`)).json(), before);
      interrupt.resolveInterrupt(true, { editedArgs: { count: value } });
      for (let i = 0; i < 100; i++) {
        if (chat.getError() || chat.getMessages().some(m => m.parts.some(p => p.type === 'text' && p.content === 'Result: 6'))) break;
        await new Promise(resolve => setTimeout(resolve, 10));
      }
      const after = await (await fetch(`${base}/ref-state`)).json();
      if (valid) {
        assert.equal(chat.getError(), undefined);
        assert.deepEqual(after, [...before, 3]);
        assert.ok(chat.getMessages().some(m => m.parts.some(p => p.type === 'text' && p.content === 'Result: 6')));
      } else {
        assert.equal(chat.getError()?.code, 'INVALID_INPUT');
        assert.equal(chat.getError()?.message, 'Invalid input or provider output.');
        assert.deepEqual(after, before);
      }
      console.log(`PASS official JS client: local ref edited approval ${scenario}`);
    } finally { chat.dispose(); }
  }
  for (const scenario of ['text', 'tool', 'approval', 'client', 'reasoning', 'structured', 'pause', 'structured-pause']) {
    const chat = new ChatClient({
      threadId: scenario, connection: fetchServerSentEvents(`${base}/${scenario.startsWith('structured') ? 'structured' : 'chat'}`),
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
      if (scenario.startsWith('structured')) {
        const part = chat.getMessages().flatMap(m => m.parts).find(p => p.type === 'structured-output' && p.data !== undefined);
        assert.deepEqual(part?.data, { answer: 42 });
        const structured = chat.getMessages().flatMap(m => m.parts).filter(p => p.type === 'structured-output');
        assert.equal(structured.length, 1, JSON.stringify(structured));
        assert.equal(structured[0].status, 'complete');
        if (scenario === 'structured-pause') {
          await chat.sendMessage('structured-pause');
          assert.equal(chat.getError(), undefined);
          const outputs = chat.getMessages().flatMap(m => m.parts).filter(p => p.type === 'structured-output');
          assert.equal(outputs.length, 2, JSON.stringify(outputs));
          assert.ok(outputs.every(p => p.status === 'complete'));
          const history = await (await fetch(`${base}/structured-history?threadId=${scenario}`)).json();
          const saved = history.messages.flatMap(m => m.parts).filter(p => p.type === 'structured-output');
          assert.deepEqual(saved.map(p => p.data), [{ answer:42 }, { answer:42 }]);
          const restored = new ChatClient({threadId: scenario, connection: fetchServerSentEvents(`${base}/structured`), initialMessages: history.messages});
          try {
            assert.deepEqual(restored.getMessages().flatMap(m => m.parts).filter(p => p.type === 'structured-output').map(p => p.data), [{answer:42}, {answer:42}]);
          } finally { restored.dispose(); }
        }
      } else {
        assert.ok(text.includes(['text', 'reasoning', 'pause'].includes(scenario) ? 'Hello from Dart' : 'Result: 4'), JSON.stringify({text, error: chat.getError()?.message, interrupts: chat.getInterruptState()}));
      }
      assert.equal(chat.getError(), undefined);
      assert.equal(JSON.stringify(chat.getMessages()).includes('PRIVATE-PAUSE'), false);
      console.log(`PASS official JS client: ${scenario}`);
    } finally { chat.dispose(); }
  }
  const seenCitations = [];
  const citationPositions = new Map();
  const seenReferences = [];
  const referencePositions = new Map();
  let citationRunId;
  const citationConnection = fetchServerSentEvents(`${base}/citations`);
  function recordCitation(name, value) {
    if (name === 'agent_weave:reference') {
      CustomEventSchema.parse({type: 'CUSTOM', name, value});
      seenReferences.push(value);
      referencePositions.set(`${value.messageId}:${value.referenceIndex}`, value.reference);
      return;
    }
    if (name !== 'agent_weave:citation') return;
    CustomEventSchema.parse({type: 'CUSTOM', name, value});
    seenCitations.push(value);
    citationPositions.set(`${value.messageId}:${value.citationIndex}`, value.citation);
  }
  const citations = new ChatClient({
    threadId: 'citations', connection: citationConnection,
    onChunk(chunk) { if (chunk.type === 'RUN_STARTED') citationRunId = chunk.runId; },
    onCustomEvent: recordCitation,
  });
  try {
    await citations.sendMessage('Summarize');
    assert.equal(citations.getError(), undefined);
    const live = citations.getMessages().find(m => m.role === 'assistant');
    assert.equal(live.parts.filter(p => p.type === 'text').map(p => p.content).join(''), 'A 🌿 grows.');
    assert.equal(seenCitations.length, 2);
    assert.deepEqual(seenCitations.map(c => c.citationIndex), [0, 1]);
    assert.equal(seenCitations[0].messageId, live.id);
    const annotations = live.metadata.agent_weave.citations;
    const references = live.metadata.agent_weave.references;
    assert.equal(references.length, 2);
    assert.deepEqual(references, seenReferences.map(r => r.reference));
    assert.deepEqual(seenReferences.map(r => r.referenceIndex), [0, 1]);
    assert.equal(references[0].source.fileId, 'file-visible');
    assert.equal(references[0].position.type, 'file_list');
    assert.equal(references[0].position.index, 99);
    assert.equal(references[0].source.filename, undefined);
    assert.deepEqual(annotations, seenCitations.map(c => c.citation));
    assert.deepEqual(annotations[0], annotations[1]);
    assert.equal('A 🌿 grows.'.slice(annotations[0].start, annotations[0].end), '🌿');
    const history = await (await fetch(`${base}/citations-history?threadId=citations`)).json();
    assert.equal(JSON.stringify(history).includes('PRIVATE-CITATION'), false);
    assert.deepEqual(history.messages.find(m => m.role === 'assistant').metadata, live.metadata);
    const restored = new ChatClient({threadId: 'citations', connection: fetchServerSentEvents(`${base}/citations`), initialMessages: history.messages});
    try {
      assert.deepEqual(restored.getMessages().find(m => m.role === 'assistant').metadata, live.metadata);
    } finally { restored.dispose(); }
    // Feed the actual adapter's read-only GET replay through the official processor.
    const replay = new ChatClient({
      threadId: 'citations',
      connection: {connect: () => citationConnection.joinRun(citationRunId)},
      onCustomEvent: recordCitation,
    });
    try {
      await replay.sendMessage('Read stored log');
      assert.equal(replay.getError(), undefined);
      assert.equal(seenCitations.length, 4);
      assert.equal(citationPositions.size, 2);
      assert.equal(seenReferences.length, 4);
      assert.equal(referencePositions.size, 2);
      assert.deepEqual([...referencePositions.values()], references);
      assert.deepEqual([...citationPositions.values()], annotations);
      assert.deepEqual(replay.getMessages().find(m => m.role === 'assistant').metadata, live.metadata);
    } finally { replay.dispose(); }
    console.log('PASS official JS client: citations/references, duplicate-safe replay, snapshot and hydration');
  } finally { citations.dispose(); }
  const media = new ChatClient({threadId: 'output-media', connection: fetchServerSentEvents(`${base}/media`)});
  try {
    await media.sendMessage('Draw');
    assert.equal(media.getError(), undefined);
    const parts = media.getMessages().find(m => m.role === 'assistant').parts;
    assert.deepEqual(parts.map(p => p.type), ['text', 'image', 'text']);
    assert.equal(parts[0].content, 'before');
    assert.equal(parts[2].content, 'after');
    ContentPartSchema.parse(parts[1]);
    assert.match(parts[1].source.value, /^data:image\/png;base64,/);
    assert.equal(Buffer.from(parts[1].source.value.split(',')[1], 'base64').readUInt32BE(0), 0x89504e47);
    const history = await (await fetch(`${base}/media-history?threadId=output-media`)).json();
    assert.deepEqual(history.messages.find(m => m.role === 'assistant').parts, parts);
    assert.equal(JSON.stringify(history).includes('PRIVATE-MEDIA'), false);
    const restored = new ChatClient({threadId: 'output-media', connection: fetchServerSentEvents(`${base}/media`), initialMessages: history.messages});
    try { assert.deepEqual(restored.getMessages().find(m => m.role === 'assistant').parts, parts); }
    finally { restored.dispose(); }
    console.log('PASS official JS client: ordered output image and private history');
  } finally { media.dispose(); }
  for (const [name, part] of [
    ['document-url', { type: 'document', source: { type: 'url', value: 'https://example.com/report.pdf' }, metadata: { filename: 'report.pdf' } }],
    ['document-data', { type: 'document', source: { type: 'data', value: 'UERG', mimeType: 'application/pdf' } }],
    ['document-file', { type: 'document', source: { type: 'file', value: 'file-1', provider: 'openai' } }],
    ['document-unscoped-file', { type: 'document', source: { type: 'file', value: 'legacy-file' } }],
    ['image-url', { type: 'image', source: { type: 'url', value: 'https://example.com/image.png' } }],
    ['video-url', { type: 'video', source: { type: 'url', value: 'https://example.com/video.mp4' } }],
    ['audio-data', { type: 'audio', source: { type: 'data', value: 'UklGRg==', mimeType: 'audio/mpeg' } }],
  ]) {
    ContentPartSchema.parse(part);
    const chat = new ChatClient({ threadId: name, connection: fetchServerSentEvents(`${base}/chat`) });
    try {
      await chat.sendMessage({ content: [part] });
      assert.equal(chat.getError(), undefined);
      const expected = { type: part.source.type, value: part.source.value };
      if (part.type === 'document') Object.assign(expected, part.source);
      const reply = chat.getMessages().filter(m => m.role === 'assistant').flatMap(m => m.parts).find(p => p.type === 'text');
      assert.deepEqual(JSON.parse(reply.content), [expected]);
      const response = await fetch(`${base}/history?threadId=${name}`);
      assert.equal(response.status, 200);
      const history = await response.json();
      const [restored] = history.messages.find(m => m.role === 'user').parts;
      ContentPartSchema.parse(restored);
      assert.deepEqual(restored, part);
      const fresh = new ChatClient({ threadId: name, connection: fetchServerSentEvents(`${base}/chat`), initialMessages: history.messages });
      try { assert.deepEqual(fresh.getMessages()[0].parts, [part]); }
      finally { fresh.dispose(); }
      console.log(`PASS official JS client: ${name} and history`);
    } finally { chat.dispose(); }
  }
  for (const approved of [true, false]) {
    const threadId = approved ? 'native-approval' : 'native-denial';
    const chat = new ChatClient({ threadId, connection: fetchServerSentEvents(`${base}/native`) });
    try {
      await chat.sendMessage('computer');
      assert.equal(chat.getError(), undefined);
      const [interrupt] = chat.getInterrupts();
      assert.equal(interrupt.kind, 'generic');
      assert.equal(interrupt.canResolve, true);
      interrupt.resolveInterrupt({ approved });
      let history;
      for (let i = 0; i < 100; i++) {
        history = await (await fetch(`${base}/native-history?threadId=${threadId}`)).json();
        if (history.interrupts === null) break;
        await new Promise(resolve => setTimeout(resolve, 10));
      }
      assert.equal(history.interrupts, null);
      assert.equal(chat.getError(), undefined);
      assert.equal(chat.getInterrupts().length, 0);
      const serialized = JSON.stringify(history);
      assert.equal(serialized.includes('private-native-replay'), false);
      assert.equal(serialized.includes('private-native-environment'), false);
      assert.equal(serialized.includes('fixture.native'), false);
      const nativePart = history.messages.flatMap(message => message.parts).find(part => part.type === 'tool-call');
      const restored = new ChatClient({ threadId, connection: fetchServerSentEvents(`${base}/native`), initialMessages: history.messages });
      try {
        const part = restored.getMessages().flatMap(message => message.parts).find(part => part.type === 'tool-call');
        assert.equal(part.id, 'native-call');
        assert.equal(part.name, 'nativeGate');
      } finally { restored.dispose(); }
      if (approved) assert.equal(nativePart.output, 'captured');
      else assert.equal(Object.hasOwn(nativePart, 'output'), false);
      console.log(`PASS official JS client: native ${approved ? 'approval' : 'denial'} and private history`);
    } finally { chat.dispose(); }
  }
  {
    const threadId = 'mixed-computer';
    const chat = new ChatClient({ threadId, connection: fetchServerSentEvents(`${base}/mixed`) });
    try {
      await chat.sendMessage('computer');
      assert.equal(chat.getError(), undefined);
      const interrupts = chat.getInterrupts();
      assert.equal(interrupts.length, 3);
      assert.ok(interrupts.every(item => item.kind === 'generic' && item.canResolve));
      assert.deepEqual(await (await fetch(`${base}/mixed-state`)).json(), {computer: 0, ordinary: 0});
      const before = await (await fetch(`${base}/mixed-history?threadId=${threadId}`)).json();
      const nativePending = before.interrupts.pending.filter(item => item.toolCallId.startsWith('computer-'));
      assert.equal(nativePending.length, 2);
      for (const item of nativePending) assert.deepEqual(item.responseSchema, {
        type: 'object', properties: { approved: { type: 'boolean' } },
        required: ['approved'], additionalProperties: false,
      });
      assert.equal(JSON.stringify(before).includes('private-mixed-replay'), false);
      assert.equal(JSON.stringify(before).includes('private-mixed-environment'), false);
      for (const interrupt of interrupts) interrupt.resolveInterrupt({ approved: true });
      for (let i = 0; i < 100; i++) {
        if (chat.getMessages().some(m => m.parts.some(p => p.type === 'text' && p.content === 'Mixed completed'))) break;
        await new Promise(resolve => setTimeout(resolve, 10));
      }
      assert.equal(chat.getError(), undefined);
      assert.ok(chat.getMessages().some(m => m.parts.some(p => p.type === 'text' && p.content === 'Mixed completed')));
      assert.deepEqual(await (await fetch(`${base}/mixed-state`)).json(), {computer: 1, ordinary: 0});
      const after = await (await fetch(`${base}/mixed-history?threadId=${threadId}`)).json();
      assert.equal(JSON.stringify(after).includes('private-mixed-replay'), false);
      assert.equal(JSON.stringify(after).includes('private-mixed-environment'), false);
      console.log('PASS official JS client: mixed computer batch approval and failure halt');
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
