# agent_weave_vercel_gateway

Vercel AI Gateway public Chat Completions and Responses adapters for AgentWeave.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_vercel_gateway/agent_weave_vercel_gateway.dart' as gateway;

Future<void> main() async {
  final key = Platform.environment['GATEWAY_API_KEY'];
  final modelId = Platform.environment['GATEWAY_MODEL'];
  final provider = Platform.environment['GATEWAY_PROVIDER'];
  if (key == null || modelId == null || provider == null) {
    throw StateError('Set GATEWAY_API_KEY, GATEWAY_MODEL, and GATEWAY_PROVIDER.');
  }
  final client = gateway.GatewayClient.withApiKey(apiKey: key);
  try {
    final model = gateway.GatewayChatModel(
      client: client,
      model: modelId,
      options: gateway.GatewayOptions(order: [provider]),
    );
    final result = await generateText(model: model, prompt: 'Say hello.');
    print(result.text);
  } finally {
    client.close();
  }
}
```

`GatewayClient.withApiKey` is available for a fixed gateway token. Resolve credentials on the backend; the resolver runs per request and may rotate both the bearer token and BYOK credentials. For a custom transport, use `GatewayClient.withTransport`; the caller owns that transport. Raw `createChat`, `streamChat`, `createResponse`, and `streamResponse` expose native JSON and response metadata. Provider-specific request options can be supplied under `providerOptions`; credentials belong only in the resolver.

The two models use the public OpenAI-compatible endpoints, not the separate Vercel AI SDK wire protocol. Gateway response metadata is preserved in raw responses; provider selection and cost are not inferred. Gateway file IDs and live service behavior are not verified. Never put credentials in logs, persistent history, or client-side applications.

See the [complete guide](https://seifalmotaz.github.io/agent-weave/vercel-gateway/)
and [option reference](https://seifalmotaz.github.io/agent-weave/gateway-options/).
