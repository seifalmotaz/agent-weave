import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

Future<void> main() async {
  final key = Platform.environment['ANTHROPIC_API_KEY'];
  final modelId = Platform.environment['ANTHROPIC_MODEL'];
  if (key == null || key.isEmpty || modelId == null || modelId.isEmpty) {
    throw StateError('Set ANTHROPIC_API_KEY and ANTHROPIC_MODEL.');
  }
  final client = anthropic.AnthropicNativeClient.withApiKey(apiKey: key);
  try {
    final agent = AiAgent<void>(
      model: client.chatModel(
        authorityBindingId: 'example-anthropic-account',
        model: modelId,
        hostedTools: [
          anthropic.AnthropicHostedTool(
            const anthropic.WebSearchTool(maxUses: 3),
          ),
        ],
      ),
      maxSteps: 4,
      maxOutputTokens: 1024,
    );
    final result = await agent.generate(
      ChatRequest(
        threadId: 'research',
        runId: 'first',
        messages: [
          ChatMessage.user(
            'Find the latest stable Dart release.',
            id: 'question',
          ),
        ],
      ),
      ownerId: 'local-example',
      context: null,
    );
    print(result.text);
  } finally {
    client.close();
  }
}
