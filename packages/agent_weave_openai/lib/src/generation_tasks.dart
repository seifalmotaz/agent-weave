import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:openai_dart/openai_dart.dart' as api;
import 'package:uuid/uuid.dart';
import 'generation_models.dart';

/// Normalizes provider output to the TanStack image generation result contract.
GenerationTask<api.ImageGenerationRequest, ImageGeneration> imageTask(
  api.OpenAIClient client,
) => GenerationTask(
  execute: (request, context) async {
    final response = await OpenAIImageModel(
      client,
    ).generate(request, cancellation: context.cancellation);
    return ImageGeneration(
      id: const Uuid().v4(),
      model: request.model,
      images: [
        for (final image in response.data)
          if (image.url case final url?)
            ImageUrl(url)
          else if (image.b64Json case final data?)
            ImageBase64(data)
          else
            throw const FormatException('OpenAI returned no image source.'),
      ],
    );
  },
  encodeResult: (result) => result.toJson(),
);

GenerationTask<api.SpeechRequest, SpeechGeneration> speechTask(
  api.OpenAIClient client,
) => GenerationTask(
  execute: (request, context) async {
    final bytes = await OpenAISpeechModel(
      client,
    ).speak(request, cancellation: context.cancellation);
    return SpeechGeneration(
      id: const Uuid().v4(),
      model: request.model,
      audio: base64Encode(bytes),
      format: request.responseFormat?.toJson() ?? 'mp3',
    );
  },
  encodeResult: (result) => result.toJson(),
);

GenerationTask<api.TranscriptionRequest, Transcription> transcriptionTask(
  api.OpenAIClient client,
) => GenerationTask(
  execute: (request, context) async {
    final result = await OpenAITranscriptionModel(
      client,
    ).transcribe(request, cancellation: context.cancellation);
    return Transcription(
      id: const Uuid().v4(),
      model: request.model,
      text: result.text,
    );
  },
  encodeResult: (result) => result.toJson(),
);
