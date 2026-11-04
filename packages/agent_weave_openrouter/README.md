# AgentWeave OpenRouter

OpenRouter Chat Completions for AgentWeave. Keep API keys on the backend and close the client on shutdown.

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;

final client = router.openRouterClient(apiKey: apiKey);
final model = router.OpenRouterChatModel(
  client: client,
  model: modelId, // A model available to your OpenRouter account.
  fallbackModels: [fallbackModelId],
  provider: const router.OpenRouterProviderPreferences(
    order: ['OpenAI'],
    allowFallbacks: true,
  ),
  reasoning: const router.OpenRouterReasoning(effort: 'low'),
);
try {
  final result = await generateText(model: model, prompt: 'Hello');
  print(result.text);
} finally {
  client.close();
}
```

This adapter delegates to AgentWeave's OpenAI Chat Completions adapter and `openai_dart` 11.0.1. It forwards SDK-represented OpenRouter provider preferences, fallback models, route, reasoning and usage settings. `configure` exposes other SDK request options; runtime messages, registered tools, output schema and maximum tokens remain protected by the delegated adapter. Set attribution and session headers on `openRouterClient`; arbitrary extra headers can be supplied with `headers`. Capabilities vary by model and provider.

The SDK does not represent every OpenRouter request field. In particular, plugins, top-level cache control, and newer provider-routing fields are not available through this adapter. OpenRouter-specific response metadata, provider identity, cost and reasoning continuation data are not exposed by AgentWeave's delegated adapter; do not rely on it for billing or provider audit. Token usage and the model reported on usage events are forwarded when supplied. Direct model streams propagate HTTP and inline streaming errors from the SDK. `generateText` wraps failures in `AgentRunException`; inspect its `cause` only in trusted backend logs, not client responses. Model-specific behavior, billing, cache hits and live cancellation have not been verified against OpenRouter.

See the [complete setup recipe](https://seifalmotaz.github.io/agent-weave/openrouter/).

References: [Chat Completions API](https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request), [provider routing](https://openrouter.ai/docs/guides/routing/provider-selection), [streaming](https://openrouter.ai/docs/api/reference/streaming).
