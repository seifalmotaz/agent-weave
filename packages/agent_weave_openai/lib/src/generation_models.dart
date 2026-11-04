import 'dart:typed_data';
import 'package:agent_weave/agent_weave.dart';
import 'package:openai_dart/openai_dart.dart' as api;
import 'package:openai_dart/openai_dart_realtime.dart' as realtime;

/// Non-streaming image calls cannot currently abort in the underlying SDK.
/// Use [stream] when cancellation of an in-flight request is required.
final class OpenAIImageModel
    implements ImageModel<api.ImageGenerationRequest, api.ImageResponse> {
  final api.OpenAIClient client;
  const OpenAIImageModel(this.client);
  @override
  Future<api.ImageResponse> generate(
    api.ImageGenerationRequest request, {
    CancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final result = await client.images.generate(request);
    cancellation?.throwIfCancelled();
    return result;
  }

  Stream<api.ImageGenStreamEvent> stream(
    api.ImageGenerationRequest request, {
    CancellationToken? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    return client.images.generateStream(
      request,
      abortTrigger: cancellation?.whenCancelled,
    );
  }
}

final class OpenAISpeechModel
    implements SpeechModel<api.SpeechRequest, Uint8List> {
  final api.OpenAIClient client;
  const OpenAISpeechModel(this.client);
  @override
  Future<Uint8List> speak(
    api.SpeechRequest request, {
    CancellationToken? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    return client.audio.speech.create(
      request,
      abortTrigger: cancellation?.whenCancelled,
    );
  }

  Stream<Uint8List> stream(
    api.SpeechRequest request, {
    CancellationToken? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    return client.audio.speech.createByteStream(
      request,
      abortTrigger: cancellation?.whenCancelled,
    );
  }
}

final class OpenAITranscriptionModel
    implements
        TranscriptionModel<
          api.TranscriptionRequest,
          api.TranscriptionResponse
        > {
  final api.OpenAIClient client;
  const OpenAITranscriptionModel(this.client);
  @override
  Future<api.TranscriptionResponse> transcribe(
    api.TranscriptionRequest request, {
    CancellationToken? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    return client.audio.transcriptions.create(
      request,
      abortTrigger: cancellation?.whenCancelled,
    );
  }

  Stream<api.TranscriptionStreamEvent> stream(
    api.TranscriptionRequest request, {
    CancellationToken? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    return client.audio.transcriptions.createStream(
      request,
      abortTrigger: cancellation?.whenCancelled,
    );
  }
}

final class OpenAIEmbeddingModel
    implements EmbeddingModel<api.EmbeddingRequest, api.EmbeddingResponse> {
  final api.OpenAIClient client;
  const OpenAIEmbeddingModel(this.client);
  @override
  Future<api.EmbeddingResponse> embed(
    api.EmbeddingRequest request, {
    CancellationToken? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    return client.embeddings.create(
      request,
      abortTrigger: cancellation?.whenCancelled,
    );
  }
}

/// A server-to-server realtime session. The caller closes the returned session.
final class OpenAIRealtimeModel
    implements RealtimeModel<api.RealtimeConnection> {
  final api.OpenAIClient client;
  final String model;
  final realtime.RealtimeSessionCreateRequest? config;
  const OpenAIRealtimeModel({
    required this.client,
    required this.model,
    this.config,
  });
  @override
  Future<api.RealtimeConnection> connect({
    CancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final connection = await client.realtime.connect(
      model: model,
      config: config,
    );
    if (cancellation?.isCancelled ?? false) {
      await connection.close();
      throw const RunCancelled();
    }
    // Session lifetime belongs to its caller after connection establishment.
    return connection;
  }
}

final class OpenAIDecisionModel
    implements DecisionModel<api.DecisionRequest, api.DecisionResponse> {
  final api.OpenAIClient client;
  const OpenAIDecisionModel(this.client);
  @override
  Future<api.DecisionResponse> decide(
    api.DecisionRequest request, {
    CancellationToken? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    return client.decisions.create(
      request,
      abortTrigger: cancellation?.whenCancelled,
    );
  }
}

/// Video creation returns a provider job. Cancelling a local wait does not
/// cancel that job or its cost. Manage it explicitly through client.videos.
final class OpenAIVideoModel
    implements VideoModel<api.CreateVideoRequest, api.Video> {
  final api.OpenAIClient client;
  const OpenAIVideoModel(this.client);
  @override
  Future<api.Video> create(
    api.CreateVideoRequest request, {
    CancellationToken? cancellation,
  }) {
    cancellation?.throwIfCancelled();
    return client.videos.create(request);
  }
}
