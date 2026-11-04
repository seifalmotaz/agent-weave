import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';

import 'native_core_test.dart' as native;
import 'runtime_test.dart' as f;
import 'sequential_native_test.dart' as sequential;

class FallbackTool implements NativeToolFallback<String> {
  final List<String> effects;
  final String denied;
  final bool approval;
  final bool throwAfterEffect;
  final String binding;
  final String grammar;
  FallbackTool(
    this.effects, {
    this.denied = 'declined',
    this.approval = true,
    this.throwAfterEffect = false,
    this.binding = 'ticket-database',
    this.grammar = 'original',
  });

  @override
  NativeModelTool get definition => NativeModelTool(
    name: 'custom',
    description: 'Look up a ticket',
    provider: 'example',
    bindingId: binding,
    definition: {'type': 'custom', 'grammar': grammar},
    inputSchema: const {
      'type': 'object',
      'properties': {
        'input': {'type': 'string'},
      },
      'required': ['input'],
      'additionalProperties': false,
    },
  );
  @override
  JsonObject get outputSchema => const {
    'type': 'object',
    'properties': {
      'output': {'type': 'string'},
      'isError': {'type': 'boolean'},
    },
    'required': ['output', 'isError'],
    'additionalProperties': false,
  };
  @override
  bool get needsApproval => approval;
  @override
  bool get clientExecuted => false;
  @override
  Object? declinedResult({required bool cancelled}) => {
    'output': cancelled ? 'cancelled' : denied,
    'isError': true,
  };
  @override
  Object? skippedResult() => {'output': 'skipped', 'isError': true};
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<String> context) async {
    effects.add(input['input'] as String);
    if (throwAfterEffect) throw StateError('Outcome is uncertain');
    return {'output': input['input'], 'isError': false};
  }
}

class BadFallback extends FallbackTool {
  BadFallback() : super([]);
  @override
  Object? declinedResult({required bool cancelled}) => 42;
}

class ValidatingModel implements ChatModel, ModelToolValidator {
  final f.FakeModel delegate = f.FakeModel([]);
  int validations = 0;
  List<ModelRequest> get requests => delegate.requests;
  @override
  ModelCapabilities get capabilities => delegate.capabilities;
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => delegate.stream(request, cancellation: cancellation);
  @override
  void validateTools(Iterable<ModelTool> tools) {
    validations++;
    if (tools.whereType<NativeModelTool>().length > 1) {
      throw ArgumentError('Conflicting tool registry');
    }
  }
}

NativeToolCall customCall() => NativeToolCall(
  id: 'custom-1',
  name: 'custom',
  provider: 'example',
  arguments: const {'input': 'TICKET-42'},
);

void main() {
  for (final cancel in [false, true]) {
    test(
      'declared native outcome resumes after denial, cancelled=$cancel',
      () async {
        final effects = <String>[];
        final model = f.FakeModel([
          [NativeToolCallReady(customCall()), const ModelFinished()],
          [const TextDelta('Understood'), const ModelFinished()],
        ]);
        final store = MemoryRunStore();
        AiAgent<String> agent() => AiAgent<String>(
          model: model,
          store: store,
          tools: [FallbackTool(effects)],
        );
        final paused = await agent().generate(
          f.request(),
          ownerId: 'owner',
          context: 'x',
        );
        final saved = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
        final pending = (saved['pending'] as List).single as Map;
        expect((pending['toolContract'] as Map)['nativeFallbacks'], {
          'declined': {'output': 'declined', 'isError': true},
          'cancelled': {'output': 'cancelled', 'isError': true},
          'skipped': {'output': 'skipped', 'isError': true},
        });
        final resumed = await agent().generate(
          f.request(
            run: 'next',
            parent: paused.runId,
            text: null,
            resume: [
              cancel
                  ? paused.interrupts.single.cancel()
                  : paused.interrupts.single.reject(),
            ],
          ),
          ownerId: 'owner',
          context: 'x',
        );
        expect(resumed.status, RunStatus.completed);
        expect(resumed.text, 'Understood');
        expect(effects, isEmpty);
        expect(model.requests, hasLength(2));
        expect(jsonDecode(resumed.responseMessages.first.text), {
          'output': cancel ? 'cancelled' : 'declined',
          'isError': true,
        });
        expect(
          (await store.load(
            ownerId: 'owner',
            threadId: 'thread',
          ))!['nativeContinuationClosed'],
          isNull,
        );
      },
    );
  }

  test(
    'changed fallback policy rejects the whole batch before effects',
    () async {
      final effects = <String>[];
      final model = f.FakeModel([
        [NativeToolCallReady(customCall()), f.call(), const ModelFinished()],
      ]);
      final store = MemoryRunStore();
      AiAgent<String> agent(String denied) => AiAgent<String>(
        model: model,
        store: store,
        tools: [
          FallbackTool(effects, denied: denied),
          f.tool(
            approval: true,
            execute: (_, _) {
              effects.add('ordinary');
              return 1;
            },
          ),
        ],
      );
      final paused = await agent(
        'original',
      ).generate(f.request(), ownerId: 'owner', context: 'x');
      await expectLater(
        agent('changed').generate(
          f.request(
            run: 'changed',
            parent: paused.runId,
            text: null,
            resume: [
              for (final interrupt in paused.interrupts)
                interrupt.call.name == 'custom'
                    ? interrupt.reject()
                    : interrupt.approve(),
            ],
          ),
          ownerId: 'owner',
          context: 'x',
        ),
        throwsA(isA<AgentRunException>()),
      );
      expect(effects, isEmpty);
      expect(model.requests, hasLength(1));
      final saved = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      expect(saved['status'], 'interrupted');
      expect(saved['pending'], hasLength(2));
    },
  );

  test('computer denial still closes a mixed batch before any effect', () async {
    final effects = <String>[];
    // Build the native call explicitly: the computer has no safe denial output.
    final actualModel = f.FakeModel([
      [
        NativeToolCallReady(native.nativeCall()),
        NativeToolCallReady(customCall()),
        const ModelFinished(),
      ],
    ]);
    final agent = AiAgent<String>(
      model: actualModel,
      tools: [
        native.NativeTool((_) => effects.add('computer')),
        FallbackTool(effects),
      ],
    );
    final paused = await agent.generate(
      f.request(),
      ownerId: 'owner',
      context: 'x',
    );
    await expectLater(
      agent.generate(
        f.request(
          run: 'deny',
          parent: paused.runId,
          text: null,
          resume: [
            for (final interrupt in paused.interrupts)
              interrupt.call.name == 'computer'
                  ? interrupt.reject()
                  : interrupt.approve(),
          ],
        ),
        ownerId: 'owner',
        context: 'x',
      ),
      throwsA(isA<RunCancelled>()),
    );
    expect(effects, isEmpty);
    expect(actualModel.requests, hasLength(1));
    expect(
      (await agent.store.load(
        ownerId: 'owner',
        threadId: 'thread',
      ))!['nativeContinuationClosed'],
      isNotNull,
    );
  });

  test(
    'custom native call can receive a declared skip after earlier failure',
    () async {
      final effects = <String>[];
      final nativeEffects = <int>[];
      final model = f.FakeModel([
        [
          NativeToolCallReady(sequential.call(1)),
          NativeToolCallReady(customCall()),
          const ModelFinished(),
        ],
        [const TextDelta('Recovered'), const ModelFinished()],
      ]);
      final result = await AiAgent<String>(
        model: model,
        tools: [
          sequential.SequentialTool(nativeEffects),
          FallbackTool(effects, approval: false),
        ],
      ).generate(f.request(), ownerId: 'owner', context: 'x');
      expect(result.text, 'Recovered');
      expect(nativeEffects, [1]);
      expect(effects, isEmpty);
      final skipped = result.responseMessages.singleWhere(
        (m) => m.toolCallId == 'custom-1',
      );
      expect(jsonDecode(skipped.text), {'output': 'skipped', 'isError': true});
    },
  );

  test(
    'unknown executor failure never invents a fallback or retries',
    () async {
      final effects = <String>[];
      final model = f.FakeModel([
        [NativeToolCallReady(customCall()), const ModelFinished()],
      ]);
      final agent = AiAgent<String>(
        model: model,
        tools: [FallbackTool(effects, approval: false, throwAfterEffect: true)],
      );
      await expectLater(
        agent.generate(f.request(), ownerId: 'owner', context: 'x'),
        throwsA(isA<AgentRunException>()),
      );
      expect(effects, ['TICKET-42']);
      final saved = (await agent.store.load(
        ownerId: 'owner',
        threadId: 'thread',
      ))!;
      expect(saved['nativeContinuationClosed'], isNotNull);
      await expectLater(
        agent.generate(
          f.request(run: 'retry', text: null),
          ownerId: 'owner',
          context: 'x',
        ),
        throwsA(isA<AgentRunException>()),
      );
      expect(effects, ['TICKET-42']);
      expect(model.requests, hasLength(1));
    },
  );

  test('invalid declared outcomes and registry fail before a run', () {
    expect(
      () => AiAgent<String>(model: f.FakeModel([]), tools: [BadFallback()]),
      throwsA(isA<SchemaValidationException>()),
    );
    final model = ValidatingModel();
    expect(
      () => AiAgent<String>(
        model: model,
        tools: [FallbackTool([]), native.NativeTool((_) {})],
      ),
      throwsArgumentError,
    );
    expect(model.validations, 1);
    expect(model.requests, isEmpty);
  });
  for (final change in ['binding', 'grammar', 'removed', 'order']) {
    test(
      'unrelated registry $change rejects before an approved function effect',
      () async {
        final effects = <String>[];
        final store = MemoryRunStore();
        final model = f.FakeModel([
          [f.call(), const ModelFinished()],
          [const TextDelta('Complete'), const ModelFinished()],
        ]);
        AiAgent<String> agent([String change = 'original']) {
          final ordinary = f.tool(
            approval: true,
            execute: (n, _) {
              effects.add('ordinary');
              return n;
            },
          );
          final custom = FallbackTool(
            effects,
            binding: change == 'binding'
                ? 'different-database'
                : 'ticket-database',
            grammar: change == 'grammar' ? 'different-grammar' : 'original',
          );
          return AiAgent<String>(
            model: model,
            store: store,
            tools: [
              if (change == 'order') custom,
              ordinary,
              if (change != 'removed' && change != 'order') custom,
            ],
          );
        }

        final paused = await agent().generate(
          f.request(),
          ownerId: 'owner',
          context: 'x',
        );
        expect(paused.interrupts.single.call, isA<FunctionToolCall>());
        final saved = await store.load(ownerId: 'owner', threadId: 'thread');
        await expectLater(
          agent(change).generate(
            f.request(
              run: 'changed',
              parent: paused.runId,
              text: null,
              resume: [paused.interrupts.single.approve()],
            ),
            ownerId: 'owner',
            context: 'x',
          ),
          throwsA(
            isA<AgentRunException>().having(
              (error) => error.code,
              'code',
              'INVALID_INPUT',
            ),
          ),
        );
        expect(effects, isEmpty);
        expect(model.requests, hasLength(1));
        expect(await store.load(ownerId: 'owner', threadId: 'thread'), saved);
        final completed = await agent().generate(
          f.request(
            run: 'original',
            parent: paused.runId,
            text: null,
            resume: [paused.interrupts.single.approve()],
          ),
          ownerId: 'owner',
          context: 'x',
        );
        expect(completed.text, 'Complete');
        expect(effects, ['ordinary']);
      },
    );
  }

  test(
    'legacy unfinished profile without its full registry is retained and rejected',
    () async {
      final effects = <String>[];
      final store = MemoryRunStore();
      final model = f.FakeModel([
        [f.call(), const ModelFinished()],
      ]);
      final agent = AiAgent<String>(
        model: model,
        store: store,
        tools: [
          f.tool(
            approval: true,
            execute: (_, _) {
              effects.add('called');
              return 1;
            },
          ),
        ],
      );
      final paused = await agent.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final saved = Map<String, Object?>.from(
        (await store.load(ownerId: 'owner', threadId: 'thread'))!,
      );
      saved['modelContinuationContract'] = {'v': 1, 'kind': 'unbound_model'};
      await store.begin(
        ownerId: 'owner',
        threadId: 'thread',
        runId: 'seed',
        parentRunId: paused.runId,
      );
      await store.save(
        ownerId: 'owner',
        threadId: 'thread',
        runId: 'seed',
        state: saved,
        release: true,
      );
      await expectLater(
        agent.generate(
          f.request(
            run: 'legacy',
            parent: paused.runId,
            text: null,
            resume: [paused.interrupts.single.approve()],
          ),
          ownerId: 'owner',
          context: 'x',
        ),
        throwsA(isA<AgentRunException>()),
      );
      expect(effects, isEmpty);
      expect(model.requests, hasLength(1));
      expect(await store.load(ownerId: 'owner', threadId: 'thread'), saved);
    },
  );
}
