import 'dart:async';

import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';

void main() {
  test(
    'generation emits progress, typed result and one terminal event',
    () async {
      final task = GenerationTask<int, int>(
        execute: (value, context) async {
          context.reportProgress(0.5, message: 'Working');
          return value * 2;
        },
        encodeResult: (result) => {'answer': result},
      );
      final events = await task.run(21, threadId: 't', runId: 'r').toList();
      expect(events.map((e) => e.type), [
        'RUN_STARTED',
        'CUSTOM',
        'CUSTOM',
        'RUN_FINISHED',
      ]);
      expect(events[1].json['name'], 'generation:progress');
      expect(events[2].json['value'], {'answer': 42});
    },
  );
  for (final progress in [-1.0, 1.1, double.nan, double.infinity]) {
    test(
      'invalid progress $progress fails without exposing internal errors',
      () async {
        final task = GenerationTask<int, int>(
          execute: (value, context) async {
            context.reportProgress(progress);
            return value;
          },
          encodeResult: (result) => result,
        );
        final events = await task.run(0, threadId: 't', runId: 'r').toList();
        expect(events.last.type, 'RUN_ERROR');
      },
    );
  }
  test('pre-cancellation prevents generation submission', () async {
    var called = false;
    final task = GenerationTask<int, int>(
      execute: (value, context) async {
        called = true;
        return value;
      },
      encodeResult: (result) => result,
    );
    final events = await task
        .run(
          0,
          threadId: 't',
          runId: 'r',
          cancellation: CancellationToken()..cancel(),
        )
        .toList();
    expect(events, isEmpty);
    expect(called, isFalse);
  });
  test(
    'generation subscriptions do not cancel a shared parent or sibling',
    () async {
      final parent = CancellationToken();
      final started = <int, Completer<void>>{1: Completer(), 2: Completer()};
      final cancelled = <int, Completer<void>>{1: Completer(), 2: Completer()};
      final task = GenerationTask<int, int>(
        execute: (value, context) async {
          started[value]!.complete();
          await context.cancellation.whenCancelled;
          cancelled[value]!.complete();
          context.cancellation.throwIfCancelled();
          return value;
        },
        encodeResult: (result) => result,
      );
      final one = task
          .run(1, threadId: 't1', runId: 'r1', cancellation: parent)
          .listen(null);
      final two = task
          .run(2, threadId: 't2', runId: 'r2', cancellation: parent)
          .listen(null);
      await Future.wait(started.values.map((c) => c.future));
      await one.cancel().timeout(const Duration(seconds: 1));
      expect(parent.isCancelled, isFalse);
      expect(cancelled[2]!.isCompleted, isFalse);
      parent.cancel();
      await cancelled[2]!.future.timeout(const Duration(seconds: 1));
      await two.cancel();
    },
  );
}
