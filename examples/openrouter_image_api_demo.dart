import 'dart:io';

import 'package:agent_weave_openrouter/agent_weave_openrouter.dart';

Future<void> main() async {
  final key = Platform.environment['OPENROUTER_API_KEY'];
  final modelId = Platform.environment['OPENROUTER_IMAGE_MODEL'];
  final prompt = Platform.environment['OPENROUTER_IMAGE_PROMPT'];
  if (key == null || modelId == null || prompt == null) {
    throw StateError(
      'Set OPENROUTER_API_KEY, OPENROUTER_IMAGE_MODEL, and OPENROUTER_IMAGE_PROMPT.',
    );
  }

  final client = OpenRouterClient.withApiKey(apiKey: key);
  final model = OpenRouterImageModel(client: client);
  final request = OpenRouterImageRequest(model: modelId, prompt: prompt);
  try {
    if (Platform.environment['OPENROUTER_IMAGE_STREAM'] == '1') {
      await for (final event in model.stream(request)) {
        switch (event) {
          case OpenRouterImagePartial():
            print(
              'Partial image ${event.index}: ${event.image.bytes.length} bytes',
            );
          case OpenRouterImageText():
            print('Text chunk phase: ${event.phase}');
          case OpenRouterImageCompleted():
            print(
              'Final image: ${event.image.bytes.length} bytes; '
              'media type: ${event.image.mediaType ?? 'unknown'}',
            );
          case OpenRouterImageBuffered():
            for (final image in event.response.data) {
              print(
                'Final image: ${image.bytes.length} bytes; '
                'media type: ${image.mediaType ?? 'unknown'}',
              );
            }
          case OpenRouterImageError():
            throw StateError(
              'Image generation failed; inspect the error event safely.',
            );
        }
      }
    } else {
      final response = await model.generate(request);
      for (final image in response.data) {
        print(
          'Final image: ${image.bytes.length} bytes; '
          'media type: ${image.mediaType ?? 'unknown'}',
        );
      }
    }
  } finally {
    client.close();
  }
}
