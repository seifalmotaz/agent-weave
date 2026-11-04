part of '../agent_weave_openrouter.dart';

/// Typed access to OpenRouter's dedicated Image API.
final class OpenRouterImageModel
    implements ImageModel<OpenRouterImageRequest, OpenRouterImageResponse> {
  final OpenRouterClient client;
  const OpenRouterImageModel({required this.client});

  @override
  Future<OpenRouterImageResponse> generate(
    OpenRouterImageRequest request, {
    CancellationToken? cancellation,
  }) async {
    if (request.toJson()['stream'] == true) {
      throw ArgumentError('Use stream for streamed image generation.');
    }
    final response = await client.createImages(
      request.toJson(),
      cancellation: cancellation,
    );
    return OpenRouterImageResponse.fromJson(response.data);
  }

  /// Emits provider events in order, including an explicit buffered fallback.
  Stream<OpenRouterImageStreamEvent> stream(
    OpenRouterImageRequest request, {
    CancellationToken? cancellation,
  }) async* {
    await for (final event in client.streamImages(
      request.toJson(),
      cancellation: cancellation,
    )) {
      if (event is JsonBufferedData) {
        yield OpenRouterImageBuffered(
          OpenRouterImageResponse.fromJson(event.data),
        );
      } else if (event is JsonSseData) {
        yield OpenRouterImageStreamEvent.fromJson(
          event.data.containsKey('type')
              ? event.data
              : event.data['data'] as JsonObject,
        );
      }
    }
  }

  Future<OpenRouterImageModels> listModels({
    CancellationToken? cancellation,
  }) async => OpenRouterImageModels.fromJson(
    (await client.listImageModels(cancellation: cancellation)).data,
  );

  Future<OpenRouterImageModelEndpoints> listModelEndpoints(
    String author,
    String slug, {
    CancellationToken? cancellation,
  }) async => OpenRouterImageModelEndpoints.fromJson(
    (await client.listImageModelEndpoints(
      author,
      slug,
      cancellation: cancellation,
    )).data,
  );
}
