import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:agent_weave/agent_weave.dart';
import 'package:serverpod/serverpod.dart';

typedef AgentFactory<C> = FutureOr<AiAgent<C>> Function(Session session);
typedef AgentAuthentication = FutureOr<String?> Function(Session session);
typedef AgentContextFactory<C> = FutureOr<C> Function(Session session);

/// Standard TanStack SSE transport on Serverpod's web server.
///
/// Each response owns a dedicated session until its stream closes. Serverpod's
/// request session is closed before a streaming HTTP body is consumed.
final class AgentChatRoute<C> extends Route {
  final AgentFactory<C> createAgent;
  final AgentAuthentication authenticate;
  final AgentContextFactory<C> createContext;
  final int maxRequestBytes;
  AgentChatRoute({
    required this.createAgent,
    required this.authenticate,
    required this.createContext,
    this.maxRequestBytes = 1024 * 1024,
  }) : super(methods: {Method.post, Method.get}) {
    if (maxRequestBytes < 1) throw ArgumentError.value(maxRequestBytes);
  }

  @override
  Future<Result> handleCall(Session session, Request request) async {
    final ownerId = await authenticate(session);
    if (ownerId == null || ownerId.isEmpty) return Response.unauthorized();
    if (request.method == Method.get) return _get(session, request, ownerId);
    final ChatRequest input;
    try {
      final body = await request.readAsString(maxLength: maxRequestBytes);
      input = ChatRequest.fromJson(
        Map<String, Object?>.from(jsonDecode(body) as Map),
      );
    } on Object {
      return Response.badRequest(
        body: Body.fromString('Invalid chat request.'),
      );
    }
    final stream = _stream(session, ownerId, input);
    return Response.ok(
      headers: Headers.fromMap({
        'Cache-Control': ['no-cache, no-transform'],
        'X-Accel-Buffering': ['no'],
      }),
      body: Body.fromDataStream(
        stream,
        mimeType: const MimeType('text', 'event-stream'),
      ),
    );
  }

  Future<Result> _get(Session session, Request request, String ownerId) async {
    final query = request.url.queryParameters;
    final agent = await createAgent(session);
    if (query['runId'] case final runId?) {
      final threadId = await agent.store.threadForRun(
        ownerId: ownerId,
        runId: runId,
      );
      if (threadId == null) return Response.notFound();
      final after = int.tryParse(query['offset'] ?? '-1');
      if (after == null || after < -1) return Response.badRequest();
      return Response.ok(
        body: Body.fromDataStream(
          _replay(session, ownerId, threadId, runId, after),
          mimeType: const MimeType('text', 'event-stream'),
        ),
      );
    }
    final threadId = query['threadId'];
    if (threadId == null || threadId.isEmpty) return Response.badRequest();
    final snapshot = chatHydration(
      await agent.store.load(ownerId: ownerId, threadId: threadId),
    );
    final messages = List<Object?>.from(snapshot['messages'] as List);
    var end = messages.length;
    if (query['before'] case final before?) {
      end = messages.indexWhere((m) => (m as Map)['id'] == before);
      if (end < 0) return Response.badRequest();
    }
    final limit = query['limit'] == null ? end : int.tryParse(query['limit']!);
    if (limit == null ||
        limit < 0 ||
        (query['limit'] != null && (limit < 1 || limit > 100))) {
      return Response.badRequest();
    }
    final start = (end - limit).clamp(0, end);
    snapshot['messages'] = messages.sublist(start, end);
    snapshot['page'] = {
      'truncated': start > 0,
      if (start > 0) 'cursor': (messages[start] as Map)['id'],
    };
    return Response.ok(
      body: Body.fromString(jsonEncode(snapshot), mimeType: MimeType.json),
    );
  }

  Stream<Uint8List> _replay(
    Session original,
    String ownerId,
    String threadId,
    String runId,
    int after,
  ) async* {
    final session = await original.serverpod.createSession();
    session.updateAuthenticated(original.authenticated);
    try {
      final agent = await createAgent(session);
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        final events = await agent.store.events(
          ownerId: ownerId,
          threadId: threadId,
          runId: runId,
          afterSequence: after,
        );
        for (final json in events) {
          after = json['sequence'] as int;
          yield Uint8List.fromList(utf8.encode(AgentEvent(json).toSse()));
          if (json['type'] == 'RUN_FINISHED' || json['type'] == 'RUN_ERROR') {
            return;
          }
        }
        final current = await agent.store.load(
          ownerId: ownerId,
          threadId: threadId,
        );
        if (current?['runId'] != runId || current?['status'] != 'running') {
          // A cancelled run has no normal terminal event to replay.
          yield Uint8List.fromList(
            utf8.encode(
              AgentEvent({
                'type': 'RUN_ERROR',
                'threadId': threadId,
                'runId': runId,
                'code': 'RUN_NOT_ACTIVE',
                'message': 'The run is no longer active.',
              }).toSse(),
            ),
          );
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      yield Uint8List.fromList(
        utf8.encode(
          AgentEvent({
            'type': 'RUN_ERROR',
            'threadId': threadId,
            'runId': runId,
            'code': 'REPLAY_TIMEOUT',
            'message': 'Reconnect to continue observing this run.',
          }).toSse(),
        ),
      );
    } finally {
      await session.close();
    }
  }

  Stream<Uint8List> _stream(
    Session requestSession,
    String ownerId,
    ChatRequest input,
  ) async* {
    final session = await requestSession.serverpod.createSession();
    session.updateAuthenticated(requestSession.authenticated);
    try {
      final agent = await createAgent(session);
      final context = await createContext(session);
      await for (final event in agent.run(
        input,
        ownerId: ownerId,
        context: context,
      )) {
        yield Uint8List.fromList(utf8.encode(event.toSse()));
      }
    } on RunConflict {
      yield Uint8List.fromList(
        utf8.encode(
          AgentEvent({
            'type': 'RUN_ERROR',
            'threadId': input.threadId,
            'runId': input.runId,
            'code': 'RUN_CONFLICT',
            'message': 'The thread is busy or the run is stale.',
          }).toSse(),
        ),
      );
    } catch (_) {
      session.log('AgentWeave streaming failed.', level: LogLevel.error);
      yield Uint8List.fromList(
        utf8.encode(
          AgentEvent({
            'type': 'RUN_ERROR',
            'threadId': input.threadId,
            'runId': input.runId,
            'code': 'STREAM_FAILED',
            'message': 'The AI stream could not complete.',
          }).toSse(),
        ),
      );
    } finally {
      await session.close();
    }
  }
}

/// Use inside a generated Serverpod endpoint that returns `Stream<String>`.
Stream<String> streamAgent<C>(
  AiAgent<C> agent,
  ChatRequest request, {
  required String ownerId,
  required C context,
  CancellationToken? cancellation,
}) => agent
    .run(
      request,
      ownerId: ownerId,
      context: context,
      cancellation: cancellation,
    )
    .map((event) => jsonEncode(event.json));
