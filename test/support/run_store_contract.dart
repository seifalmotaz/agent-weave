import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';

/// The same behavioral contract runs against memory and real PostgreSQL.
void runStoreContract(RunStore Function() createStore) {
  Future<void> reserve(RunStore store, String thread) =>
      store.begin(ownerId: 'contract', threadId: thread, runId: thread);
  Future<List<JsonObject>> events(RunStore store, String thread) =>
      store.events(ownerId: 'contract', threadId: thread, runId: thread);
  Future<void> complete(
    RunStore store,
    String thread, {
    JsonObject state = const {'status': 'completed'},
    String owner = 'contract',
    int sequence = 0,
    String type = 'RUN_FINISHED',
  }) => store.complete(
    ownerId: owner,
    threadId: thread,
    runId: thread,
    event: {'type': type, 'sequence': sequence},
    state: state,
  );

  test(
    'failed terminal checkpoint cannot expose a success event or release the run',
    () async {
      final store = createStore();
      const thread = 'atomic-rollback';
      await reserve(store, thread);
      await expectLater(
        complete(store, thread, state: {'invalid': DateTime.utc(2026)}),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );
      expect(await events(store, thread), isEmpty);
      expect(
        await store.load(ownerId: 'contract', threadId: thread),
        anyOf(isNull, isEmpty),
      );
      await expectLater(
        store.begin(
          ownerId: 'contract',
          threadId: thread,
          runId: 'next-$thread',
        ),
        throwsA(isA<RunConflict>()),
      );
      await complete(store, thread);
      expect((await events(store, thread)).single['type'], 'RUN_FINISHED');
      expect(
        (await store.load(ownerId: 'contract', threadId: thread))!['status'],
        'completed',
      );
      await store.begin(
        ownerId: 'contract',
        threadId: thread,
        runId: 'next-$thread',
      );
    },
  );
  test('only the reservation owner can complete a run', () async {
    final store = createStore();
    const thread = 'atomic-owner';
    await reserve(store, thread);
    await expectLater(
      complete(store, thread, owner: 'attacker'),
      throwsA(isA<RunConflict>()),
    );
    expect(await events(store, thread), isEmpty);
    await complete(store, thread);
    expect(
      await store.events(ownerId: 'attacker', threadId: thread, runId: thread),
      isEmpty,
    );
  });
  test('gaps and duplicate event sequences are rejected', () async {
    final store = createStore();
    const thread = 'atomic-sequence';
    await reserve(store, thread);
    await expectLater(
      complete(store, thread, sequence: 1),
      throwsA(isA<RunConflict>()),
    );
    expect(await events(store, thread), isEmpty);
    await store.appendEvent(
      ownerId: 'contract',
      threadId: thread,
      runId: thread,
      event: {'type': 'RUN_STARTED', 'sequence': 0},
    );
    await expectLater(complete(store, thread), throwsA(isA<RunConflict>()));
    expect(await events(store, thread), hasLength(1));
    await complete(store, thread, sequence: 1);
    expect((await events(store, thread)).map((e) => e['sequence']), [0, 1]);
  });
  test('non-terminal events cannot release reservations', () async {
    final store = createStore();
    const thread = 'atomic-terminal';
    await reserve(store, thread);
    await expectLater(
      complete(store, thread, type: 'CUSTOM'),
      throwsArgumentError,
    );
    expect(await events(store, thread), isEmpty);
    await complete(store, thread);
  });
  test('stale writers cannot overwrite a completed checkpoint', () async {
    final store = createStore();
    const thread = 'atomic-stale';
    await reserve(store, thread);
    await complete(store, thread);
    await expectLater(
      store.save(
        ownerId: 'contract',
        threadId: thread,
        runId: thread,
        state: {'status': 'running'},
        release: false,
      ),
      throwsA(isA<RunConflict>()),
    );
    expect(
      (await store.load(ownerId: 'contract', threadId: thread))!['status'],
      'completed',
    );
    await expectLater(
      complete(store, thread, sequence: 1),
      throwsA(isA<RunConflict>()),
    );
    expect(await events(store, thread), hasLength(1));
  });
}
