import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';
import 'runtime_test.dart' as f;

class FailingProvider implements ChatModel {
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    throw StateError('private-provider-credential');
  }
}

class NativeFixture implements AgentTool<String> {
  @override
  final NativeModelTool definition;
  @override
  final JsonObject? outputSchema;
  @override
  final bool needsApproval;
  @override
  bool get clientExecuted => false;
  final void Function() effect;
  NativeFixture(
    this.effect, {
    required Object value,
    this.needsApproval = true,
    this.outputSchema = const {'type': 'integer'},
  }) : definition = NativeModelTool(
         name: 'computer',
         description: '',
         inputSchema: const {'type': 'object'},
         provider: 'test',
         definition: {'type': 'computer', 'limit': value},
         bindingId: 'session',
       );
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<String> context) async {
    effect();
    return 1;
  }
}

class SequentialFixture extends NativeFixture
    implements SequentialNativeTool<String> {
  SequentialFixture(super.effect, {required super.value});
  @override
  bool isFailure(Object? result) => false;
  @override
  Object? skippedResult() => 1;
}

Future<void> nativeScenario(
  AgentTool<String> first,
  AgentTool<String> second, {
  required bool shouldResume,
}) async {
  final model = f.FakeModel([
    [
      NativeToolCallReady(
        NativeToolCall(
          id: 'c',
          name: 'computer',
          provider: 'test',
          arguments: {},
          requiresApproval: true,
        ),
      ),
      const ModelFinished(),
    ],
    [const ModelFinished()],
  ]);
  final store = MemoryRunStore();
  final original = AiAgent<String>(model: model, store: store, tools: [first]);
  final paused = await original.generate(
    f.request(),
    ownerId: 'owner',
    context: 'x',
  );
  expect(paused.status, RunStatus.interrupted);
  final changed = AiAgent<String>(model: model, store: store, tools: [second]);
  final events = await f.run(
    changed,
    f.request(
      run: 'resume',
      parent: 'run',
      text: null,
      resume: [paused.interrupts.single.approve()],
    ),
  );
  expect(events.last.type, shouldResume ? 'RUN_FINISHED' : 'RUN_ERROR');
  if (!shouldResume) {
    final retry = await f.run(
      original,
      f.request(
        run: 'retry',
        parent: 'run',
        text: null,
        resume: [paused.interrupts.single.approve()],
      ),
    );
    expect(
      retry.last.type,
      'RUN_FINISHED',
      reason: 'rejected continuation preserves pending history',
    );
  }
}

void main() {
  test(
    'native large integer collision rejects changed definition and keeps pending approval',
    () async {
      const a = 9007199254740992;
      const b = 9007199254740993;
      expect(schemaHash({'limit': a}), schemaHash({'limit': b}));
      var effects = 0;
      await nativeScenario(
        NativeFixture(() => effects++, value: a),
        NativeFixture(() => effects++, value: b),
        shouldResume: false,
      );
      expect(effects, 1, reason: 'only the original contract retry executes');
    },
  );

  test(
    'unchanged large integers and equivalent int/double values resume',
    () async {
      for (final pair in [(9007199254740993, 9007199254740993), (42, 42.0)]) {
        var effects = 0;
        await nativeScenario(
          NativeFixture(() => effects++, value: pair.$1),
          NativeFixture(() => effects++, value: pair.$2),
          shouldResume: true,
        );
        expect(effects, 1);
      }
    },
  );

  test(
    'native output schema, approval and sequential policy changes reject',
    () async {
      var effects = 0;
      await nativeScenario(
        NativeFixture(() => effects++, value: 1),
        NativeFixture(
          () => effects++,
          value: 1,
          outputSchema: const {'type': 'number'},
        ),
        shouldResume: false,
      );
      await nativeScenario(
        NativeFixture(() => effects++, value: 1),
        NativeFixture(() => effects++, value: 1, needsApproval: false),
        shouldResume: false,
      );
      await nativeScenario(
        NativeFixture(() => effects++, value: 1),
        SequentialFixture(() => effects++, value: 1),
        shouldResume: false,
      );
      expect(effects, 3);
    },
  );

  test(
    'client tool cannot be resumed as server tool with identical schemas',
    () async {
      var effects = 0;
      final server = f.tool(
        approval: true,
        execute: (v, _) {
          effects++;
          return v;
        },
      );
      final client = ClientTool<String>(
        definition: server.definition,
        outputSchema: server.outputSchema,
      );
      final model = f.FakeModel([
        [f.call(), const ModelFinished()],
        [const ModelFinished()],
      ]);
      final store = MemoryRunStore();
      final paused = await AiAgent<String>(
        model: model,
        store: store,
        tools: [client],
      ).generate(f.request(), ownerId: 'owner', context: 'x');
      expect(paused.status, RunStatus.interrupted);
      final events = await f.run(
        AiAgent<String>(model: model, store: store, tools: [server]),
        f.request(
          run: 'resume',
          parent: 'run',
          text: null,
          resume: [
            ResumeAnswer(interruptId: paused.interrupts.single.id, value: true),
          ],
        ),
      );
      expect(events.last.type, 'RUN_ERROR');
      expect(effects, 0);
    },
  );
  test(
    'legacy and malformed private contracts fail closed without public leakage',
    () async {
      for (final variant in ['missing', 'unknown version', 'malformed']) {
        var effects = 0;
        final tool = NativeFixture(() => effects++, value: 11);
        final model = f.FakeModel([
          [
            NativeToolCallReady(
              NativeToolCall(
                id: 'c',
                name: 'computer',
                provider: 'test',
                arguments: {},
                requiresApproval: true,
              ),
            ),
            const ModelFinished(),
          ],
        ]);
        final store = MemoryRunStore();
        final agent = AiAgent<String>(
          model: model,
          store: store,
          tools: [tool],
        );
        final paused = await agent.generate(
          f.request(),
          ownerId: 'owner',
          context: 'x',
        );
        final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
        final public = jsonEncode({
          'events': await store.events(
            ownerId: 'owner',
            threadId: 'thread',
            runId: 'run',
          ),
          'hydration': chatHydration(state),
        });
        expect(public, isNot(contains('toolContract')));
        expect(public, isNot(contains('bindingId')));
        expect(public, isNot(contains('session')));
        expect(public, isNot(contains('limit')));
        final pending = (state['pending'] as List).single as Map;
        if (variant == 'missing') {
          pending.remove('toolContract');
        } else if (variant == 'unknown version') {
          (pending['toolContract'] as Map)['v'] = 2;
        } else {
          pending['toolContract'] = 'malformed';
        }
        await store.begin(
          ownerId: 'owner',
          threadId: 'thread',
          runId: 'seed',
          parentRunId: 'run',
        );
        await store.save(
          ownerId: 'owner',
          threadId: 'thread',
          runId: 'seed',
          state: state,
          release: true,
        );
        final events = await f.run(
          agent,
          f.request(
            run: 'resume',
            parent: 'run',
            text: null,
            resume: [paused.interrupts.single.approve()],
          ),
        );
        expect(events.last.type, 'RUN_ERROR', reason: variant);
        expect(effects, 0, reason: variant);
        final after = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
        expect(after['pending'], state['pending'], reason: variant);
        expect(after['messages'], state['messages'], reason: variant);
        expect(
          jsonEncode(events.map((event) => event.json).toList()),
          isNot(contains('toolContract')),
        );
      }
    },
  );
  test(
    'provider errors have matching generic stream and Future messages',
    () async {
      final streamAgent = AiAgent<String>(model: FailingProvider());
      final events = await f.run(streamAgent);
      final streamed = events.last.json['message'];
      expect(events.last.type, 'RUN_ERROR');
      expect(streamed, 'The AI run could not complete.');
      final futureAgent = AiAgent<String>(model: FailingProvider());
      try {
        await futureAgent.generate(f.request(), ownerId: 'owner', context: 'x');
        fail('expected provider failure');
      } on AgentRunException catch (error) {
        expect(error.code, 'MODEL_FAILED');
        expect(error.message, streamed);
        expect(
          error.toString(),
          isNot(contains('private-provider-credential')),
        );
        expect(error.cause.toString(), contains('private-provider-credential'));
      }
    },
  );

  test(
    'changed contract emits safe matching stream and Future messages',
    () async {
      final model = f.FakeModel([
        [
          NativeToolCallReady(
            NativeToolCall(
              id: 'c',
              name: 'computer',
              provider: 'test',
              arguments: {},
              requiresApproval: true,
            ),
          ),
          const ModelFinished(),
        ],
      ]);
      final store = MemoryRunStore();
      final original = AiAgent<String>(
        model: model,
        store: store,
        tools: [NativeFixture(() {}, value: 11)],
      );
      final paused = await original.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final changed = AiAgent<String>(
        model: model,
        store: store,
        tools: [NativeFixture(() {}, value: 12)],
      );
      ChatRequest resume(String id) => f.request(
        run: id,
        parent: 'run',
        text: null,
        resume: [paused.interrupts.single.approve()],
      );
      final events = await f.run(changed, resume('stream'));
      final streamed = events.last.json['message'];
      expect(
        streamed,
        'Execution configuration changed. Start a new conversation.',
      );
      try {
        await changed.generate(
          resume('future'),
          ownerId: 'owner',
          context: 'x',
        );
        fail('expected contract failure');
      } on AgentRunException catch (error) {
        expect(error.code, 'INVALID_INPUT');
        expect(error.message, streamed);
        expect(error.toString(), isNot(contains('session')));
        expect(error.toString(), isNot(contains('limit')));
      }
    },
  );
}
