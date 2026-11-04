/// Serverpod connections and provider approvals for the TanStack Dart client.
library;

import 'dart:async';
import 'dart:convert';
import 'package:tanstack_ai_dart/connections.dart';

export 'src/provider_approval.dart';

/// The callback invokes your generated endpoint with a serialized RunAgentInput.
/// No provider credential belongs in this callback or the Flutter application.
/// [loadHistory] adapts the generated full-history JSON endpoint. Enable server
/// persistence and call ChatClient.attach to restore it. For paging use [hydrate].
ConnectionAdapter serverpodConnection({
  required Stream<String> Function(String requestJson) send,
  HydrateFunction? hydrate,
  Future<String> Function(String threadId)? loadHistory,
  JoinRunFunction? joinRun,
}) {
  if (hydrate != null && loadHistory != null) {
    throw ArgumentError('Provide hydrate or loadHistory, not both.');
  }
  return ConnectionAdapter.connect(
    connect: (messages, {data, signal, required runContext}) {
      final request = <String, Object?>{
        'messages': uiMessagesToWire(messages),
        'threadId': runContext.threadId,
        'runId': runContext.runId,
        if (runContext.parentRunId != null)
          'parentRunId': runContext.parentRunId,
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
                  final chunk = Map<String, dynamic>.from(
                    jsonDecode(raw) as Map,
                  );
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
    hydrate:
        hydrate ??
        (loadHistory == null
            ? null
            : (threadId, {options}) async {
                if (options?.limit != null || options?.before != null) {
                  throw UnsupportedError(
                    'loadHistory returns a full snapshot. Use hydrate for paged history.',
                  );
                }
                return decodeServerpodHistory(await loadHistory(threadId));
              }),
    joinRun: joinRun,
  );
}

/// Decode the JSON returned by the example's authenticated history endpoint.
/// This is a full server-owned snapshot, not a client-side conversation cache.
ChatHydrationResult decodeServerpodHistory(String source) {
  Map<String, dynamic> object(Object? value, String name) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('Expected $name object.');
    }
    return value;
  }

  String identifier(Object? value, String name) {
    if (value is! String || value.isEmpty) {
      throw FormatException('Expected $name identifier.');
    }
    return value;
  }

  final json = object(jsonDecode(source), 'history');
  final rawMessages = json['messages'];
  if (rawMessages is! List) {
    throw const FormatException('Expected history messages.');
  }
  final active = json['activeRun'];
  final interrupts = json['interrupts'];
  final pending = interrupts == null
      ? null
      : object(interrupts, 'interrupts')['pending'];
  if (interrupts != null && pending is! List) {
    throw const FormatException('Expected pending interrupts.');
  }
  final waits = json['pendingWaits'];
  if (waits != null && waits is! List) {
    throw const FormatException('Expected pending waits.');
  }
  final page = json['page'] == null ? null : object(json['page'], 'page');
  if (page != null && page['truncated'] is! bool) {
    throw const FormatException('Expected history page truncation flag.');
  }
  return ChatHydrationResult(
    messages: [for (final message in rawMessages) object(message, 'message')],
    pendingWaits: waits == null ? null : List<Object?>.from(waits as List),
    activeRun: active == null
        ? null
        : ActiveRun(
            identifier(object(active, 'activeRun')['runId'], 'active run'),
          ),
    interrupts: interrupts == null
        ? null
        : ChatInterrupts(
            runId: identifier(
              object(interrupts, 'interrupts')['runId'],
              'interrupted run',
            ),
            pending: [
              for (final item in pending as List) object(item, 'interrupt'),
            ],
          ),
    page: page == null
        ? const ChatHydrationPage.full()
        : ChatHydrationPage(
            truncated: page['truncated'] as bool,
            cursor: page['cursor'] == null
                ? null
                : identifier(page['cursor'], 'page cursor'),
          ),
  );
}
