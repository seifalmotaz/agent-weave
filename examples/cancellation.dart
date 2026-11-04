import 'dart:async';

import 'package:agent_weave/agent_weave.dart';

/// An offline provider that waits for its invocation's cancellation signal.
final class WaitingModel implements ChatModel {
  final started = Completer<void>();
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();

  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    yield const TextDelta('Working on the answer...');
    started.complete();
    await cancellation.whenCancelled;
    cancellation.throwIfCancelled();
  }
}

Future<void> main() async {
  final model = WaitingModel();
  final token = CancellationToken();
  final agent = AiAgent<void>(model: model);
  final work = agent.generate(
    ChatRequest(
      threadId: 'cancellation',
      runId: 'run',
      messages: [ChatMessage.user('Start a slow answer', id: 'question')],
    ),
    ownerId: 'demo-user',
    context: null,
    cancellation: token,
  );
  await model.started.future;
  token.cancel(); // In an application, call this from its cancellation action.
  try {
    await work;
    throw StateError('The cancelled operation unexpectedly completed.');
  } on RunCancelled {
    final saved = await agent.store.load(
      ownerId: 'demo-user',
      threadId: 'cancellation',
    );
    if (saved?['status'] != 'cancelled') {
      throw StateError('The cancelled run did not retain its checkpoint.');
    }
    print('Run cancelled; retained ${saved?['status']} history.');
  }
}
