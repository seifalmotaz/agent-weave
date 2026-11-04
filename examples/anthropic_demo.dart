import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

Future<void> main() async {
  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
  final modelId = Platform.environment['ANTHROPIC_MODEL'];
  if (apiKey == null || apiKey.isEmpty || modelId == null || modelId.isEmpty) {
    throw StateError('Set ANTHROPIC_API_KEY and ANTHROPIC_MODEL.');
  }
  final client = anthropic.AnthropicNativeClient.withApiKey(
    apiKey: apiKey,
    apiVersion: Platform.environment['ANTHROPIC_VERSION'] ?? '2023-06-01',
  );
  try {
    final model = client.chatModel(
      model: modelId,
      configure: (body) => {
        ...body,
        'thinking': {'type': 'adaptive'},
        'cache_control': {'type': 'ephemeral'},
      },
    );
    final result = await generateObject<String>(
      model: model,
      prompt: 'Give one concise title for a guide to growing herbs indoors.',
      schema: const {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
        },
        'required': ['title'],
        'additionalProperties': false,
      },
      decode: (json) => (json as Map<String, Object?>)['title'] as String,
    );
    print(result.value);
  } finally {
    client.close();
  }
}
