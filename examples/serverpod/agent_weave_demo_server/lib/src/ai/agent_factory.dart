import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:serverpod/serverpod.dart';

final openai.OpenAIClient? _openai =
    Platform.environment['AGENT_WEAVE_USE_OPENAI'] == 'true'
    ? openai.OpenAIClient.fromEnvironment()
    : null;

AiAgent<Session> createAgent(Session session) => AiAgent(
  model: _openai == null || session.serverpod.runMode == ServerpodRunMode.test
      ? const DemoModel()
      : openai.OpenAIResponsesModel(
          client: _openai!,
          model: Platform.environment['OPENAI_MODEL'] ?? 'gpt-5.4-nano',
        ),
  store: ServerpodRunStore(session),
  instructions: 'You are a helpful assistant. Be concise.',
  tools: [
    Tool<String, String, Session>(
      name: 'greet',
      description: 'Greet a person by name',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
        'required': ['name'],
        'additionalProperties': false,
      },
      outputSchema: const {'type': 'string'},
      decode: (input) => input['name'] as String,
      encode: (result) => result,
      execute: (name, context) => 'Hello $name',
    ),
  ],
);

/// Offline example. No provider key or billable requests required.
final class DemoModel implements ChatModel {
  const DemoModel();
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(tools: true);
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    yield TextDelta('AgentWeave received: ${request.messages.last.text}');
    yield const ModelFinished();
  }
}
