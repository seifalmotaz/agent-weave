import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

Future<void> main() async {
  final key = Platform.environment['OPENAI_API_KEY'];
  final modelId = Platform.environment['OPENAI_MODEL'];
  if (key == null || key.isEmpty || modelId == null || modelId.isEmpty) {
    throw StateError('Set OPENAI_API_KEY and OPENAI_MODEL.');
  }
  final client = openai.OpenAIClient.withApiKey(key);
  try {
    final result = await generateText(
      model: openai.OpenAIResponsesModel.native(
        client: client,
        model: modelId,
        hostedTools: [
          openai.OpenAIHostedTool.fromJson({
            'type': 'web_search',
            'user_location': {
              'type': 'approximate',
              'city': 'Cairo',
              'country': 'EG',
            },
          }),
        ],
        configure: (body) => {...body, 'tool_choice': 'auto'},
      ),
      prompt: 'Find the latest stable Dart release.',
      maxOutputTokens: 1024,
    );
    print(result.text);
  } finally {
    client.close();
  }
}
