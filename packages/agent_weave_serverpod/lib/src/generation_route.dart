import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:agent_weave/agent_weave.dart';
import 'package:serverpod/serverpod.dart';
import 'chat_route.dart';

/// A typed generation endpoint emitting the standard TanStack result protocol.
final class AgentGenerationRoute<P, R> extends Route {
  final AgentAuthentication authenticate;
  final P Function(JsonObject input) decode;
  final FutureOr<GenerationTask<P, R>> Function(Session session) createTask;
  final int maxRequestBytes;
  AgentGenerationRoute({
    required this.authenticate,
    required this.decode,
    required this.createTask,
    this.maxRequestBytes = 1024 * 1024,
  }) : super(methods: {Method.post}) {
    if (maxRequestBytes < 1) throw ArgumentError.value(maxRequestBytes);
  }

  @override
  Future<Result> handleCall(Session session, Request request) async {
    final owner = await authenticate(session);
    if (owner == null || owner.isEmpty) return Response.unauthorized();
    final P parameters;
    final String threadId;
    final String runId;
    try {
      final json = Map<String, Object?>.from(
        jsonDecode(await request.readAsString(maxLength: maxRequestBytes))
            as Map,
      );
      threadId = json['threadId'] as String;
      runId = json['runId'] as String;
      ChatRequest(threadId: threadId, runId: runId);
      final payload = json['forwardedProps'];
      parameters = decode(
        payload is Map ? Map<String, Object?>.from(payload) : json,
      );
    } catch (_) {
      return Response.badRequest(
        body: Body.fromString('Invalid generation request.'),
      );
    }
    return Response.ok(
      headers: Headers.fromMap({
        'Cache-Control': ['no-cache, no-transform'],
        'X-Accel-Buffering': ['no'],
      }),
      body: Body.fromDataStream(
        _stream(session, parameters, threadId, runId, owner),
        mimeType: const MimeType('text', 'event-stream'),
      ),
    );
  }

  Stream<Uint8List> _stream(
    Session original,
    P parameters,
    String threadId,
    String runId,
    String ownerId,
  ) async* {
    final session = await original.serverpod.createSession();
    session.updateAuthenticated(original.authenticated);
    try {
      final task = await createTask(session);
      await for (final event in task.run(
        parameters,
        threadId: threadId,
        runId: runId,
        ownerId: ownerId,
      )) {
        yield Uint8List.fromList(utf8.encode(event.toSse()));
      }
    } catch (_) {
      yield Uint8List.fromList(
        utf8.encode(
          AgentEvent({
            'type': 'RUN_ERROR',
            'threadId': threadId,
            'runId': runId,
            'code': 'GENERATION_FAILED',
            'message': 'The generation could not complete.',
          }).toSse(),
        ),
      );
    } finally {
      await session.close();
    }
  }
}
