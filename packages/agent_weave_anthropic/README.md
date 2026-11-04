# agent_weave_anthropic

Anthropic Messages for the AgentWeave Dart runtime. This independent package is
a development version and is not published to pub.dev.

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

final client = anthropic.AnthropicNativeClient.withApiKey(apiKey: apiKey);
try {
  final result = await generateText(
    model: client.chatModel(model: yourEnabledModelId),
    prompt: 'Hello',
  );
  print(result.text);
} finally {
  client.close();
}
```

Keep credentials on the backend. The native client supports raw JSON and SSE,
request cancellation, credential resolution and `chatModel` integration.
Its default API version is `2023-06-01`; set `apiVersion` explicitly for a
different supported version. The existing `AnthropicChatModel` accepts a typed
`anthropic_sdk_dart` client for SDK-backed integrations. Raw access does not
mean every provider feature is integrated into the agent loop.

See the [native guide](https://seifalmotaz.github.io/agent-weave/anthropic/)
for a complete example, private replay, client ownership and protocol limits,
and the [coverage matrix](https://seifalmotaz.github.io/agent-weave/provider-coverage/).

`AnthropicComputerTool` adds the 17-member computer toolset with an app-owned
executor, typed Dart action records/enums, approval and batch-failure handling.
See the [computer guide](https://seifalmotaz.github.io/agent-weave/anthropic-computer/).
Native file-ID documents use `provider: 'anthropic'`; the pinned SDK typed
configuration callback cannot decode them. Live driver behavior remains unverified.

`AnthropicHostedTool` accepts typed SDK or native definitions for provider-executed
search, fetch, code and tool search. Paused turns use the normal step budget and
private container replay. See the [hosted-tool guide](https://seifalmotaz.github.io/agent-weave/anthropic-hosted/)
for mixed approvals, configuration and current limits.
