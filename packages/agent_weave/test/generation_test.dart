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
}
