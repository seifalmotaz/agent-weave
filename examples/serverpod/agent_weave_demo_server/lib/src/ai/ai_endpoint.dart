import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_serverpod/agent_weave_serverpod.dart';
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:serverpod/serverpod.dart';
import 'agent_factory.dart';

/// Native Serverpod streaming, usable through the generated Dart client.
class AiEndpoint extends Endpoint {
  @override
  bool get requireLogin => true;

  Stream<String> chat(Session session, String requestJson) {
    final input = ChatRequest.fromJson(
      Map<String, Object?>.from(jsonDecode(requestJson) as Map),
    );
    return streamAgent(
      createAgent(session),
      input,
      ownerId: session.authenticated!.userIdentifier,
      context: session,
    );
  }

  Future<String> history(Session session, String threadId) async => jsonEncode(
    chatHydration(
      await ServerpodRunStore(session).load(
        ownerId: session.authenticated!.userIdentifier,
        threadId: threadId,
      ),
    ),
  );
}
