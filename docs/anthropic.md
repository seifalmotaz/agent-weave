# Native Anthropic Messages

`agent_weave_anthropic` implements the native Messages wire protocol, using
`anthropic_sdk_dart 9.0.1` for transport and typed options. That SDK is maintained
independently of Anthropic. This adapter is not an OpenAI-compatible gateway.

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

final client = anthropic.AnthropicClient.withApiKey(apiKey);
final model = anthropic.AnthropicChatModel(
  client: client,
  model: yourEnabledModelId,
);
try {
  final result = await generateText(model: model, prompt: 'Hello');
  print(result.text);
} finally {
  client.close();
}
```

Model availability is account-specific. Keep API keys on the backend. Use the
same adapter with `AiAgent<Session>` and `ServerpodRunStore` in a Serverpod app;
the core runtime owns the tool loop and approval validation.

## Implemented and fixture-tested

- System instructions separate from message blocks; text and URL images.
- User documents by URL, inline PDF, and inline plain text. See [documents](documents.md).
- Fragmented tool JSON, native tool-use/results, multiple calls, and replay.
- Native JSON schema format for `generateObject` and `AiAgent.outputSchema`.
- Thinking deltas with private signed/redacted block continuation.
- Cache read/creation input accounted in total input usage; read tokens retained
  in `cachedInputTokens`. A fixture is not evidence of an actual cache hit.
- `configure` for typed SDK options; native cache controls on user blocks,
  single-block system instructions, and tool definitions; strict tool options.
- Beta headers, user-profile options, cancellation signals and stream failures.

Configuration cannot rewrite authoritative messages, system instructions, tool
schemas or token bounds. Cache decoration is compared at the native block/tool
level; a schema property called `cache_control` is not silently ignored.

Thinking and signature replay belongs in server storage. Hydration does not
return private provider continuation blocks to the UI.

## Explicit limits

The pinned SDK does not support file-ID documents.
[Upstream PR #431](https://github.com/davidmigloz/ai_clients_dart/pull/431) adds
the missing source type; an open PR is not an available SDK release. The adapter also does not
implement audio/video input, hosted
server-tool output or `pause_turn` continuation. Unsupported stream blocks and
stop reasons fail explicitly. Other endpoints are available directly through
the provider SDK, with its own support and constraints.

Thirteen offline fixture tests cover selected serialization and stream contracts.
No live Anthropic request or device behavior has been tested. Complete nested
parameter, header, event and endpoint coverage remains open in the
[provider inventory](provider-coverage.md).
