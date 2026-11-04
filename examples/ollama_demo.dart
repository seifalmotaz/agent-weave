import 'dart:io';

import 'package:agent_weave/agent_weave.dart' as weave;
import 'package:agent_weave_ollama/agent_weave_ollama.dart' as ollama;

Future<void> main() async {
  final modelId = Platform.environment['OLLAMA_MODEL'];
  if (modelId == null || modelId.isEmpty) {
    stderr.writeln(
      'Set OLLAMA_MODEL to an installed model that supports JSON schema.',
    );
    exitCode = 64;
    return;
  }
  final client = ollama.OllamaNativeClient(
    baseUrl:
        Platform.environment['OLLAMA_BASE_URL'] ?? 'http://localhost:11434',
  );
  try {
    final model = client.chatModel(
      model: modelId,
      options: const ollama.ModelOptions(temperature: 0.2),
    );
    final result = await weave.generateObject<String>(
      model: model,
      prompt: 'Give a short name for a friendly robot.',
      schema: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
        },
        'required': ['name'],
        'additionalProperties': false,
      },
      decode: (json) => (json as Map<String, Object?>)['name'] as String,
    );
    print(result.value);
  } finally {
    client.close();
  }
}
