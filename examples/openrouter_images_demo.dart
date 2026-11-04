import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;

Future<void> main() async {
  final key = Platform.environment['OPENROUTER_API_KEY'];
  final modelId = Platform.environment['OPENROUTER_IMAGE_CHAT_MODEL'];
  if (key == null || modelId == null) {
    throw StateError('Set OPENROUTER_API_KEY and OPENROUTER_IMAGE_CHAT_MODEL.');
  }
  final client = router.OpenRouterClient.withApiKey(apiKey: key);
  try {
    final result = await generateText(
      model: router.OpenRouterChatModel(
        client: client,
        model: modelId,
        options: router.OpenRouterChatOptions(
          modalities: [
            router.OpenRouterOutputModality.text,
            router.OpenRouterOutputModality.image,
          ],
          imageConfig: {'aspect_ratio': '1:1'},
        ),
      ),
      prompt: 'Draw a small red sailboat and describe it briefly.',
    );
    print(result.text);
    print('Generated ${result.images.length} images.');
    for (final image in result.images) {
      // Pass image.url to your renderer or application-owned artifact store.
      print('Image reference has ${image.url.length} characters.');
    }
  } finally {
    client.close();
  }
}
