import 'dart:async';
import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:dart_frog/dart_frog.dart';

/// Identity and application context established by trusted server authentication.
typedef AgentIdentity<C> = ({String ownerId, C context});
typedef AgentAuthenticate<C> =
    FutureOr<AgentIdentity<C>?> Function(RequestContext context);

/// A Dart Frog handler for streamed chat and owner-scoped history.
Handler chatHandler<C>({
  required AiAgent<C> agent,
  required AgentAuthenticate<C> authenticate,
  int maxRequestBytes = 1024 * 1024,
}) {
  if (maxRequestBytes < 1) throw ArgumentError.value(maxRequestBytes);
  return (context) async {
    final method = context.request.method;
    if (method != HttpMethod.get && method != HttpMethod.post) {
      return Response(statusCode: 405, headers: {'allow': 'GET, POST'});
    }
    final identity = await authenticate(context);
    if (identity == null || identity.ownerId.isEmpty) {
      return Response(statusCode: 401);
    }
    if (method == HttpMethod.get) {
      final query = context.request.uri.queryParameters;
      if (query['runId'] case final runId?) {
        final threadId = await agent.store.threadForRun(
          ownerId: identity.ownerId,
          runId: runId,
        );
        if (threadId == null) return Response(statusCode: 404);
        final offset = int.tryParse(query['offset'] ?? '-1');
        if (offset == null || offset < -1) return Response(statusCode: 400);
        return _sse(
          _replay(agent.store, identity.ownerId, threadId, runId, offset),
        );
      }
      final threadId = query['threadId'];
      if (threadId == null || threadId.isEmpty) {
        return Response(statusCode: 400);
      }
      final snapshot = chatHydration(
        await agent.store.load(ownerId: identity.ownerId, threadId: threadId),
      );
      final messages = List<Object?>.from(snapshot['messages'] as List);
      var end = messages.length;
      if (query['before'] case final before?) {
        end = messages.indexWhere((m) => (m as Map)['id'] == before);
        if (end < 0) return Response(statusCode: 400);
      }
      final limit = query['limit'] == null
          ? end
          : int.tryParse(query['limit']!);
      if (limit == null ||
          limit < 0 ||
          (query.containsKey('limit') && (limit < 1 || limit > 100))) {
        return Response(statusCode: 400);
      }
      final start = (end - limit).clamp(0, end);
      snapshot['messages'] = messages.sublist(start, end);
      snapshot['page'] = {
        'truncated': start > 0,
        if (start > 0) 'cursor': (messages[start] as Map)['id'],
      };
      return Response.json(body: snapshot);
    }
    final ChatRequest input;
    try {
      input = ChatRequest.fromJson(
        await _body(context.request, maxRequestBytes),
      );
    } on Object {
      return Response(statusCode: 400, body: 'Invalid chat request.');
    }
    return _sse(_chatEvents(agent, input, identity));
  };
}

/// A Dart Frog handler for a typed generation task.
Handler generationHandler<C, P, R>({
  required GenerationTask<P, R> task,
  required AgentAuthenticate<C> authenticate,
  required P Function(JsonObject, C) decode,
  int maxRequestBytes = 1024 * 1024,
}) {
  if (maxRequestBytes < 1) throw ArgumentError.value(maxRequestBytes);
  return (context) async {
    if (context.request.method != HttpMethod.post) {
      return Response(statusCode: 405, headers: {'allow': 'POST'});
    }
    final identity = await authenticate(context);
    if (identity == null || identity.ownerId.isEmpty) {
      return Response(statusCode: 401);
    }
    final P parameters;
    final String threadId;
    final String runId;
    try {
      final json = await _body(context.request, maxRequestBytes);
      threadId = json['threadId'] as String;
      runId = json['runId'] as String;
      ChatRequest(threadId: threadId, runId: runId);
      final payload = json['forwardedProps'];
      parameters = decode(
        payload is Map ? Map<String, Object?>.from(payload) : json,
        identity.context,
      );
    } on Object {
      return Response(statusCode: 400, body: 'Invalid generation request.');
    }
    return _sse(
      _generationEvents(task, parameters, threadId, runId, identity.ownerId),
    );
  };
}

Future<JsonObject> _body(Request request, int maxBytes) async {
  final bytes = <int>[];
  await for (final chunk in request.bytes()) {
    if (bytes.length + chunk.length > maxBytes) {
      throw const FormatException('Request too large.');
    }
    bytes.addAll(chunk);
  }
  return Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
}

Response _sse(Stream<AgentEvent> events) => Response.stream(
  body: events.map((event) => utf8.encode(event.toSse())),
  headers: {
    'content-type': 'text/event-stream',
    'cache-control': 'no-cache, no-transform',
    'x-accel-buffering': 'no',
  },
  bufferOutput: false,
);

Stream<AgentEvent> _chatEvents<C>(
  AiAgent<C> agent,
  ChatRequest input,
  AgentIdentity<C> identity,
) async* {
  try {
    yield* agent.run(
      input,
      ownerId: identity.ownerId,
      context: identity.context,
    );
  } on RunConflict {
    yield _error(
      input.threadId,
      input.runId,
      'RUN_CONFLICT',
      'The thread is busy or the run is stale.',
    );
  } catch (_) {
    yield _error(
      input.threadId,
      input.runId,
      'STREAM_FAILED',
      'The AI stream could not complete.',
    );
  }
}

Stream<AgentEvent> _generationEvents<P, R>(
  GenerationTask<P, R> task,
  P parameters,
  String threadId,
  String runId,
  String ownerId,
) async* {
  try {
    yield* task.run(
      parameters,
      threadId: threadId,
      runId: runId,
      ownerId: ownerId,
    );
  } catch (_) {
    yield _error(
      threadId,
      runId,
      'GENERATION_FAILED',
      'The generation could not complete.',
    );
  }
}

AgentEvent _error(String threadId, String runId, String code, String message) =>
    AgentEvent({
      'type': 'RUN_ERROR',
      'threadId': threadId,
      'runId': runId,
      'code': code,
      'message': message,
    });

Stream<AgentEvent> _replay(
  RunStore store,
  String ownerId,
  String threadId,
  String runId,
  int after,
) async* {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final events = await store.events(
      ownerId: ownerId,
      threadId: threadId,
      runId: runId,
      afterSequence: after,
    );
    for (final json in events) {
      after = json['sequence'] as int;
      yield AgentEvent(json);
      if (json['type'] == 'RUN_FINISHED' || json['type'] == 'RUN_ERROR') return;
    }
    final state = await store.load(ownerId: ownerId, threadId: threadId);
    if (state?['runId'] != runId || state?['status'] != 'running') {
      yield _error(
        threadId,
        runId,
        'RUN_NOT_ACTIVE',
        'The run is no longer active.',
      );
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  yield _error(
    threadId,
    runId,
    'REPLAY_TIMEOUT',
    'Reconnect to continue observing this run.',
  );
}
