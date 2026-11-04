import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

class _Model implements ChatModel {
  int requests = 0;
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(tools: true);
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    requests++;
    if (requests == 1) {
      yield ToolCallReady(ToolCall(id: 'call', name: 'send', arguments: {}));
    } else {
      yield const TextDelta('Done');
    }
    yield const ModelFinished();
  }
}

void main() {
  withServerpod('Typed stream PostgreSQL persistence', (builder, _) {
    test('approval survives agent recreation and isolates owners', () async {
      final model = _Model();
      var effects = 0;
      AiAgent<void> agent() => AiAgent<void>(
        model: model,
        store: ServerpodRunStore(builder.build()),
        tools: [
          Tool<JsonObject, String, void>(
            name: 'send',
            description: 'Send',
            needsApproval: true,
            inputSchema: const {'type': 'object'},
            decode: (json) => json,
            encode: (value) => value,
            execute: (_, _) {
              effects++;
              return 'sent';
            },
          ),
        ],
      );
      final first = await agent()
          .stream(
            ChatRequest(
              threadId: 'typed-stream',
              runId: 'first',
              messages: [ChatMessage.user('Start', id: 'u')],
            ),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      final paused = (first.last as AgentRunFinished).result;
      expect(paused.status, RunStatus.interrupted);
      expect(effects, 0);
      final savedPause = (await agent().store.load(
        ownerId: 'owner',
        threadId: 'typed-stream',
      ))!;
      expect(savedPause['status'], 'interrupted');
      expect(savedPause['pending'], hasLength(1));
      expect(
        await agent().store.load(ownerId: 'other', threadId: 'typed-stream'),
        isNull,
      );
      final resumed = await agent()
          .stream(
            ChatRequest(
              threadId: 'typed-stream',
              runId: 'next',
              parentRunId: 'first',
              resume: [paused.interrupts.single.approve()],
            ),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      expect(resumed.whereType<AgentToolResult>().single.result, 'sent');
      expect((resumed.last as AgentRunFinished).result.text, 'Done');
      expect(effects, 1);
      expect(model.requests, 2);
      final saved = (await agent().store.load(
        ownerId: 'owner',
        threadId: 'typed-stream',
      ))!;
      expect(saved['status'], 'completed');
      expect(saved['pending'], isEmpty);
      expect(
        ChatMessage.fromJson(
          Map<String, Object?>.from((saved['messages'] as List).last as Map),
        ).text,
        'Done',
      );
      final journal = await agent().store.events(
        ownerId: 'owner',
        threadId: 'typed-stream',
        runId: 'next',
      );
      expect(journal.last['type'], 'RUN_FINISHED');
      expect(
        journal.where((event) => event['type'] == 'RUN_FINISHED'),
        hasLength(1),
      );
      expect(journal.map((event) => event['sequence']), [
        for (var i = 0; i < journal.length; i++) i,
      ]);
    });
  });
}
