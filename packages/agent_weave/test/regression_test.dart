import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';
import 'runtime_test.dart' show FakeModel, tool, call, request, run;

String interruptId(List<AgentEvent> events) =>
    (((events.last.json['outcome'] as Map)['interrupts'] as List).single
            as Map)['id']
        as String;

void main() {
  test(
    'a throwing diagnostic observer cannot replace the original failure or poison history',
    () async {
      final agent = AiAgent<String>(
        model: FakeModel([
          [call(), const ModelFinished()],
          [const TextDelta('Recovered'), const ModelFinished()],
        ]),
        tools: [
          tool(execute: (_, _) => throw StateError('private tool failure')),
        ],
        onError: (_, _) => throw StateError('logger failure'),
      );
      final failed = await run(agent);
      expect(failed.last.json['code'], 'TOOL_FAILED');
      expect(failed.where((e) => e.type == 'TOOL_CALL_RESULT'), hasLength(1));
      final next = await run(agent, request(run: 'next'));
      expect(next.last.type, 'RUN_FINISHED');
    },
  );
  test(
    'new user messages cannot be inserted between a pending call and its result',
    () async {
      var calls = 0;
      final agent = AiAgent(
        model: FakeModel([
          [call(), const ModelFinished()],
        ]),
        tools: [
          tool(
            approval: true,
            execute: (n, _) {
              calls++;
              return n;
            },
          ),
        ],
      );
      final id = interruptId(await run(agent));
      final invalid = await run(
        agent,
        request(
          run: 'next',
          parent: 'run',
          text: 'Injected',
          resume: [ResumeAnswer(interruptId: id, value: true)],
        ),
      );
      expect(invalid.last.json['code'], 'INVALID_INPUT');
      expect(calls, 0);
      expect(
        (await agent.store.load(
          ownerId: 'owner',
          threadId: 'thread',
        ))!['status'],
        'interrupted',
      );
    },
  );
  test(
    'a failing generation observer still produces a safe terminal failure',
    () async {
      final task = GenerationTask<int, int>(
        execute: (_, _) async => throw StateError('private'),
        encodeResult: (n) => n,
        onError: (_, _) => throw StateError('logger'),
      );
      final events = await task.run(1, threadId: 't', runId: 'r').toList();
      expect(events.last.type, 'RUN_ERROR');
      expect(
        jsonEncode(events.map((e) => e.json).toList()),
        isNot(contains('private')),
      );
    },
  );

  test(
    'cancellation retains the text already delivered to the client',
    () async {
      final token = CancellationToken();
      final agent = AiAgent<String>(
        model: FakeModel([
          [
            const TextDelta('Partial answer'),
            const TextDelta(' omitted'),
            const ModelFinished(),
          ],
        ]),
      );
      await for (final event in agent.run(
        request(),
        ownerId: 'owner',
        context: 'x',
        cancellation: token,
      )) {
        if (event.type == 'TEXT_MESSAGE_CONTENT') token.cancel();
      }
      final saved = await agent.store.load(
        ownerId: 'owner',
        threadId: 'thread',
      );
      expect(saved!['status'], 'cancelled');
      final last = (saved['messages'] as List).last as Map;
      expect(last['content'], [
        {'type': 'text', 'text': 'Partial answer'},
      ]);
    },
  );
  test('a failed tool leaves complete history for the next turn', () async {
    final model = FakeModel([
      [call(), const ModelFinished()],
      [const TextDelta('Recovered'), const ModelFinished()],
    ]);
    final agent = AiAgent(
      model: model,
      tools: [tool(execute: (_, _) => throw StateError('private failure'))],
    );
    final failed = await run(agent);
    expect(failed.last.type, 'RUN_ERROR');
    expect(
      jsonEncode(failed.map((e) => e.json).toList()),
      isNot(contains('private failure')),
    );
    expect(failed.where((e) => e.type == 'TOOL_CALL_RESULT'), hasLength(1));
    expect((await run(agent, request(run: 'next'))).last.type, 'RUN_FINISHED');
    final history = model.requests.last.messages;
    expect(
      history.where((m) => m.role == MessageRole.tool).single.toolCallId,
      'call',
    );
  });
  test('a truncated model invocation cannot execute tools', () async {
    var executed = false;
    final agent = AiAgent(
      model: FakeModel([
        [call(), const ModelFinished('length')],
      ]),
      tools: [
        tool(
          execute: (n, _) {
            executed = true;
            return n;
          },
        ),
      ],
    );
    expect((await run(agent)).last.type, 'RUN_ERROR');
    expect(executed, isFalse);
  });
  test('tool idempotency keys survive continuations and isolate owners', () {
    ToolContext<void> context(String owner, String run) => ToolContext(
      value: null,
      ownerId: owner,
      threadId: 'thread',
      runId: run,
      toolCallId: 'call',
      cancellation: CancellationToken(),
    );
    expect(
      context('owner', 'run').idempotencyKey,
      context('owner', 'continuation').idempotencyKey,
    );
    expect(
      context('owner', 'run').idempotencyKey,
      isNot(context('another-owner', 'run').idempotencyKey),
    );
  });
  test(
    'invalid approval batch preserves the original pending run for a corrected retry',
    () async {
      var called = 0;
      final model = FakeModel([
        [call(), const ModelFinished()],
        [const ModelFinished()],
      ]);
      final agent = AiAgent(
        model: model,
        tools: [
          tool(
            approval: true,
            execute: (n, c) {
              called++;
              return n * 2;
            },
          ),
        ],
      );
      final id = interruptId(await run(agent));
      final invalid = await run(
        agent,
        request(
          run: 'invalid',
          parent: 'run',
          text: null,
          resume: [
            ResumeAnswer(
              interruptId: id,
              value: {
                'approved': true,
                'editedArgs': {'count': -1},
              },
            ),
          ],
        ),
      );
      expect(invalid.last.type, 'RUN_ERROR');
      expect(called, 0);
      final preserved = await agent.store.load(
        ownerId: 'owner',
        threadId: 'thread',
      );
      expect(preserved!['status'], 'interrupted');
      expect(preserved['runId'], 'run');
      final valid = await run(
        agent,
        request(
          run: 'valid',
          parent: 'run',
          text: null,
          resume: [ResumeAnswer(interruptId: id, value: true)],
        ),
      );
      expect(valid.last.type, 'RUN_FINISHED');
      expect(called, 1);
    },
  );
  test('another owner cannot resolve a pending approval', () async {
    var called = 0;
    final agent = AiAgent(
      model: FakeModel([
        [call(), const ModelFinished()],
      ]),
      tools: [
        tool(
          approval: true,
          execute: (n, c) {
            called++;
            return n;
          },
        ),
      ],
    );
    final id = interruptId(await run(agent));
    await expectLater(
      agent
          .run(
            request(
              run: 'attack',
              parent: 'run',
              text: null,
              resume: [ResumeAnswer(interruptId: id, value: true)],
            ),
            ownerId: 'other-owner',
            context: 'x',
          )
          .toList(),
      throwsA(isA<RunConflict>()),
    );
    expect(called, 0);
  });
  test('terminal event is published after releasing the reservation', () async {
    final agent = AiAgent<String>(
      model: FakeModel([
        [const ModelFinished()],
        [const ModelFinished()],
      ]),
    );
    Future<List<AgentEvent>>? next;
    await for (final event in agent.run(
      request(),
      ownerId: 'owner',
      context: 'x',
    )) {
      if (event.type == 'RUN_FINISHED') next = run(agent, request(run: 'next'));
    }
    expect((await next!).last.type, 'RUN_FINISHED');
  });
  test('reasoning emits the standard event sequence', () async {
    final events = await run(
      AiAgent<String>(
        model: FakeModel([
          [
            const ReasoningDelta('Considering'),
            const TextDelta('Answer'),
            const ModelFinished(),
          ],
        ]),
      ),
    );
    expect(
      events.map((e) => e.type),
      containsAllInOrder([
        'REASONING_START',
        'REASONING_MESSAGE_START',
        'REASONING_MESSAGE_CONTENT',
        'TEXT_MESSAGE_START',
        'TEXT_MESSAGE_CONTENT',
        'TEXT_MESSAGE_END',
        'REASONING_MESSAGE_END',
        'REASONING_END',
        'RUN_FINISHED',
      ]),
    );
  });
  test(
    'opaque provider reasoning is persisted but never exposed by hydration',
    () async {
      final agent = AiAgent<String>(
        model: FakeModel([
          [
            ProviderOutput(
              provider: 'provider',
              items: [
                {'encrypted': 'private-replay-state'},
              ],
            ),
            const TextDelta('Public'),
            const ModelFinished(),
          ],
        ]),
      );
      await run(agent);
      final state = await agent.store.load(
        ownerId: 'owner',
        threadId: 'thread',
      );
      expect(jsonEncode(state), contains('private-replay-state'));
      expect(
        jsonEncode(chatHydration(state)),
        isNot(contains('private-replay-state')),
      );
    },
  );
  test('events and tool inputs snapshot nested mutable JSON', () {
    final json = <String, Object?>{
      'nested': <String, Object?>{'value': 1},
    };
    final event = AgentEvent({'type': 'CUSTOM', 'value': json});
    final call = ToolCall(id: 'c', name: 'tool', arguments: json);
    (json['nested'] as Map)['value'] = 2;
    expect(((event.json['value'] as Map)['nested'] as Map)['value'], 1);
    expect((call.arguments['nested'] as Map)['value'], 1);
    expect(
      () => (call.arguments['nested'] as Map)['value'] = 3,
      throwsUnsupportedError,
    );
  });
  test(
    'generation snapshots and event logs survive a new task instance',
    () async {
      final store = MemoryRunStore();
      final task = GenerationTask<int, int>(
        store: store,
        execute: (input, context) async => input * 2,
        encodeResult: (result) => {'answer': result},
      );
      await task
          .run(21, threadId: 'generation', runId: 'r', ownerId: 'owner')
          .drain<void>();
      final saved = await store.load(ownerId: 'owner', threadId: 'generation');
      expect(saved!['result'], {'answer': 42});
      expect(saved['status'], 'completed');
      expect(
        await store.events(
          ownerId: 'owner',
          threadId: 'generation',
          runId: 'r',
        ),
        hasLength(3),
      );
      expect(await store.threadForRun(ownerId: 'other', runId: 'r'), isNull);
      final chat = AiAgent<String>(model: FakeModel([]), store: store);
      final rejected = await chat
          .run(
            request(thread: 'generation', run: 'chat'),
            ownerId: 'owner',
            context: 'x',
          )
          .toList();
      expect(rejected.last.type, 'RUN_ERROR');
      expect(
        (await store.load(ownerId: 'owner', threadId: 'generation'))!['kind'],
        'generation',
      );
    },
  );
  test(
    'generation cancellation aborts a blocked operation and releases storage',
    () async {
      final store = MemoryRunStore();
      final started = Completer<void>();
      final task = GenerationTask<int, int>(
        store: store,
        execute: (n, context) async {
          started.complete();
          await context.cancellation.whenCancelled;
          context.cancellation.throwIfCancelled();
          return n;
        },
        encodeResult: (result) => result,
      );
      final sub = task
          .run(1, threadId: 'g', runId: 'r', ownerId: 'owner')
          .listen((_) {});
      await started.future;
      await sub.cancel().timeout(const Duration(seconds: 2));
      expect(
        (await store.load(ownerId: 'owner', threadId: 'g'))!['status'],
        'cancelled',
      );
    },
  );
  test(
    'structured output has typed start and complete protocol events',
    () async {
      final events = await run(
        AiAgent<String>(
          model: FakeModel([
            [const TextDelta('{"answer":42}'), const ModelFinished()],
          ]),
          outputSchema: const {
            'type': 'object',
            'required': ['answer'],
            'properties': {
              'answer': {'type': 'integer'},
            },
          },
        ),
      );
      final complete = events.singleWhere(
        (e) => e.json['name'] == 'structured-output.complete',
      );
      expect((complete.json['value'] as Map)['object'], {'answer': 42});
      expect(events.last.type, 'RUN_FINISHED');
    },
  );
}
