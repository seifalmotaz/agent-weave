import 'dart:async';
import 'dart:convert';
import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart' as client;
import 'package:test/test.dart';

void main() {
  test(
    'serializes identity, lineage and resume without sending authentication secrets',
    () async {
      String? sent;
      final connection = serverpodConnection(
        send: (request) {
          sent = request;
          return Stream.value(
            '{"type":"RUN_FINISHED","runId":"r","threadId":"t"}',
          );
        },
      );
      final chunks = await connection
          .connect!(
            [],
            runContext: const client.RunAgentInputContext(
              threadId: 't',
              runId: 'r',
              parentRunId: 'parent',
              resume: [
                {'interruptId': 'i', 'value': true},
              ],
              headers: {'Authorization': 'do-not-send-in-body'},
            ),
          )
          .toList();
      expect((jsonDecode(sent!) as Map)['parentRunId'], 'parent');
      expect(sent, isNot(contains('do-not-send-in-body')));
      expect(chunks.single['type'], 'RUN_FINISHED');
    },
  );
  test('rejects malformed endpoint events', () async {
    final connection = serverpodConnection(
      send: (_) => Stream.value('{"hello":true}'),
    );
    await expectLater(
      connection
          .connect!(
            [],
            runContext: const client.RunAgentInputContext(
              threadId: 't',
              runId: 'r',
            ),
          )
          .toList(),
      throwsFormatException,
    );
  });
  test(
    'consumer cancellation closes the native endpoint subscription',
    () async {
      var cancelled = false;
      final source = StreamController<String>(onCancel: () => cancelled = true);
      final connection = serverpodConnection(send: (_) => source.stream);
      final sub = connection
          .connect!(
            [],
            runContext: const client.RunAgentInputContext(
              threadId: 't',
              runId: 'r',
            ),
          )
          .listen((_) {});
      await sub.cancel();
      expect(cancelled, isTrue);
      await source.close();
    },
  );
  test('pre-cancelled signal never invokes the endpoint', () async {
    var called = false;
    final connection = serverpodConnection(
      send: (_) {
        called = true;
        return const Stream.empty();
      },
    );
    final cancellation = client.CancellationController()..cancel();
    expect(
      await connection
          .connect!(
            [],
            signal: cancellation.signal,
            runContext: const client.RunAgentInputContext(
              threadId: 't',
              runId: 'r',
            ),
          )
          .toList(),
      isEmpty,
    );
    expect(called, isFalse);
  });
}
