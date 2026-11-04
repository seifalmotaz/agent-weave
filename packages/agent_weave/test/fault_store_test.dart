import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:test/test.dart';

final class FailOnceStore implements RunStore {
  final inner = MemoryRunStore();
  bool failed = false;
  @override
  Future<void> complete({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject event,
    required JsonObject state,
  }) {
    if (!failed) {
      failed = true;
      throw StateError('checkpoint unavailable');
    }
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
  }) => inner.appendEvent(
    ownerId: ownerId,
    threadId: threadId,
    runId: runId,
    event: event,
  );
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
    'failed completion writes a contiguous failure instead of exposing false success',
    () async {
      final store = FailOnceStore();
      final agent = AiAgent<void>(
        store: store,
        model: ScriptedChatModel(
          steps: [
            [const TextDelta('Answer'), const ModelFinished()],
          ],
        ),
      );
      final events = await agent
          .run(
            ChatRequest(
              threadId: 't',
              runId: 'r',
              messages: [ChatMessage.user('Hi', id: 'u')],
            ),
            ownerId: 'o',
            context: null,
          )
          .toList();
      expect(events.last.type, 'RUN_ERROR');
      expect(events.where((e) => e.type == 'RUN_FINISHED'), isEmpty);
      final stored = await store.events(
        ownerId: 'o',
        threadId: 't',
        runId: 'r',
      );
      expect(
        stored.map((e) => e['sequence']),
        List.generate(stored.length, (i) => i),
      );
      expect(stored.last['type'], 'RUN_ERROR');
      expect(
        (await store.load(ownerId: 'o', threadId: 't'))!['status'],
        'failed',
      );
      await store.begin(ownerId: 'o', threadId: 't', runId: 'next');
    },
  );
}
