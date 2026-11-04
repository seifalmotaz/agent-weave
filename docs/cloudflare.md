# Cloudflare Workers AI and AI Gateway

`agent_weave_cloudflare` provides REST clients and selected model adapters. The
contracts below are distinct; a model's support for one does not establish its
support for another. Model availability, options, pricing, gateway behavior and
live inference have not been verified by the offline fixtures.

| Contract | Client | Request |
| --- | --- | --- |
| Workers AI native | `CloudflareClient` | `POST /accounts/{accountId}/ai/run/{model}` with model-specific input |
| Gateway run | `CloudflareGatewayClient` | `POST /accounts/{accountId}/ai/run` wrapping `model`, `input`, and optional `options` |
| Compatible Chat | `CloudflareCompatibleClient` | `/accounts/{accountId}/ai/v1/chat/completions` |
| Compatible Responses | `CloudflareCompatibleClient` | `/accounts/{accountId}/ai/v1/responses` |

The native client also exposes `getModelSchema`, `listModels`, raw JSON, bytes,
and SSE methods. Raw methods preserve status, headers, bytes and, when present,
JSON; they do not validate every model's schema. Gateway options can be passed
to the gateway and compatible clients. `@cf/` models require a gateway ID for
the gateway run contract. The compatible endpoints have separate payloads and
stream semantics; select the adapter supported by the chosen model.

## Start a backend chat

Set `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_CHAT_MODEL` for a model available to your account. For Workers AI
models routed through Gateway, also set `CLOUDFLARE_GATEWAY_ID`.
The API token needs Account > Workers AI > Read permission, including when
calling third-party models. AI Gateway management permission alone is insufficient.

The complete `examples/cloudflare_demo.dart` program is:

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_cloudflare/agent_weave_cloudflare.dart' as cf;

Future<void> main() async {
  final accountId = Platform.environment['CLOUDFLARE_ACCOUNT_ID'];
  final apiToken = Platform.environment['CLOUDFLARE_API_TOKEN'];
  final modelId = Platform.environment['CLOUDFLARE_CHAT_MODEL'];
  final gatewayId = Platform.environment['CLOUDFLARE_GATEWAY_ID'];
  if (accountId == null || apiToken == null || modelId == null) {
    throw StateError(
      'Set CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN and CLOUDFLARE_CHAT_MODEL.',
    );
  }
  if (modelId.startsWith('@cf/') && gatewayId == null) {
    throw StateError(
      'Set CLOUDFLARE_GATEWAY_ID for Workers AI gateway requests.',
    );
  }
  final workers = cf.CloudflareClient.withApiToken(
    accountId: accountId,
    apiToken: apiToken,
    gateway: gatewayId == null
        ? null
        : cf.CloudflareGatewayOptions(gatewayId: gatewayId),
  );
  try {
    final model = cf.CloudflareCompatibleChatModel(
      client: cf.CloudflareCompatibleClient(client: workers),
      model: modelId,
    );
    final result = await generateText(model: model, prompt: 'Say hello.');
    print(result.text);
  } finally {
    workers.close();
  }
}
```

Run `dart run examples/cloudflare_demo.dart` from the workspace. It sends a real
inference request and may incur charges. This example was analyzed and compiled,
but not run against Cloudflare. Keep credentials on the backend.

For rotating secrets, construct `CloudflareClient` with an application-owned
`tokenResolver`. It runs per request within that request's timeout. Requests
use Bearer authorization. The optional client `gateway` supplies default
Gateway headers to native inference and compatible endpoints; explicit
request-level Gateway options override matching defaults. A model-in-path
request can therefore carry the gateway ID needed for prepaid Gateway billing.
Actual billing behavior has not been tested.

Gateway options include cache key, TTL, bypass, metadata, timeout and retry
headers. A cache key can group responses: choose it with the application's data
isolation and privacy requirements in mind. Custom Gateway headers cannot
override authentication or built-in option headers. The client does not retry
POSTs itself; Gateway retry headers request gateway-side behavior.

With an application-owned `workers` client, native inference is separate from
the compatible Chat adapter:

```dart
final embeddings = await cf.CloudflareEmbeddingModel(client: workers).embed(
  cf.CloudflareEmbeddingRequest(text: ['hello'], pooling: cf.CloudflarePooling.cls),
);
print(embeddings.vectors);
print(embeddings.pooling); // Actual returned pooling, never an inferred default.

final gateway = cf.CloudflareGatewayClient(client: workers);
final response = await gateway.runJson(
  modelId,
  {'messages': [{'role': 'user', 'content': 'Hello'}]},
  gateway: cf.CloudflareGatewayOptions(gatewayId: gatewayId),
);
print(response.json);
```

## Model adapters

- `CloudflareEmbeddingModel` supports the BGE `text` input and optional
  `CloudflarePooling.mean` or `.cls`. Its result exposes `vectors`, `shape`,
  returned `pooling`, `result`, and the full `response`.
- `CloudflareTranscriptionModel` accepts `CloudflareAudioInput.json` for
  model-specific JSON or `.bytes` for binary input, with a configurable content
  type defaulting to `application/octet-stream`. The exact binary REST content
  type and server acceptance have not been live verified. The result exposes
  text and raw result data.
- `CloudflareImageModel` accepts model-specific JSON. It returns image bytes for
  image content types and decodes the base64 `result.image` for Flux Schnell;
  retain `response` for raw JSON and metadata. Unknown formats require raw
  client inspection. Image format and model acceptance remain model-specific.

For an agent, prefer `CloudflareCompatibleChatModel` with an explicitly chosen,
currently available compatible model, configured by the application (for
example via an environment variable). `CloudflareCompatibleResponsesModel`
uses the separate Responses contract. Both expose `options` and an SDK-typed
`configure` callback; request-owned fields cannot be overridden through
`options`. Compatible Chat defaults to `max_completion_tokens`; select
`CloudflareChatTokenField.maxTokens` for models requiring `max_tokens`.

For example, configure the compatible Chat adapter with a model supplied by the
application:

```dart
final compatible = cf.CloudflareCompatibleClient(client: workers);
final chat = cf.CloudflareCompatibleChatModel(
  client: compatible,
  model: compatibleModelFromEnvironment,
);
```

`CloudflareChatModel` requires an explicit model and implements the documented
Hermes traditional single-tool continuation. It performs non-streamed native
requests even when used through the core stream API, accepts text parts, and
rejects multi-call continuation. Its structured-output mode sends a bare JSON
schema. Availability of the legacy Hermes model has not been verified; do not
assume that another native model supports this continuation format. Tool
execution and approvals remain the runtime's responsibility.

## Lifecycle and evidence

Pass a `CancellationToken` to client methods and model operations as needed.
Request timeouts include preparation; cancellation cannot undo an operation
already accepted remotely. Close the client when done. An injected transport
or HTTP client remains caller-owned. Cancelling one subscription signals that invocation without cancelling sibling
calls sharing its parent token. Cancelling the parent signals all active calls.
Streaming subscription cancellation aborts the request when supported by the
underlying HTTP client. No license acceptance
or paid inference occurs automatically.

Offline fixtures exercise selected request and response behavior, not live model
availability, full API parity, provider billing, or server acceptance. Consult
[Workers AI REST](https://developers.cloudflare.com/workers-ai/get-started/rest-api/),
[function calling](https://developers.cloudflare.com/workers-ai/features/function-calling/),
[JSON mode](https://developers.cloudflare.com/workers-ai/features/json-mode/), and
[AI Gateway REST](https://developers.cloudflare.com/ai-gateway/usage/rest-api/)
for current provider requirements. See [provider coverage](provider-coverage.md)
and [compatibility](compatibility.md) for the scope of this integration. The
[API inventory reference](cloudflare-api-reference.md) records the classified
contracts; it is not a parity certificate. The inventory includes management
endpoints that are not integrated. Compatible endpoint documentation is tracked
separately from the pinned API specification.
