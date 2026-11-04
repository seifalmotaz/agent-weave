# OpenRouter dedicated Image API

Use `OpenRouterImageModel` for OpenRouter's dedicated `/images` endpoint. It accepts an image model and a prompt, and returns generated image bytes. `OpenRouterChatModel` uses the separate Chat Completions image workflow; its messages and replay are not interchangeable with this API.

The example below defaults to a buffered response. Set `OPENROUTER_IMAGE_STREAM=1` to request streaming. Each invocation can incur provider charges. Choose a model and options from discovery before running it.

```dart
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
```

Run from the workspace root with `OPENROUTER_API_KEY`, `OPENROUTER_IMAGE_MODEL`, and `OPENROUTER_IMAGE_PROMPT` set in your environment:

```sh
dart run examples/openrouter_image_api_demo.dart
```

The example reports sizes and does not write or render images. The separate offline fixture needs no key or network access: `dart run examples/review_cases/openrouter_image_api.dart`.

## Requests and discovery

`OpenRouterImageRequest` exposes `n`, reference images, resolution, aspect ratio, size, quality, background, output format and compression, seed, provider preferences, session ID, user, trace, and streaming. `extra` retains additional native request fields; `fromJson` and `toJson` support native JSON. Reference images use native `image_url` content parts. The request type checks their shape and nonempty URL string. Apply your own scheme, host and authorization policy before accepting untrusted reference URLs; the provider may fetch them. Model and provider capabilities vary: unsupported parameters can be ignored or rejected by the provider, and requesting multiple images does not guarantee a particular count.

Call `model.listModels()` for image models and `model.listModelEndpoints(author, slug)` for per-endpoint capabilities and pricing. The typed results expose capability descriptors, endpoint details and pricing, and preserve unknown fields in `raw`. Pass the author and slug as separate path segments; the client uses its configured API origin and does not follow URLs returned by discovery. The raw client also offers `listImageModels`, `listImageModelEndpoints`, and `createImages` for native JSON access. See [OpenRouter's Image API guide](https://openrouter.ai/docs/guides/overview/multimodal/image-generation) for model-specific availability and routing.

## Serve generation through Serverpod

Register `createOpenRouterImageRoute(client: client, model: yourImageModel)` on
`pod.webServer` at `/api/images`. Use your existing Serverpod authentication
handler. The example factory below accepts a prompt from `forwardedProps`, fixes
the model and count on the server, and saves the exact native result through
`ServerpodRunStore`. It rejects unauthenticated requests. The application owns
the provider client and closes it at shutdown.

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;
import 'package:agent_weave_serverpod/agent_weave_serverpod.dart';
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';

/// Register with pod.webServer.addRoute(route, '/api/images').
/// The application owns the client and closes it at shutdown.
AgentGenerationRoute<
  router.OpenRouterImageRequest,
  router.OpenRouterImageResponse
>
createOpenRouterImageRoute({
  required router.OpenRouterClient client,
  required String model,
}) {
  final image = router.OpenRouterImageModel(client: client);
  return AgentGenerationRoute(
    authenticate: (session) => session.authenticated?.userIdentifier,
    // Keep model, count and routing policy on the server.
    decode: (input) => router.OpenRouterImageRequest(
      model: model,
      prompt: input['prompt'] as String,
      n: 1,
    ),
    createTask: (session) => GenerationTask(
      store: ServerpodRunStore(session),
      execute: (request, context) => image.generate(
        request,
        cancellation: context.cancellation,
      ),
      encodeResult: (response) => response.raw,
    ),
  );
}
```

This source lives at
[`examples/serverpod/agent_weave_demo_server/lib/src/ai/openrouter_image_route.dart`](https://github.com/seifalmotaz/agent-weave/blob/main/examples/serverpod/agent_weave_demo_server/lib/src/ai/openrouter_image_route.dart).
The route emits AgentWeave generation events while the provider call is buffered;
it does not stream preview bytes. Use a generic generation client to receive the
native JSON result. Add your application's quota, output storage and retention
policy before exposing a billable endpoint.

The real PostgreSQL/network fixture in
`test/integration/openrouter_image_api_test.dart` also demonstrates an application
task consuming native partial events and retaining every completed event in
provider order. Its progress value stays at zero while receiving previews, since
the provider gives no completion percentage. Preview bytes are not stored as
final output. The task treats a native error event as failure and waits for stream
completion before saving its result. This is an application recipe, not automatic
Chat history or preview synchronization in either client.

## Streaming and results

`stream` emits events in provider order. `OpenRouterImagePartial` is a preview, with a partial sequence index; it is not a final image. `OpenRouterImageText` has a `phase`: `content` is renderable output, while `draft` and `reasoning` are intermediate; unknown phase strings are preserved. `OpenRouterImageCompleted` carries a final image. There may be multiple completed events, and the API does not supply an output index that associates them with previews. Handle each event without inventing that association.

Some providers return buffered JSON even when streaming is requested. The client detects the response content type from the **same HTTP request** and emits `OpenRouterImageBuffered` with the response; it does not repeat the generation request. The client accepts both the direct event shape in OpenRouter's guide and the `data` wrapper in its pinned OpenAPI schema. The native `streamImages` method exposes the underlying JSON/SSE events. A typed `OpenRouterImageError` is a failure event: callers must handle it explicitly. Invalid events, an incomplete stream, or an absent completion sentinel fail the stream. Bytes after the `[DONE]` sentinel are not read.

Images provide `bytes`, `b64Json`, and a nullable `mediaType`. The API may omit the media type; the client does not infer one or fabricate image IDs or a model ID. Usage and cost are available when reported by the provider. Treat output as untrusted: in particular, an SVG is data and should not be executed as HTML. The examples do not fetch returned URLs or render SVG.

## Cancellation and resource limits

Pass a `CancellationToken` to `generate`, `stream`, or discovery. The client also accepts a credential resolver for token refresh; cancellation can stop waiting for a pending resolver. Cancellation or a transport error after dispatch does not prove that the provider stopped processing, so check provider records before retrying an uncertain, billable request. The client does not automatically repeat the image POST for a fallback.

Base64 and decoded image bytes consume memory. Set application-appropriate request, response, storage, and retention limits, particularly when requesting multiple or large images; the typed adapter does not impose an image-size cap. Store credentials and generated content according to your application's privacy requirements. Dispose the client with `close()` when finished; a client constructed with a borrowed transport leaves that transport open.
