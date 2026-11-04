import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';
import 'runtime_test.dart' as f;

class ContractModel implements ChatModel, ModelContinuationContract {
  final f.FakeModel delegate;
  final String identity;
  ContractModel(this.identity, List<List<ModelEvent>> steps)
    : delegate = f.FakeModel(steps);
  @override
  JsonObject get continuationContract => {
    'v': 1,
    'kind': 'fixture',
    'identity': identity,
  };
  @override
  ModelCapabilities get capabilities => delegate.capabilities;
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => delegate.stream(request, cancellation: cancellation);
}

void main() {
  test(
    'changed model contract blocks resumed local effect and preserves retry',
    () async {
      var effects = 0;
      final store = MemoryRunStore();
      final original = ContractModel('a', [
        [f.call(), const ModelFinished()],
        [const ModelFinished()],
      ]);
      final tool = f.tool(
        approval: true,
        execute: (n, _) {
          effects++;
          return n;
        },
      );
      final paused = await AiAgent<String>(
        model: original,
        store: store,
        tools: [tool],
      ).generate(f.request(), ownerId: 'owner', context: 'x');
      final changed = ContractModel('b', []);
      final rejected = await f.run(
        AiAgent<String>(model: changed, store: store, tools: [tool]),
        f.request(
          run: 'bad',
          parent: 'run',
          text: null,
          resume: [paused.interrupts.single.approve()],
        ),
      );
      expect(rejected.last.type, 'RUN_ERROR');
      expect(effects, 0);
      expect(changed.delegate.requests, isEmpty);
      final done =
          await AiAgent<String>(
            model: original,
            store: store,
            tools: [tool],
          ).generate(
            f.request(
              run: 'good',
              parent: 'run',
              text: null,
              resume: [paused.interrupts.single.approve()],
            ),
            ownerId: 'owner',
            context: 'x',
          );
      expect(done.status, RunStatus.completed);
      expect(effects, 1);
    },
  );
  test(
    'unbound sentinel blocks replacement by declared provider model',
    () async {
      var effects = 0;
      final store = MemoryRunStore();
      final tool = f.tool(
        approval: true,
        execute: (n, _) {
          effects++;
          return n;
        },
      );
      final original = f.FakeModel([
        [f.call(), const ModelFinished()],
      ]);
      final paused = await AiAgent<String>(
        model: original,
        store: store,
        tools: [tool],
      ).generate(f.request(), ownerId: 'owner', context: 'x');
      final changed = ContractModel('effectful', []);
      final events = await f.run(
        AiAgent<String>(model: changed, store: store, tools: [tool]),
        f.request(
          run: 'bad',
          parent: 'run',
          text: null,
          resume: [paused.interrupts.single.approve()],
        ),
      );
      expect(events.last.type, 'RUN_ERROR');
      expect(effects, 0);
      expect(changed.delegate.requests, isEmpty);
    },
  );
  for (final variant in ['missing', 'malformed']) {
    test(
      'legacy $variant model binding fails closed without losing state',
      () async {
        final store = MemoryRunStore();
        final original = f.FakeModel([
          [f.call(), const ModelFinished()],
        ]);
        final tool = f.tool(approval: true);
        final paused = await AiAgent<String>(
          model: original,
          store: store,
          tools: [tool],
        ).generate(f.request(), ownerId: 'owner', context: 'x');
        final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
        if (variant == 'missing') {
          state.remove('modelContinuationContract');
        } else {
          state['modelContinuationContract'] = {'v': 2};
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
          AiAgent<String>(model: original, store: store, tools: [tool]),
          f.request(
            run: 'bad',
            parent: 'run',
            text: null,
            resume: [paused.interrupts.single.approve()],
          ),
        );
        expect(events.last.type, 'RUN_ERROR');
        expect(await store.load(ownerId: 'owner', threadId: 'thread'), state);
      },
    );
  }
  test('orphan local call checkpoint without binding fails closed', () async {
    final store = MemoryRunStore();
    final state = <String, Object?>{
      'kind': 'chat',
      'threadId': 'thread',
      'runId': 'seed',
      'generation': 1,
      'status': 'failed',
      'messages': [
        ChatMessage(
          id: 'a',
          role: MessageRole.assistant,
          toolCalls: [
            ToolCall(id: 'c', name: 'double', arguments: {'count': 2}),
          ],
        ).toJson(),
      ],
    };
    await store.begin(ownerId: 'owner', threadId: 'thread', runId: 'seed');
    await store.save(
      ownerId: 'owner',
      threadId: 'thread',
      runId: 'seed',
      state: state,
      release: true,
    );
    final model = f.FakeModel([]);
    final events = await f.run(
      AiAgent<String>(model: model, store: store, tools: [f.tool()]),
      f.request(run: 'bad', text: null),
    );
    expect(events.last.type, 'RUN_ERROR');
    expect(model.requests, isEmpty);
    expect(await store.load(ownerId: 'owner', threadId: 'thread'), state);
  });
  test(
    'step-limit continuation retains binding across recreation and clears after completion',
    () async {
      final store = MemoryRunStore();
      final original = ContractModel('a', [
        [const TextDelta('pause'), const ModelFinished.continuation()],
        [const ModelFinished()],
      ]);
      final first = AiAgent<String>(model: original, store: store, maxSteps: 1);
      await expectLater(
        first.generate(f.request(), ownerId: 'owner', context: 'x'),
        throwsA(
          isA<AgentRunException>().having((e) => e.code, 'code', 'STEP_LIMIT'),
        ),
      );
      final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      expect(
        ((state['modelContinuationContract'] as Map)['model']
            as Map)['identity'],
        'a',
      );
      expect(state['providerContinuationPending'], true);
      final changed = ContractModel('b', []);
      final rejected = await f.run(
        AiAgent<String>(model: changed, store: store),
        f.request(run: 'bad', text: null),
      );
      expect(rejected.last.type, 'RUN_ERROR');
      expect(changed.delegate.requests, isEmpty);
      final done = await AiAgent<String>(model: original, store: store)
          .generate(
            f.request(run: 'resume', text: null),
            ownerId: 'owner',
            context: 'x',
          );
      expect(done.status, RunStatus.completed);
      expect(
        (await store.load(
          ownerId: 'owner',
          threadId: 'thread',
        ))!.containsKey('modelContinuationContract'),
        false,
      );
      final next = ContractModel('b', [
        [const ModelFinished()],
      ]);
      final fresh = await AiAgent<String>(model: next, store: store).generate(
        f.request(run: 'next'),
        ownerId: 'owner',
        context: 'x',
      );
      expect(fresh.status, RunStatus.completed);
    },
  );
  for (final status in [
    'running',
    'interrupted',
    'failed',
    'cancelled',
    'completed',
  ]) {
    test(
      'legacy $status history with completed local call has safe continuation',
      () async {
        final store = MemoryRunStore();
        final state = <String, Object?>{
          'kind': 'chat',
          'threadId': 'thread',
          'runId': 'seed',
          'generation': 1,
          'status': status,
          'messages': [
            ChatMessage(
              id: 'a',
              role: MessageRole.assistant,
              toolCalls: [
                ToolCall(id: 'c', name: 'double', arguments: {'count': 2}),
              ],
            ).toJson(),
            ChatMessage(
              id: 'result',
              role: MessageRole.tool,
              toolCallId: 'c',
              content: [TextPart('4')],
            ).toJson(),
          ],
          'events': [
            {'type': 'RUN_ERROR', 'code': 'STEP_LIMIT'},
          ],
        };
        await store.begin(ownerId: 'owner', threadId: 'thread', runId: 'seed');
        await store.save(
          ownerId: 'owner',
          threadId: 'thread',
          runId: 'seed',
          state: state,
          release: true,
        );
        final model = ContractModel('new', [
          [const ModelFinished()],
        ]);
        final events = await f.run(
          AiAgent<String>(model: model, store: store),
          f.request(
            run: 'next',
            parent: status == 'interrupted' ? 'seed' : null,
            text: null,
          ),
        );
        if (status == 'completed') {
          expect(events.last.type, 'RUN_FINISHED');
          expect(model.delegate.requests, hasLength(1));
        } else {
          expect(events.last.type, 'RUN_ERROR');
          expect(model.delegate.requests, isEmpty);
          expect(await store.load(ownerId: 'owner', threadId: 'thread'), state);
        }
      },
    );
  }
}
