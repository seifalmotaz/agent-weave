# Ollama

Connect AgentWeave to an existing Ollama server and an installed model. Install `agent_weave`, `agent_weave_ollama`, and their dependencies in your Dart project. Set `OLLAMA_MODEL` to an installed model that supports JSON Schema; optionally set `OLLAMA_BASE_URL` (defaults to `http://localhost:11434`). Then run `dart run examples/ollama_demo.dart` from this repository.

```dart
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
```

This client talks to an Ollama HTTP server; it does not run inference inside the Dart or Flutter app. On a phone, `localhost` means the phone itself, so configure a reachable server URL. Device networking and model capabilities vary and have not been verified here.

`OllamaChatModel` supports AgentWeave function tools and structured output, subject to the model's capabilities. AgentWeave validates tool arguments and applies configured approval rules before execution. Assistant thinking and native tool calls are preserved for continuation in private provider data. Ollama may return native call IDs; AgentWeave generates separate local IDs and binds tool results to the original call. When the native ID is absent, replay uses the tool name without inventing an ID on the wire. Private replay, raw frames, response metadata and logprobs can contain sensitive information; do not expose them to end users or logs.

In the pinned Ollama server, its generic parser and reviewed built-in parsers allocate increasing call indices across a response. This is not guaranteed for remote or older servers. AgentWeave accepts repeated identical indexed calls once and rejects conflicting repeats rather than guessing how to merge them. Use `streamChat` directly for protocols that need different handling.

For images, use an AgentWeave `ImagePart` containing an inline `data:image/...;base64,...` URL. Remote image URLs are not fetched. Files, audio, video and native provider-specific tool kinds are unsupported in normalized chat. The native API remains available when the model or server needs a different request shape.

The package re-exports `ollama_dart` 4.0.0 types for typed options, including `ModelOptions`, `ThinkValue`, `KeepAlive` and `EmbedRequest`. The example leaves thinking and keep-alive at server defaults. When supported by your model and desired, pass `think: const ollama.ThinkValue.enabled(true)` or `keepAlive: const ollama.KeepAlive.duration('5m')` to `client.chatModel`. Model options remain model-dependent. `maxOutputTokens` owns `options.num_predict`; `configure` cannot replace runtime-owned model, messages, tools, stream, output schema or output limit.

To embed with an installed embedding-capable model, use `OllamaEmbeddingModel(client).embed(ollama.EmbedRequest(model: embeddingModelId, input: ollama.EmbedInput.list(['first', 'second'])))`. Its result exposes immutable vectors, the raw response, the reported model and input token count. Do not assume every chat model supports embeddings.

For native JSON, use `createChat`, `createGenerate`, `embed`, `show`, or `send`; `streamChat` and `streamGenerate` expose NDJSON frames. The native client accepts a `CancellationToken` and cancels its request on cancellation or stream unsubscribe; these guarantees belong to AgentWeave's transport, not the re-exported SDK. It does not retry, pull or download models. For protected servers, supply an optional `credentialResolver` on the backend; it is called per request, permitting rotation. Diagnostic errors redact the resolved credential, but raw successful data can still be sensitive. Keep credentials off frontend clients.

Token usage and cache counts are reported only when returned by Ollama; durations and other terminal fields remain in private metadata, with full raw frames retained separately. Their presence does not guarantee caching or any model-specific behavior. Consult [the parameter inventory](ollama-parameters.md) for the pinned official schema, nested fields, source gaps and scope. A raw field being forwarded does not imply normalized runtime support. Fixture tests and compilation do not establish live model or device behavior.
