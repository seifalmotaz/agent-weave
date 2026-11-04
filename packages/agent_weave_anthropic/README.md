# agent_weave_anthropic

Native Anthropic Messages streaming for AgentWeave, backed by the third-party
`anthropic_sdk_dart 9.0.1` SDK. Development version; not published to pub.dev.

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

final client = anthropic.AnthropicClient.withApiKey(apiKey);
try {
  final result = await generateText(
    model: anthropic.AnthropicChatModel(client: client, model: yourEnabledModelId),
    prompt: 'Hello',
  );
  print(result.text);
} finally {
  client.close();
}
```

Keep hosted provider credentials on the backend. Use a prefixed import to avoid
collisions between SDK and AgentWeave types. Native Messages tools, typed JSON
schema output, signed/redacted thinking replay, cache controls, beta headers,
usage and cooperative cancellation are covered by offline fixtures.

File-ID documents, audio/video, server-side tool output and pause-turn workflows
are not implemented in this adapter. Other native resources remain available
through the SDK. This is not complete Anthropic endpoint/parameter coverage.

See the [native guide](https://seifalmotaz.github.io/agent-weave/anthropic/)
and [coverage matrix](https://seifalmotaz.github.io/agent-weave/provider-coverage/).
Independent and unofficial; not endorsed by Anthropic, TanStack or Serverpod.
