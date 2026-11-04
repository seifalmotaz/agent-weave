# Use OpenRouter

`agent_weave_openrouter` sends Chat Completions through the OpenAI adapter.
From the workspace root, run `dart pub get`, then save this example as
`examples/openrouter_demo.dart`. Set `OPENROUTER_API_KEY` and
`OPENROUTER_MODEL` in your backend environment. Choose a model available to your
account. Running the example makes a paid provider request.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;

Future<void> main() async {
  final apiKey = Platform.environment['OPENROUTER_API_KEY'];
  final modelId = Platform.environment['OPENROUTER_MODEL'];
  if (apiKey == null || modelId == null) {
    throw StateError('Set OPENROUTER_API_KEY and OPENROUTER_MODEL.');
  }
  final client = router.openRouterClient(apiKey: apiKey, appName: 'My app');
  try {
    final model = router.OpenRouterChatModel(
      client: client,
      model: modelId,
      provider: const router.OpenRouterProviderPreferences(allowFallbacks: false),
    );
    final result = await generateText(model: model, prompt: 'Say hello.');
    print(result.text);
  } finally {
    client.close();
  }
}
```

Run `dart run examples/openrouter_demo.dart` to print the response. Keep the API
key on the backend. Provider and model availability depend on your account.

## Configure requests

`OpenRouterChatModel` exposes typed `provider`, `fallbackModels`, `route`,
`reasoning`, and `usage` options represented by the pinned SDK. Use `configure`
for other SDK request options. The adapter protects runtime messages, registered
tools, output schema, and token bounds. `openRouterClient` accepts attribution,
session, and extra headers. See the [package README](https://github.com/seifalmotaz/agent-weave/tree/main/packages/agent_weave_openrouter#readme)
for an example of routing and reasoning options.

Plugins, top-level cache control, and newer provider-routing fields are not
available through the adapter. It does not preserve OpenRouter response provider
identity, cost, or reasoning continuation metadata. Do not use it for billing or
provider audit. Token usage and the model on usage events are forwarded when
supplied. The adapter rejects document inputs.

Direct model streams propagate HTTP and inline streaming errors from the SDK.
`generateText` wraps failures in `AgentRunException`; its `code` and `cause`
help diagnose failures on the backend. Keep the cause out of client responses:

```dart
try {
  final result = await generateText(model: model, prompt: 'Say hello.');
  print(result.text);
} on AgentRunException catch (error) {
  // Record error.code and error.cause only in trusted backend logs.
  print('Request failed: ${error.code}');
}
```

Check the account configuration if a request fails. Offline fixtures cover selected request
and stream behavior. Live model behavior, billing, cache hits, and cancellation
have not been verified. See [provider coverage](provider-coverage.md).
