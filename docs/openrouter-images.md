# Images from OpenRouter Chat

Request image output through `OpenRouterChatOptions.modalities`. The normalized
agent supports text and image output. Its typed enum also represents audio for
native requests, but the agent rejects audio before sending a request because
it does not implement that output lifecycle.

Select a model and provider that support image output through Chat Completions.
Availability and accepted configuration vary; this guide does not recommend a
particular model. Use the [dedicated Image API guide](openrouter-image-api.md) for the separate
`/images` workflow; its results are independent of Chat history and replay.

## Generate images from Dart

Set `OPENROUTER_API_KEY` and `OPENROUTER_IMAGE_CHAT_MODEL` on the backend. Running
this example makes a billable request. The repository analyzes and compiles it
without execution.

```dart
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
```

The complete program is also in
[`examples/openrouter_images_demo.dart`](https://github.com/seifalmotaz/agent-weave/blob/main/examples/openrouter_images_demo.dart).
Use the same model in an `AiAgent` behind an authenticated Serverpod endpoint;
the runtime owns tools, approvals and history.

`result.images` contains images produced by assistant messages in this run,
including intermediate tool steps. It excludes user image inputs and previous
runs. `result.messages` includes the complete stored history and private replay;
use `chatHydration` to return public history to a client.

## Completed Chat messages, not image stream fragments

Ordinary text Chat requests use SSE. Requesting an image modality sends
`stream: false` and reads a completed native Chat response. The pinned Chat
schema defines `assistant.images`; its streaming delta does not define image
fragments, image IDs or image indexes. The adapter rejects image-bearing SSE
deltas rather than silently dropping them or guessing how to assemble them.

For a string `content` and separate `images` array, the public result places
text before the images, retaining image-array order. The schema does not define
cross-order between these two fields. If `content` itself is an array of text
and image parts, its explicit order is retained, followed by the separate
`images` array. No image deduplication or index inference is performed.

Image references may be absolute HTTP(S) URLs without credentials or nonempty
base64 image data URLs. Other URI forms are rejected by this adapter. Remote
images are not downloaded; data URLs are checked for valid base64 but are not
raster-decoded. Your application owns rendering, storage limits, expired URLs
and any artifact hosting.

## Native configuration and safe continuation

`imageConfig` snapshots model-specific JSON without inventing universal sizes
or aspect ratios. Native unknown fields remain intact. The provider validates
its accepted configuration; a JSON map is not compile-time validation of every
model option. `extra` cannot replace runtime-owned history, tools, schema,
token bounds, streaming or modality selection.

The existing typed `configure` callback still protects runtime fields. It can
set provider parameters such as temperature. It cannot replace a supplied
schema or instructions or advertise an unregistered function.

Image continuation is stored privately under `openrouter.chat.images`. It
retains the original content, refusal and image payloads, including opaque
fields on images. Restoring history checks that this payload matches the
assistant's public content; it cannot replace roles or tool calls. Function
calls, reasoning and metadata retain their existing separate handling.

Mixed image/function responses pause for normal approvals. Images are stored
before the pause, and a recreated agent replays them with the selected function
result after approval. Invalid images, mismatched replay and error or filtered
tool-call finishes do not release a local call. Buffered JSON error envelopes
retain redacted diagnostics and request IDs.

## Contract and verification

The [OpenRouter API inventory](openrouter-api-reference.md) follows the pinned
[official OpenAPI](https://openrouter.ai/openapi.json). The current
[image-generation guide](https://openrouter.ai/docs/guides/overview/multimodal/image-generation)
describes the dedicated Image API. Its partial-image event types and parameter
limits do not establish Chat behavior.

Local tests cover completed messages, content-array ordering, multiple data and
HTTP(S) image references, exact private replay, ownership guards, configuration,
errors, cancellation and approval recreation. The independent consumer scores
this selected path 8/10. No live model, billing or device rendering was tested.
See [validation](validation.md) for the exact evidence and open work.
