/// Connect a generated Serverpod streaming method to the TanStack Dart client.
library;

import 'dart:async';
import 'dart:convert';
import 'package:tanstack_ai_dart/connections.dart';

/// The callback invokes your generated endpoint with a serialized RunAgentInput.
/// No OpenAI credential belongs in this callback or the Flutter application.
ConnectionAdapter serverpodConnection({
  required Stream<String> Function(String requestJson) send,
  HydrateFunction? hydrate,
  JoinRunFunction? joinRun,
}) => ConnectionAdapter.connect(
  connect: (messages, {data, signal, required runContext}) {
    final request = <String, Object?>{
      'messages': uiMessagesToWire(messages),
      'threadId': runContext.threadId,
      'runId': runContext.runId,
      if (runContext.parentRunId != null) 'parentRunId': runContext.parentRunId,
      if (runContext.resume != null) 'resume': runContext.resume,
      if (runContext.clientTools != null)
        'tools': runContext.clientTools!.map((t) => t.toJson()).toList(),
      if (data != null || runContext.forwardedProps != null)
        'forwardedProps': {...?data, ...?runContext.forwardedProps},
    };
    if (signal?.isCancelled ?? false) return const Stream.empty();
    StreamSubscription<String>? subscription;
    late final StreamController<StreamChunk> controller;
    void cancel() {
      unawaited(subscription?.cancel());
      unawaited(controller.close());
    }

    controller = StreamController<StreamChunk>(
      onListen: () {
        signal?.addListener(cancel);
        try {
          subscription = send(jsonEncode(request)).listen(
            (raw) {
              try {
                final chunk = Map<String, dynamic>.from(jsonDecode(raw) as Map);
                if (chunk['type'] is! String) {
                  throw const FormatException('Expected event type.');
                }
                controller.add(chunk);
              } catch (error, stack) {
                controller.addError(error, stack);
              }
            },
            onError: controller.addError,
            onDone: controller.close,
          );
        } catch (error, stack) {
          controller.addError(error, stack);
          unawaited(controller.close());
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        signal?.removeListener(cancel);
        await subscription?.cancel();
      },
    );
    return controller.stream;
  },
  hydrate: hydrate,
  joinRun: joinRun,
);
