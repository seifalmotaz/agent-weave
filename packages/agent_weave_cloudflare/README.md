# Cloudflare Workers AI and AI Gateway

`CloudflareClient` calls the native Workers AI REST endpoint. Provide an
account ID and a per-request async `tokenResolver` or use `withApiToken`.
Optional client `gateway` settings also reach native model-in-path inference.
Close the client when finished; an injected transport or HTTP client remains
caller-owned. Raw `runJson`, `runJsonOrBytes`, `runBytes`, `stream`,
`getModelSchema`, and `listModels` retain response data and expose model-specific
parameters without claiming that every model supports the same schema.

`CloudflareGatewayClient` is a separate `/ai/run` contract. Its request wraps
`model`, `input`, and optional `options`; `CloudflareGatewayOptions` supplies
request headers. Cloudflare requires a gateway ID for `@cf/` models on this
endpoint. Cache keys can group responses, so choose them with care.

`CloudflareEmbeddingModel` covers the BGE text/pooling input,
`CloudflareTranscriptionModel` supports binary and JSON input, and
`CloudflareImageModel` returns decoded image bytes and the full response for supported formats. Responses retain full JSON,
bytes, status, and headers. Model-specific outputs vary.

`CloudflareChatModel` uses the documented Hermes traditional single-tool
continuation and non-streamed requests, even through the core `stream` method.
Its schema mode passes Cloudflare's bare JSON schema. It rejects multi-call
continuation and non-text parts; native model support and streamed formats vary.
The Hermes catalog availability has not been verified. Binary Whisper content type and server acceptance have not been verified; JSON audio is documented. The runtime owns tool execution and approvals. No inference, license acceptance,
or POST retry happens automatically.

References: [Workers AI REST](https://developers.cloudflare.com/workers-ai/get-started/rest-api/),
[traditional example](https://developers.cloudflare.com/workers-ai/features/function-calling/),
[JSON mode](https://developers.cloudflare.com/workers-ai/features/json-mode/),
[AI Gateway REST](https://developers.cloudflare.com/ai-gateway/usage/rest-api/),
[Gateway headers](https://developers.cloudflare.com/ai-gateway/glossary/).

```dart
final workers = CloudflareClient(
  accountId: accountId,
  tokenResolver: () async => loadCloudflareToken(),
);
final embeddings = await CloudflareEmbeddingModel(client: workers).embed(
  CloudflareEmbeddingRequest(text: ['hello'], pooling: CloudflarePooling.cls),
);
print(embeddings.result); // Full native result, including shape.

final gateway = CloudflareGatewayClient(client: workers);
final result = await gateway.runJson(
  '@cf/meta/llama-3.1-8b-instruct',
  {'messages': [{'role': 'user', 'content': 'Hello'}]},
  gateway: CloudflareGatewayOptions(gatewayId: 'my-gateway'),
);
print(result.cacheStatus);
workers.close();
```

For `/ai/v1/chat/completions` or `/ai/v1/responses`, use
`CloudflareCompatibleClient` and the corresponding
`CloudflareCompatibleChatModel` or `CloudflareCompatibleResponsesModel`.
Compatible model availability and supported fields are provider-specific.
`CloudflareChatTokenField.maxTokens` selects the legacy `max_tokens` field when
required by a model; the default is `max_completion_tokens`.

See the [Cloudflare guide](../../docs/cloudflare.md) for endpoint selection, lifecycle, and limitations.
