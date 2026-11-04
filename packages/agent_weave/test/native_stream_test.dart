import 'dart:async';
import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:test/test.dart';

import 'citations_test.dart' as citations;
import 'fault_store_test.dart' as faults;
import 'references_test.dart' as refs;
import 'runtime_test.dart' as fixtures;

class _ContentOnlyModel implements ChatModel {
  final proceed = Completer<void>();
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    yield ContentPartReady(ImagePart('data:image/png;base64,aGVsbG8='));
    await proceed.future;
    yield const ModelFinished();
  }
}

final class _MutatingStore implements RunStore {
  final inner = MemoryRunStore();
  final void Function() mutate;
  _MutatingStore(this.mutate);
  @override
  Future<void> complete({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject event,
    required JsonObject state,
  }) {
    return inner.complete(
      ownerId: ownerId,
      threadId: threadId,
      runId: runId,
      event: event,
      state: state,
    );
  }

  @override
  Future<JsonObject> begin({
    required String ownerId,
    required String threadId,
    required String runId,
    String? parentRunId,
  }) => inner.begin(
    ownerId: ownerId,
    threadId: threadId,
    runId: runId,
    parentRunId: parentRunId,
  );
  @override
  Future<void> save({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject state,
    required bool release,
  }) => inner.save(
    ownerId: ownerId,
    threadId: threadId,
    runId: runId,
    state: state,
    release: release,
  );
  @override
  Future<JsonObject?> load({
    required String ownerId,
    required String threadId,
  }) => inner.load(ownerId: ownerId, threadId: threadId);
  @override
  Future<String?> threadForRun({
    required String ownerId,
    required String runId,
  }) => inner.threadForRun(ownerId: ownerId, runId: runId);
  @override
  Future<void> appendEvent({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject event,
  }) async {
    await inner.appendEvent(
      ownerId: ownerId,
      threadId: threadId,
      runId: runId,
      event: event,
    );
    if (event['type'] == 'TOOL_CALL_RESULT') mutate();
  }

  @override
  Future<List<JsonObject>> events({
    required String ownerId,
    required String threadId,
    required String runId,
    int afterSequence = -1,
  }) => inner.events(
    ownerId: ownerId,
    threadId: threadId,
    runId: runId,
    afterSequence: afterSequence,
  );
}

void main() {
  test(
    'typed updates expose content and the committed result in one run',
    () async {
      final image = ImagePart('data:image/png;base64,aGVsbG8=');
      final ref = refs.reference(FileListPosition(0));
      final model = ScriptedChatModel(
        steps: [
          [
            const TextDelta('x'),
            const ReasoningDelta('thinking'),
            ContentPartReady(image),
            ReferenceReady(ref),
            CitationReady(citations.cite(0, 1)),
            ProviderOutput(
              provider: 'private',
              items: [
                {'secret': 'private-marker'},
              ],
            ),
            const TokenUsage(inputTokens: 2, outputTokens: 1),
            const ModelFinished(),
          ],
        ],
      );
      final agent = AiAgent<void>(model: model);
      final updates = await agent
          .stream(
            ChatRequest(threadId: 't', runId: 'r'),
            ownerId: 'o',
            context: null,
          )
          .toList();
      expect(updates.whereType<AgentTextDelta>().single.text, 'x');
      expect(updates.whereType<AgentReasoningDelta>().single.text, 'thinking');
      expect(updates.whereType<AgentContentPart>().single.part, same(image));
      expect(updates.whereType<AgentContentPart>().single.textOffset, 1);
      expect(updates.whereType<AgentReference>().single.reference, same(ref));
      expect(
        updates.whereType<AgentCitation>().single.citation.source,
        isA<UrlCitationSource>(),
      );
      expect(updates.whereType<AgentUsage>().single.usage.inputTokens, 2);
      expect(updates.whereType<AgentRunFinished>(), hasLength(1));
      final result = (updates.last as AgentRunFinished).result;
      expect(result.text, 'x');
      expect(
        result
            .responseMessages
            .single
            .providerData['private']!
            .single['secret'],
        'private-marker',
      );
      expect(result.status, RunStatus.completed);
      expect(model.requests, hasLength(1));
      expect(updates.map((update) => update.runtimeType), [
        AgentTextDelta,
        AgentReasoningDelta,
        AgentContentPart,
        AgentReference,
        AgentCitation,
        AgentUsage,
        AgentRunFinished,
      ]);
      expect(await agent.store.load(ownerId: 'o', threadId: 't'), isNotNull);
    },
  );

  test(
    'approval pauses and resumes with one effect and no extra model call',
    () async {
      var effects = 0;
      final model = fixtures.FakeModel([
        [fixtures.call(), const ModelFinished()],
        [const TextDelta('done'), const ModelFinished()],
      ]);
      final agent = AiAgent<String>(
        model: model,
        tools: [
          fixtures.tool(
            approval: true,
            execute: (n, _) {
              effects++;
              return n * 2;
            },
          ),
        ],
      );
      final first = await agent
          .stream(fixtures.request(), ownerId: 'owner', context: 'context')
          .toList();
      expect(first.whereType<AgentToolCallReady>(), hasLength(1));
      final paused = (first.last as AgentRunFinished).result;
      expect(paused.status, RunStatus.interrupted);
      expect(effects, 0);
      final next = await agent
          .stream(
            fixtures.request(
              run: 'next',
              parent: 'run',
              text: null,
              resume: [paused.interrupts.single.approve()],
            ),
            ownerId: 'owner',
            context: 'context',
          )
          .toList();
      expect(next.whereType<AgentToolResult>().single.result, 4);
      expect((next.last as AgentRunFinished).result.text, 'done');
      expect(effects, 1);
      expect(model.requests, hasLength(2));
    },
  );

  test(
    'invalid structured output throws with a typed partial result',
    () async {
      final agent = AiAgent<void>(
        outputSchema: const {'type': 'object'},
        model: ScriptedChatModel(
          capabilities: const ModelCapabilities(structuredOutput: true),
          steps: [
            [const TextDelta('not JSON'), const ModelFinished()],
          ],
        ),
      );
      final updates = <AgentUpdate>[];
      await expectLater(
        () async {
          await for (final update in agent.stream(
            ChatRequest(threadId: 't', runId: 'r'),
            ownerId: 'o',
            context: null,
          )) {
            updates.add(update);
          }
        },
        throwsA(
          isA<AgentRunException>()
              .having((e) => e.code, 'code', 'INVALID_OUTPUT')
              .having((e) => e.result.text, 'partial text', 'not JSON'),
        ),
      );
      expect(updates.whereType<AgentTextDelta>().single.text, 'not JSON');
      expect(updates.whereType<AgentRunFinished>(), isEmpty);
    },
  );
  test('content-only update arrives before the provider finishes', () async {
    final model = _ContentOnlyModel();
    final seen = Completer<AgentContentPart>();
    final done = Completer<void>();
    final subscription = AiAgent<void>(model: model)
        .stream(
          ChatRequest(threadId: 'content', runId: 'r'),
          ownerId: 'o',
          context: null,
        )
        .listen(
          (event) {
            if (event is AgentContentPart) seen.complete(event);
          },
          onError: done.completeError,
          onDone: done.complete,
        );
    await seen.future.timeout(const Duration(seconds: 2));
    expect(done.isCompleted, isFalse);
    model.proceed.complete();
    await done.future.timeout(const Duration(seconds: 2));
    await subscription.cancel();
  });

  test(
    'subscription cancellation releases reservation without cancelling siblings',
    () async {
      final parent = CancellationToken();
      final model = fixtures.MultiBlockingModel();
      final agent = AiAgent<String>(model: model);
      final one = agent
          .stream(
            fixtures.request(thread: 'one', run: 'one'),
            ownerId: 'owner',
            context: 'x',
            cancellation: parent,
          )
          .listen(null, onError: (Object _) {});
      final two = agent
          .stream(
            fixtures.request(thread: 'two', run: 'two'),
            ownerId: 'owner',
            context: 'x',
            cancellation: parent,
          )
          .listen(null, onError: (Object _) {});
      await model.started.future.timeout(const Duration(seconds: 2));
      await one.cancel().timeout(const Duration(seconds: 2));
      expect(parent.isCancelled, isFalse);
      expect(model.tokens.where((t) => t.isCancelled), hasLength(1));
      final state = await agent.store.load(ownerId: 'owner', threadId: 'one');
      expect(state!['status'], 'cancelled');
      parent.cancel();
      await two.cancel();
    },
  );
  test(
    'streamText produces the terminal result without a second invocation',
    () async {
      final model = ScriptedChatModel(
        steps: [
          [const TextDelta('hello'), const ModelFinished()],
        ],
      );
      final updates = await streamText(model: model, prompt: 'Hi').toList();
      expect((updates.last as AgentRunFinished).result.text, 'hello');
      expect(model.requests, hasLength(1));
    },
  );

  test('valid structured output is returned by the finished update', () async {
    final model = ScriptedChatModel(
      capabilities: const ModelCapabilities(structuredOutput: true),
      steps: [
        [const TextDelta('{"answer":42}'), const ModelFinished()],
      ],
    );
    final updates =
        await AiAgent<void>(
              model: model,
              outputSchema: const {'type': 'object'},
            )
            .stream(
              ChatRequest(threadId: 't', runId: 'r'),
              ownerId: 'o',
              context: null,
            )
            .toList();
    expect((updates.last as AgentRunFinished).result.output, {'answer': 42});
  });
  test('failed terminal checkpoint never publishes finished', () async {
    final store = faults.FailOnceStore();
    final model = ScriptedChatModel(
      steps: [
        [const TextDelta('answer'), const ModelFinished()],
      ],
    );
    final seen = <AgentUpdate>[];
    await expectLater(() async {
      await for (final update
          in AiAgent<void>(model: model, store: store).stream(
            ChatRequest(threadId: 't', runId: 'r'),
            ownerId: 'o',
            context: null,
          )) {
        seen.add(update);
      }
    }, throwsA(isA<AgentRunException>()));
    expect(seen.whereType<AgentRunFinished>(), isEmpty);
    expect(
      (await store.load(ownerId: 'o', threadId: 't'))!['status'],
      'failed',
    );
  });
  test('caller cancellation throws only after cleanup', () async {
    final parent = CancellationToken();
    final model = fixtures.BlockingModel();
    final agent = AiAgent<String>(model: model);
    final done = agent
        .stream(
          fixtures.request(),
          ownerId: 'owner',
          context: 'x',
          cancellation: parent,
        )
        .toList();
    await model.started.future.timeout(const Duration(seconds: 2));
    parent.cancel();
    await expectLater(done, throwsA(isA<RunCancelled>()));
    expect(
      (await agent.store.load(ownerId: 'owner', threadId: 'thread'))!['status'],
      'cancelled',
    );
    await agent.store.begin(
      ownerId: 'owner',
      threadId: 'thread',
      runId: 'next',
      parentRunId: 'run',
    );
  });
  test('paused subscriber receives remaining updates after resume', () async {
    final model = ScriptedChatModel(
      steps: [
        [const TextDelta('one'), const TextDelta('two'), const ModelFinished()],
      ],
    );
    final first = Completer<void>();
    final done = Completer<void>();
    final seen = <String>[];
    late StreamSubscription<AgentUpdate> subscription;
    subscription = streamText(model: model, prompt: 'Hi').listen(
      (event) {
        if (event is AgentTextDelta) {
          seen.add(event.text);
          if (seen.length == 1) {
            subscription.pause();
            first.complete();
          }
        }
      },
      onError: done.completeError,
      onDone: done.complete,
    );
    await first.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(seen, ['one']);
    expect(done.isCompleted, isFalse);
    subscription.resume();
    await done.future.timeout(const Duration(seconds: 2));
    expect(seen, ['one', 'two']);
  });

  test(
    'pre-cancelled token emits one cancellation without invoking model',
    () async {
      final model = fixtures.FakeModel([]);
      final token = CancellationToken()..cancel();
      await expectLater(
        AiAgent<String>(model: model)
            .stream(
              fixtures.request(),
              ownerId: 'owner',
              context: 'x',
              cancellation: token,
            )
            .toList(),
        throwsA(isA<RunCancelled>()),
      );
      expect(model.requests, isEmpty);
    },
  );
  test('taking first update releases the reservation', () async {
    final model = _ContentOnlyModel();
    final agent = AiAgent<void>(model: model);
    final first = await agent
        .stream(
          ChatRequest(threadId: 'first', runId: 'r'),
          ownerId: 'o',
          context: null,
        )
        .first
        .timeout(const Duration(seconds: 2));
    expect(first, isA<AgentContentPart>());
    expect(
      (await agent.store.load(ownerId: 'o', threadId: 'first'))!['status'],
      'cancelled',
    );
    await agent.store.begin(
      ownerId: 'o',
      threadId: 'first',
      runId: 'next',
      parentRunId: 'r',
    );
  });
  test(
    'tool results snapshot dynamic nested maps from encode and direct updates',
    () async {
      final inner = <dynamic, dynamic>{'value': 1};
      final values = <dynamic>[inner];
      final original = <dynamic, dynamic>{'nested': values};
      final call = ToolCall(id: 'c', name: 'snapshot', arguments: {});
      final direct = AgentToolResult(call: call, result: original);
      final model = fixtures.FakeModel([
        [ToolCallReady(call), const ModelFinished()],
        [const ModelFinished()],
      ]);
      final agent = AiAgent<void>(
        model: model,
        tools: [
          Tool<JsonObject, int, void>(
            name: 'snapshot',
            description: 'Snapshot',
            inputSchema: const {'type': 'object'},
            decode: (value) => value,
            execute: (_, _) => 1,
            encode: (_) => original,
          ),
        ],
      );
      final updates = await agent
          .stream(
            ChatRequest(threadId: 'snapshot', runId: 'r'),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      final emitted = updates.whereType<AgentToolResult>().single;
      inner['value'] = 9;
      values.add('changed');
      original['new'] = true;
      for (final update in [direct, emitted]) {
        final result = update.result as Map;
        final nested = result['nested'] as List;
        expect(result, {
          'nested': [
            {'value': 1},
          ],
        });
        expect(() => result['new'] = true, throwsUnsupportedError);
        expect(() => nested.add(2), throwsUnsupportedError);
        expect(
          () => (nested.single as Map)['value'] = 3,
          throwsUnsupportedError,
        );
      }
    },
  );

  test('JSON snapshots preserve large integers and reject non-string keys', () {
    const number = 9007199254740993;
    final snapshot = immutableJson({
      'nested': <dynamic, dynamic>{'number': number},
    });
    expect((snapshot['nested'] as Map)['number'], number);
    expect(
      () => immutableJson({
        'nested': <dynamic, dynamic>{1: 'bad'},
      }),
      throwsArgumentError,
    );
    expect(
      () => AgentToolResult(
        call: ToolCall(id: 'c', name: 't', arguments: {}),
        result: <dynamic, dynamic>{1: 'bad'},
      ),
      throwsArgumentError,
    );
  });
  test(
    'tool update matches persisted value when encode source mutates during append',
    () async {
      final nested = <dynamic, dynamic>{'value': 1};
      final original = <dynamic, dynamic>{
        'nested': [nested],
      };
      final store = _MutatingStore(() => nested['value'] = 2);
      final call = ToolCall(id: 'c', name: 'snapshot', arguments: {});
      final model = fixtures.FakeModel([
        [ToolCallReady(call), const ModelFinished()],
        [const ModelFinished()],
      ]);
      final agent = AiAgent<void>(
        model: model,
        store: store,
        tools: [
          Tool<JsonObject, int, void>(
            name: 'snapshot',
            description: 'Snapshot',
            inputSchema: const {'type': 'object'},
            decode: (value) => value,
            execute: (_, _) => 1,
            encode: (_) => original,
          ),
        ],
      );
      final updates = await agent
          .stream(
            ChatRequest(threadId: 'race', runId: 'r'),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      final native = updates.whereType<AgentToolResult>().single.result;
      final result = (updates.last as AgentRunFinished).result;
      final message = result.responseMessages.singleWhere(
        (message) => message.role == MessageRole.tool,
      );
      final events = await store.events(
        ownerId: 'owner',
        threadId: 'race',
        runId: 'r',
      );
      final wire = events.singleWhere(
        (event) => event['type'] == 'TOOL_CALL_RESULT',
      );
      expect(jsonDecode(message.text), {
        'nested': [
          {'value': 1},
        ],
      });
      expect(jsonDecode(wire['content'] as String), {
        'nested': [
          {'value': 1},
        ],
      });
      expect(native, {
        'nested': [
          {'value': 1},
        ],
      });
    },
  );
}
