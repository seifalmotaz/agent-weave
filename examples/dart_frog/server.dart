import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_dart_frog/agent_weave_dart_frog.dart';
import 'package:dart_frog/dart_frog.dart';

Future<void> main() async {
  final token = Platform.environment['DEMO_TOKEN'];
  if (token == null || token.isEmpty) {
    stderr.writeln('Set DEMO_TOKEN to run this local demonstration.');
    exitCode = 1;
    return;
  }
  final handler = chatHandler<void>(
    agent: AiAgent<void>(model: const OfflineModel()),
    authenticate: (context) =>
        context.request.headers['authorization'] == 'Bearer $token'
        ? (ownerId: 'demo-user', context: null)
        : null,
  );
  final server = await serve(handler, InternetAddress.loopbackIPv4, 8080);
  print('Demo listening at http://${server.address.address}:${server.port}');
}

final class OfflineModel implements ChatModel {
  const OfflineModel();
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    yield const TextDelta('Hello from the offline Dart Frog example.');
    yield const ModelFinished();
  }
}
