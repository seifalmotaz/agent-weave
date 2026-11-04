import 'dart:async';
import 'dart:convert';
import 'cancellation.dart';
import 'model.dart';
import 'protocol.dart';
import 'storage.dart';

final class GenerationContext {
  final CancellationToken cancellation;
  final void Function(double progress, String? message) _report;
  const GenerationContext._(this.cancellation, this._report);
  void reportProgress(double progress, {String? message}) {
    if (!progress.isFinite || progress < 0 || progress > 1) {
      throw ArgumentError.value(
        progress,
        'progress',
        'Expected a value in [0, 1].',
      );
    }
    cancellation.throwIfCancelled();
    _report(progress, message);
  }
}

/// Adapts a typed operation to TanStack's generation result/progress protocol.
final class GenerationTask<P, R> {
  final Future<R> Function(P parameters, GenerationContext context) execute;
  final Object? Function(R result) encodeResult;
  final void Function(Object, StackTrace)? onError;
  final RunStore? store;
  const GenerationTask({
    required this.execute,
    required this.encodeResult,
    this.onError,
    this.store,
  });

  Stream<AgentEvent> run(
    P parameters, {
    required String threadId,
    required String runId,
    String? ownerId,
    CancellationToken? cancellation,
  }) {
    ChatRequest(threadId: threadId, runId: runId);
    if (store != null && (ownerId == null || ownerId.isEmpty)) {
      throw ArgumentError(
        'Persistent generations require a server-derived ownerId.',
      );
    }
    final token = cancellation ?? CancellationToken();
    var sequence = 0;
    late final StreamController<AgentEvent> controller;
    void add(String type, [JsonObject fields = const {}]) {
      if (controller.isClosed || token.isCancelled) return;
      controller.add(
        AgentEvent({
          'type': type,
          'threadId': threadId,
          'runId': runId,
          'sequence': sequence++,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          ...fields,
        }),
      );
    }

    Future<void> start() async {
      try {
        token.throwIfCancelled();
        add('RUN_STARTED');
        final result = await execute(
          parameters,
          GenerationContext._(
            token,
            (progress, message) => add('CUSTOM', {
              'name': 'generation:progress',
              'value': {'progress': progress, 'message': ?message},
            }),
          ),
        );
        token.throwIfCancelled();
        final encoded = encodeResult(result);
        jsonEncode(encoded);
        add('CUSTOM', {'name': 'generation:result', 'value': encoded});
        add('RUN_FINISHED');
      } catch (error, stack) {
        onError?.call(error, stack);
        if (!token.isCancelled) {
          add('RUN_ERROR', {
            'code': 'GENERATION_FAILED',
            'message': 'The generation could not complete.',
          });
        }
      } finally {
        await controller.close();
      }
    }

    controller = StreamController<AgentEvent>(
      onListen: () => unawaited(start()),
      onCancel: token.cancel,
    );
    final persistence = store;
    if (persistence == null) return controller.stream;
    StreamSubscription<AgentEvent>? subscription;
    late final StreamController<AgentEvent> output;
    output = StreamController<AgentEvent>(
      onListen: () {
        subscription = _persist(
          controller.stream,
          persistence,
          ownerId!,
          threadId,
          runId,
          token,
        ).listen(output.add, onError: output.addError, onDone: output.close);
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        token.cancel();
        await subscription?.cancel();
      },
    );
    return output.stream;
  }
}

Stream<AgentEvent> _persist(
  Stream<AgentEvent> source,
  RunStore store,
  String ownerId,
  String threadId,
  String runId,
  CancellationToken cancellation,
) async* {
  final previous = await store.begin(
    ownerId: ownerId,
    threadId: threadId,
    runId: runId,
  );
  final state = <String, Object?>{
    'kind': 'generation',
    'threadId': threadId,
    'runId': runId,
    'status': 'running',
    'result': null,
    'progress': 0,
  };
  var released = false;
  try {
    if (previous['kind'] != null && previous['kind'] != 'generation') {
      await store.save(
        ownerId: ownerId,
        threadId: threadId,
        runId: runId,
        state: previous,
        release: true,
      );
      released = true;
      throw const RunConflict('Thread belongs to a different operation.');
    }
    await for (final event in source) {
      cancellation.throwIfCancelled();
      await store.appendEvent(
        ownerId: ownerId,
        threadId: threadId,
        runId: runId,
        event: event.json,
      );
      if (event.json['name'] == 'generation:result') {
        state['result'] = event.json['value'];
      }
      if (event.json['name'] == 'generation:progress') {
        state['progress'] = (event.json['value'] as Map)['progress'];
      }
      if (event.type == 'RUN_FINISHED') state['status'] = 'completed';
      if (event.type == 'RUN_ERROR') state['status'] = 'failed';
      final terminal =
          event.type == 'RUN_FINISHED' || event.type == 'RUN_ERROR';
      await store.save(
        ownerId: ownerId,
        threadId: threadId,
        runId: runId,
        state: state,
        release: terminal,
      );
      released = terminal;
      yield event;
    }
  } finally {
    if (!released) {
      state['status'] = 'cancelled';
      await store.save(
        ownerId: ownerId,
        threadId: threadId,
        runId: runId,
        state: state,
        release: true,
      );
    }
  }
}
