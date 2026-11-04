import 'package:agent_weave/agent_weave.dart';

Future<void> main() async {
  final agent = AiAgent<void>(model: const OfflineModel());
  await for (final event in agent.run(
    ChatRequest(
      threadId: 'demo',
      runId: 'first',
      messages: [ChatMessage.user('Hello', id: 'user-1')],
    ),
    ownerId: 'local-user',
    context: null,
  )) {
    if (event.type == 'TEXT_MESSAGE_CONTENT') print(event.json['delta']);
  }
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
    yield const TextDelta('Hello from AgentWeave. No API key needed.');
    yield const ModelFinished();
  }
}
