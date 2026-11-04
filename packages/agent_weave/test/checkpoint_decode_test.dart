import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';
import 'runtime_test.dart' as f;

void main() {
  test(
    'malformed native continuation checkpoint releases reservation intact',
    () async {
      final store = MemoryRunStore();
      final state = <String, Object?>{
        'kind': 'chat',
        'threadId': 'thread',
        'runId': 'seed',
        'status': 'completed',
        'generation': 1,
        'messages': [],
        'nativeContinuationClosed': 42,
        'futureField': {'opaque': 'preserve'},
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
      final agent = AiAgent<String>(model: model, store: store);
      await expectLater(
        agent.generate(
          f.request(run: 'attempt', parent: 'seed', text: null),
          ownerId: 'owner',
          context: 'x',
        ),
        throwsFormatException,
      );
      expect(model.requests, isEmpty);
      expect(await store.load(ownerId: 'owner', threadId: 'thread'), state);
      final preserved = await store.begin(
        ownerId: 'owner',
        threadId: 'thread',
        runId: 'probe',
        parentRunId: 'seed',
      );
      expect(preserved, state);
      await store.save(
        ownerId: 'owner',
        threadId: 'thread',
        runId: 'probe',
        state: preserved,
        release: true,
      );
    },
  );
}
