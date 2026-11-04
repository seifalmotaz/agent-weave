# AgentWeave OpenRouter

OpenRouter Chat Completions and stateless Responses for AgentWeave. Keep credentials on the backend and close the client on shutdown.

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;

final client = router.OpenRouterClient.withApiKey(apiKey: apiKey);
final model = router.OpenRouterChatModel(
  client: client,
  model: modelId,
  options: router.OpenRouterChatOptions(
    fallbackModels: [fallbackModelId],
    provider: router.OpenRouterProviderPreferences(
      order: ['openai'],
      allowFallbacks: true,
    ),
    reasoning: router.OpenRouterReasoning(effort: router.OpenRouterReasoningEffort.low),
  ),
);
try {
  final result = await generateText(model: model, prompt: 'Hello');
  print(result.text);
} finally {
  client.close();
}
```

`OpenRouterResponsesModel` supports the Responses API with full history and a separate replay namespace. OpenRouter does not support stateful Responses continuation; do not set `store: true` or `previous_response_id`. Chat reasoning details and Responses output items are retained as private provider data for continuation. Provider metadata, including reported cost and actual provider, is private provider data and should be treated as sensitive. Costs are never inferred.

Use `OpenRouterClient` with a `credentialResolver` for per-request rotating keys. Attribution and session headers are optional constructor parameters. The client owns its transport; `OpenRouterClient.withTransport` borrows it, and an injected HTTP client remains caller-owned. The raw `createChat`, `streamChat`, `createResponse`, and `streamResponse` methods accept JSON and preserve provider envelopes and unknown fields. Stream events expose SSE data and safe response headers. Provider options support extra JSON for new fields; model options reject runtime-owned history, tools, schema, token bounds, and streaming controls. `configure` offers compatible typed OpenAI request options under the same runtime protections.

Only Chat Completions and Responses are integrated. Capabilities vary by model and provider; this package does not claim coverage of other OpenRouter APIs or all native unions. The local tests use fixtures and loopback requests, not live OpenRouter billing or model behavior.


For generated images through Chat, set
`OpenRouterChatOptions(modalities: [OpenRouterOutputModality.text,
OpenRouterOutputModality.image], imageConfig: {...})` on a model that supports
Chat image output. These requests use completed JSON responses; ordinary text
uses SSE. `result.images` provides this run's assistant images, and private
replay survives approvals and stored history. See the
[image guide](https://seifalmotaz.github.io/agent-weave/openrouter-images/) for
ordering, supported URI forms and the separate dedicated Images API limitation.
