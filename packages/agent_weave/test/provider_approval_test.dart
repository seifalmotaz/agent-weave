import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';
import 'runtime_test.dart' as f;

class ApprovalModel implements ProviderApprovalModel {
  final List<List<ModelEvent>> steps;
  final requests = <ModelRequest>[];
  String identity = 'v1';
  ApprovalModel(this.steps);
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(tools: true);
  @override
  JsonObject approvalContract(ProviderApprovalCall call) => {
    'v': 1,
    'provider': call.provider,
    'label': call.serverLabel,
    'identity': identity,
  };
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    requests.add(request);
    yield* Stream.fromIterable(steps.removeAt(0));
  }
}

class EffectModel implements ChatModel {
  final bool cancel;
  final started = Completer<void>();
  int requests = 0;
  EffectModel(this.cancel);
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    requests++;
    yield const ProviderExecutionStarting();
    started.complete();
    if (cancel) {
      await cancellation.whenCancelled;
      cancellation.throwIfCancelled();
    }
    throw StateError('uncertain provider effect');
  }
}

ProviderApprovalCall call() => ProviderApprovalCall(
  id: 'public-call',
  name: 'remote',
  arguments: {'query': 'x'},
  provider: 'openai.responses',
  serverLabel: 'docs',
  providerRequestId: 'private-request',
);
void main() {
  for (final approved in [true, false]) {
    test(
      'provider decision resumes without local execution or private ID leak: $approved',
      () async {
        final model = ApprovalModel([
          [ProviderApprovalReady(call()), const ModelFinished()],
          [const TextDelta('done'), const ModelFinished()],
        ]);
        final store = MemoryRunStore();
        final agent = AiAgent<String>(model: model, store: store);
        final paused = await agent.generate(
          f.request(),
          ownerId: 'owner',
          context: 'x',
        );
        expect(paused.status, RunStatus.interrupted);
        expect(paused.interrupts.single.call, isA<ProviderApprovalCall>());
        final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
        final events = await store.events(
          ownerId: 'owner',
          threadId: 'thread',
          runId: 'run',
        );
        expect(
          jsonEncode({'events': events, 'hydration': chatHydration(state)}),
          isNot(contains('private-request')),
        );
        final resumed = await agent.generate(
          f.request(
            run: 'next',
            parent: 'run',
            text: null,
            resume: [
              approved
                  ? paused.interrupts.single.approve()
                  : paused.interrupts.single.reject(),
            ],
          ),
          ownerId: 'owner',
          context: 'x',
        );
        expect(resumed.status, RunStatus.completed);
        expect(
          model.requests.last.providerApprovalDecisions.single.approved,
          approved,
        );
        expect(
          model
              .requests
              .last
              .providerApprovalDecisions
              .single
              .providerRequestId,
          'private-request',
        );
        expect(
          (await store.events(
            ownerId: 'owner',
            threadId: 'thread',
            runId: 'next',
          )).where((e) => e['type'] == 'TOOL_CALL_RESULT'),
          isEmpty,
        );
      },
    );
  }
  test('mixed local call staged before approved continuation', () async {
    var effects = 0;
    final model = ApprovalModel([
      [f.call(), ProviderApprovalReady(call()), const ModelFinished()],
      [const ModelFinished()],
    ]);
    final store = MemoryRunStore();
    final agent = AiAgent<String>(
      model: model,
      store: store,
      tools: [
        f.tool(
          execute: (n, _) {
            effects++;
            return n;
          },
        ),
      ],
    );
    final paused = await agent.generate(
      f.request(),
      ownerId: 'owner',
      context: 'x',
    );
    expect(paused.status, RunStatus.interrupted);
    expect(effects, 0);
    final bad = await f.run(
      agent,
      f.request(
        run: 'bad',
        parent: 'run',
        text: null,
        resume: [
          ResumeAnswer(
            interruptId: paused.interrupts.single.id,
            value: {'approved': true, 'editedArgs': <String, Object?>{}},
          ),
        ],
      ),
    );
    expect(bad.last.type, 'RUN_ERROR');
    expect(effects, 0);
    final good = await agent.generate(
      f.request(
        run: 'good',
        parent: 'run',
        text: null,
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: 'x',
    );
    expect(good.status, RunStatus.completed);
    expect(effects, 1);
  });
  test(
    'uncertain continuation stays closed after restart without repeating send',
    () async {
      final model = ApprovalModel([
        [ProviderApprovalReady(call()), const ModelFinished()],
        [],
      ]);
      final store = MemoryRunStore();
      final agent = AiAgent<String>(model: model, store: store);
      final paused = await agent.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final events = await f.run(
        agent,
        f.request(
          run: 'failed',
          parent: 'run',
          text: null,
          resume: [paused.interrupts.single.approve()],
        ),
      );
      expect(events.last.type, 'RUN_ERROR');
      final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      expect(state['providerApprovalIndeterminate'], true);
      final recovered = AiAgent<String>(model: model, store: store);
      final retry = await f.run(recovered, f.request(run: 'retry', text: null));
      expect(retry.last.type, 'RUN_ERROR');
      expect(model.requests, hasLength(2));
      expect(
        (await store.load(
          ownerId: 'owner',
          threadId: 'thread',
        ))!['providerApprovalIndeterminate'],
        true,
      );
    },
  );
  test(
    'cancelled provider approval preserves pending and never sends denial',
    () async {
      final model = ApprovalModel([
        [ProviderApprovalReady(call()), const ModelFinished()],
      ]);
      final store = MemoryRunStore();
      final agent = AiAgent<String>(model: model, store: store);
      final paused = await agent.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      await expectLater(
        agent.generate(
          f.request(
            run: 'cancel',
            parent: 'run',
            text: null,
            resume: [paused.interrupts.single.cancel()],
          ),
          ownerId: 'owner',
          context: 'x',
        ),
        throwsA(isA<RunCancelled>()),
      );
      final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      expect(state['status'], 'interrupted');
      expect(state['pending'], hasLength(1));
      expect(model.requests, hasLength(1));
    },
  );
  test(
    'reused private provider request ID fails before a second interrupt',
    () async {
      final model = ApprovalModel([
        [ProviderApprovalReady(call()), const ModelFinished()],
        [
          ProviderApprovalReady(
            ProviderApprovalCall(
              id: 'new-local',
              name: 'remote',
              arguments: {},
              provider: 'openai.responses',
              serverLabel: 'docs',
              providerRequestId: 'private-request',
            ),
          ),
          const ModelFinished(),
        ],
      ]);
      final store = MemoryRunStore();
      final agent = AiAgent<String>(model: model, store: store);
      final paused = await agent.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final events = await f.run(
        agent,
        f.request(
          run: 'next',
          parent: 'run',
          text: null,
          resume: [paused.interrupts.single.approve()],
        ),
      );
      expect(events.last.type, 'RUN_ERROR');
      final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      expect(state['providerApprovalIndeterminate'], true);
    },
  );
  test(
    'orphan and duplicate stored decisions fail closed and release reservation',
    () async {
      for (final duplicate in [false, true]) {
        final store = MemoryRunStore();
        final approval = call();
        final decision = {
          'provider': approval.provider,
          'providerRequestId': approval.providerRequestId,
          'approved': true,
        };
        final state = <String, Object?>{
          'kind': 'chat',
          'threadId': 'thread',
          'runId': 'seed',
          'status': 'completed',
          'generation': 1,
          'messages': [
            if (duplicate)
              ChatMessage(
                id: 'a',
                role: MessageRole.assistant,
                toolCalls: [approval],
              ).toJson(),
          ],
          'providerApprovalDecisions': [decision, if (duplicate) decision],
        };
        await store.begin(ownerId: 'owner', threadId: 'thread', runId: 'seed');
        await store.save(
          ownerId: 'owner',
          threadId: 'thread',
          runId: 'seed',
          state: state,
          release: true,
        );
        final model = ApprovalModel([]);
        await expectLater(
          AiAgent<String>(model: model, store: store).generate(
            f.request(run: 'bad', parent: 'seed', text: null),
            ownerId: 'owner',
            context: 'x',
          ),
          throwsFormatException,
        );
        expect(await store.load(ownerId: 'owner', threadId: 'thread'), state);
        final restored = await store.begin(
          ownerId: 'owner',
          threadId: 'thread',
          runId: 'probe',
          parentRunId: 'seed',
        );
        await store.save(
          ownerId: 'owner',
          threadId: 'thread',
          runId: 'probe',
          state: restored,
          release: true,
        );
        expect(model.requests, isEmpty);
      }
    },
  );
  test(
    'mixed provider and local approvals validate complete batch before effects',
    () async {
      var effects = 0;
      final other = ProviderApprovalCall(
        id: 'public-2',
        name: 'remote',
        arguments: {'q': 2},
        provider: 'openai.responses',
        serverLabel: 'docs',
        providerRequestId: 'private-2',
      );
      final model = ApprovalModel([
        [
          f.call(),
          ProviderApprovalReady(call()),
          ProviderApprovalReady(other),
          const ModelFinished(),
        ],
        [const ModelFinished()],
      ]);
      final agent = AiAgent<String>(
        model: model,
        tools: [
          f.tool(
            approval: true,
            execute: (n, _) {
              effects++;
              return n;
            },
          ),
        ],
      );
      final paused = await agent.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      expect(paused.interrupts, hasLength(3));
      final bad = [
        paused.interrupts[0].approve(),
        paused.interrupts[1].approve(),
        ResumeAnswer(
          interruptId: paused.interrupts[2].id,
          value: {'approved': 'bad'},
        ),
      ];
      final events = await f.run(
        agent,
        f.request(run: 'bad', parent: 'run', text: null, resume: bad),
      );
      expect(events.last.type, 'RUN_ERROR');
      expect(effects, 0);
      final good = await agent.generate(
        f.request(
          run: 'good',
          parent: 'run',
          text: null,
          resume: [
            paused.interrupts[0].approve(),
            paused.interrupts[1].approve(),
            paused.interrupts[2].reject(),
          ],
        ),
        ownerId: 'owner',
        context: 'x',
      );
      expect(good.status, RunStatus.completed);
      expect(effects, 1);
      expect(
        model.requests.last.providerApprovalDecisions.map((d) => d.approved),
        [true, false],
      );
    },
  );
  test(
    'contract drift fails before effects and preserves pending for retry',
    () async {
      final model = ApprovalModel([
        [ProviderApprovalReady(call()), const ModelFinished()],
        [const ModelFinished()],
      ]);
      final store = MemoryRunStore();
      final agent = AiAgent<String>(model: model, store: store);
      final paused = await agent.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      model.identity = 'changed';
      final bad = await f.run(
        agent,
        f.request(
          run: 'bad',
          parent: 'run',
          text: null,
          resume: [paused.interrupts.single.approve()],
        ),
      );
      expect(bad.last.type, 'RUN_ERROR');
      expect(model.requests, hasLength(1));
      model.identity = 'v1';
      final good = await agent.generate(
        f.request(
          run: 'good',
          parent: 'run',
          text: null,
          resume: [paused.interrupts.single.approve()],
        ),
        ownerId: 'owner',
        context: 'x',
      );
      expect(good.status, RunStatus.completed);
    },
  );
  for (final cancellation in [false, true]) {
    test(
      'initial provider effect failure or cancellation remains indeterminate: $cancellation',
      () async {
        final model = EffectModel(cancellation);
        final store = MemoryRunStore();
        final agent = AiAgent<String>(model: model, store: store);
        final token = CancellationToken();
        final events = <AgentEvent>[];
        final run = agent
            .run(
              f.request(),
              ownerId: 'owner',
              context: 'x',
              cancellation: token,
            )
            .forEach(events.add);
        await model.started.future;
        if (cancellation) token.cancel();
        await run;
        expect(
          events.where(
            (e) =>
                e.type == 'CUSTOM' &&
                jsonEncode(e.json).contains('ProviderExecutionStarting'),
          ),
          isEmpty,
        );
        final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
        expect(state['providerApprovalIndeterminate'], true);
        final restarted = AiAgent<String>(model: model, store: store);
        final retry = await f.run(
          restarted,
          f.request(run: 'retry', text: null),
        );
        expect(retry.last.type, 'RUN_ERROR');
        expect(model.requests, 1);
      },
    );
  }
  test('authoritative terminal clears provider effect marker', () async {
    final model = f.FakeModel([
      [
        const ProviderExecutionStarting(),
        const TextDelta('ok'),
        const ModelFinished(),
      ],
      [const TextDelta('again'), const ModelFinished()],
    ]);
    final store = MemoryRunStore();
    final agent = AiAgent<String>(model: model, store: store);
    final first = await agent.generate(
      f.request(),
      ownerId: 'owner',
      context: 'x',
    );
    expect(first.status, RunStatus.completed);
    expect(
      (await store.load(
        ownerId: 'owner',
        threadId: 'thread',
      ))!['providerApprovalIndeterminate'],
      isNull,
    );
    final next = await agent.generate(
      f.request(run: 'next'),
      ownerId: 'owner',
      context: 'x',
    );
    expect(next.status, RunStatus.completed);
  });
  for (final approved in [true, false]) {
    test(
      'provider decision reason persists privately for approve or reject: $approved',
      () async {
        final model = ApprovalModel([
          [ProviderApprovalReady(call()), const ModelFinished()],
          [const ModelFinished()],
        ]);
        final store = MemoryRunStore();
        final agent = AiAgent<String>(model: model, store: store);
        final paused = await agent.generate(
          f.request(),
          ownerId: 'owner',
          context: 'x',
        );
        final answer = approved
            ? paused.interrupts.single.approve(reason: 'private-reason')
            : paused.interrupts.single.reject(reason: 'private-reason');
        final result = await agent.generate(
          f.request(run: 'next', parent: 'run', text: null, resume: [answer]),
          ownerId: 'owner',
          context: 'x',
        );
        expect(result.status, RunStatus.completed);
        final decision = model.requests.last.providerApprovalDecisions.single;
        expect(decision.approved, approved);
        expect(decision.reason, 'private-reason');
        expect(
          ProviderApprovalDecision.fromJson(decision.toJson()).reason,
          'private-reason',
        );
        final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
        expect(
          (state['providerApprovalDecisions'] as List).single['reason'],
          'private-reason',
        );
        final events = await store.events(
          ownerId: 'owner',
          threadId: 'thread',
          runId: 'next',
        );
        expect(
          jsonEncode({'events': events, 'hydration': chatHydration(state)}),
          isNot(contains('private-reason')),
        );
      },
    );
  }
  test(
    'non-string provider reason rejects before mixed local effect',
    () async {
      var effects = 0;
      final model = ApprovalModel([
        [f.call(), ProviderApprovalReady(call()), const ModelFinished()],
        [const ModelFinished()],
      ]);
      final agent = AiAgent<String>(
        model: model,
        tools: [
          f.tool(
            execute: (n, _) {
              effects++;
              return n;
            },
          ),
        ],
      );
      final paused = await agent.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final bad = await f.run(
        agent,
        f.request(
          run: 'bad',
          parent: 'run',
          text: null,
          resume: [
            ResumeAnswer(
              interruptId: paused.interrupts.single.id,
              value: {'approved': true, 'reason': 42},
            ),
          ],
        ),
      );
      expect(bad.last.type, 'RUN_ERROR');
      expect(effects, 0);
      final good = await agent.generate(
        f.request(
          run: 'good',
          parent: 'run',
          text: null,
          resume: [paused.interrupts.single.approve(reason: 'ok')],
        ),
        ownerId: 'owner',
        context: 'x',
      );
      expect(good.status, RunStatus.completed);
      expect(effects, 1);
    },
  );
  test('local interrupt methods reject reasons', () {
    final local = ToolInterrupt(
      id: 'i',
      call: ToolCall(id: 'c', name: 'x', arguments: {}),
      clientExecuted: false,
    );
    expect(() => local.approve(reason: 'no'), throwsStateError);
    expect(() => local.reject(reason: 'no'), throwsStateError);
    final native = ToolInterrupt(
      id: 'i',
      call: NativeToolCall(id: 'c', name: 'x', arguments: {}, provider: 'p'),
      clientExecuted: false,
    );
    expect(() => native.approve(reason: 'no'), throwsStateError);
    expect(() => native.reject(reason: 'no'), throwsStateError);
    final client = ToolInterrupt(
      id: 'i',
      call: ToolCall(id: 'c', name: 'x', arguments: {}),
      clientExecuted: true,
    );
    expect(() => client.approve(reason: 'no'), throwsStateError);
    expect(() => client.reject(reason: 'no'), throwsStateError);
  });
  test('local interrupt response schema hash remains unchanged', () async {
    final store = MemoryRunStore();
    final agent = AiAgent<String>(
      model: f.FakeModel([
        [f.call(), const ModelFinished()],
      ]),
      store: store,
      tools: [f.tool(approval: true)],
    );
    await agent.generate(f.request(), ownerId: 'owner', context: 'x');
    final events = await store.events(
      ownerId: 'owner',
      threadId: 'thread',
      runId: 'run',
    );
    final terminal = events.last;
    final item =
        ((terminal['outcome'] as Map)['interrupts'] as List).single as Map;
    final binding =
        (item['metadata'] as Map)['tanstack:interruptBinding'] as Map;
    expect(
      binding['responseSchemaHash'],
      schemaHash(approvalResponseSchema(f.inputSchema)),
    );
  });
  test(
    'provider approval delivered as local call is rejected before public event',
    () async {
      final model = ApprovalModel([
        [ToolCallReady(call()), const ModelFinished()],
      ]);
      final store = MemoryRunStore();
      final events = await f.run(AiAgent<String>(model: model, store: store));
      expect(events.last.type, 'RUN_ERROR');
      expect(events.where((event) => event.type == 'TOOL_CALL_START'), isEmpty);
      final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      expect(state['pending'], isEmpty);
    },
  );
}
