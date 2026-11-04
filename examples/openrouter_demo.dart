import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;

Future<void> main() async {
  final apiKey = Platform.environment['OPENROUTER_API_KEY'];
  final modelId = Platform.environment['OPENROUTER_MODEL'];
  if (apiKey == null || modelId == null) {
    throw StateError('Set OPENROUTER_API_KEY and OPENROUTER_MODEL.');
  }
  final client = router.OpenRouterClient.withApiKey(
    apiKey: apiKey,
    appName: 'My app',
    headers: {'X-OpenRouter-Metadata': 'enabled'},
  );
  try {
    final model = router.OpenRouterChatModel(
      client: client,
      model: modelId,
      options: router.OpenRouterChatOptions(
        provider: router.OpenRouterProviderPreferences(requireParameters: true),
      ),
    );
    final result = await generateText(model: model, prompt: 'Say hello.');
    print(result.text);
  } finally {
    client.close();
  }
}
