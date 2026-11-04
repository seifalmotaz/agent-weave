import 'dart:io';
import 'package:agent_weave_demo_client/agent_weave_demo_client.dart'
    as backend;
import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:serverpod_client/serverpod_client.dart' as transport;
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart';

/// Run against the backend started with AGENT_WEAVE_DEMO_MODE=true.
Future<void> main() async {
  final client = backend.Client('http://localhost:8080/')
    ..authKeyProvider = const LocalDemoAuth();
  final chat = ChatClient(
    threadId: 'native-demo-${DateTime.now().microsecondsSinceEpoch}',
    connection: serverpodConnection(send: client.ai.chat),
  );
  final subscription = chat.states.listen((state) {
    if (state.messages.isNotEmpty) stdout.writeln(state.messages.last.answer);
  });
  try {
    await chat.sendText('Hello from the native Dart client');
    if (chat.error != null) throw StateError(chat.error!);
  } finally {
    await subscription.cancel();
    await chat.dispose();
    client.close();
  }
}

final class LocalDemoAuth implements transport.ClientAuthKeyProvider {
  const LocalDemoAuth();
  @override
  Future<String> get authHeaderValue async => 'Bearer agent-weave-local-demo';
}
