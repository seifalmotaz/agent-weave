# Use OpenRouter

`agent_weave_openrouter` has a native JSON/SSE client and separate Chat and
Responses adapters. It reuses AgentWeave's compatible wire codecs, while native
routing, plugins, reasoning, cache options and metadata bypass the OpenAI SDK's
request serializer. This is selected integration, not complete OpenRouter parity.

Set `OPENROUTER_API_KEY` and `OPENROUTER_MODEL` in your backend environment for a
model available to your account. From the workspace root, run `dart pub get`,
then `dart run examples/openrouter_demo.dart`. This sends a real request and may
incur charges. The complete program is:

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
  final client = router.OpenRouterClient.withApiKey(
    apiKey: apiKey,
    appName: 'My app',
    headers: {'X-OpenRouter-Metadata': 'enabled'},
  );
  try {
    final model = router.OpenRouterChatModel(
      client: client,
      model: modelId,
      options: router.OpenRouterChatOptions(
        provider: router.OpenRouterProviderPreferences(requireParameters: true),
      ),
    );
    final result = await generateText(model: model, prompt: 'Say hello.');
    print(result.text);
  } finally {
    client.close();
  }
}
```

The example was analyzed and compiled without execution. Keep credentials on the
backend. The caller closes the client at shutdown. An injected HTTP client or
`OpenRouterClient.withTransport` transport remains caller-owned. For rotating
secrets, use `OpenRouterClient(credentialResolver: yourTokenLoader)`; resolution
occurs per request within the request deadline. Attribution and session headers
are configured on the client; authorization belongs to the resolver.

## Native options

`OpenRouterChatOptions` and `OpenRouterResponsesOptions` keep native fields
separate from runtime-owned messages, tools, schema, token bounds and streaming.
They take immutable snapshots, including nested `extra` values. OpenRouter
reports usage automatically; deprecated usage-inclusion flags do not control it.

```dart
final options = router.OpenRouterChatOptions(
  provider: router.OpenRouterProviderPreferences(
    order: ['provider-selected-by-your-app'],
    allowFallbacks: false,
    requireParameters: true,
    dataCollection: router.OpenRouterDataCollection.deny,
    sort: router.OpenRouterProviderSort.price,
    maxPrice: {'prompt': '1', 'completion': '2'},
  ),
  reasoning: router.OpenRouterReasoning(
    effort: router.OpenRouterReasoningEffort.low,
  ),
  cacheControl: router.OpenRouterCacheControl(),
  plugins: [router.OpenRouterPlugin(id: 'response-healing')],
  extra: {'prompt_cache_key': 'application-scoped-key'},
);
```

This is configuration syntax, not a tested provider/model combination. Provider
availability, supported parameters, plugin behavior and price units follow the
[official routing contract](https://openrouter.ai/docs/guides/routing/provider-selection).
Do not assume every combination works. `requireParameters` asks OpenRouter to
filter providers that cannot support the requested parameters.

Provider preferences also expose allow/ignore lists, ZDR, quantizations,
distillable-text enforcement, provider-specific options and performance
preferences. Nested price, percentile and provider-option structures remain
JSON so their schema unions and unknown fields survive. `extra` supports newer
native options. A recognized field is not proof of orchestration or acceptance.

The optional `configure` callback remains SDK-typed for compatible request
parameters. Prefer `request.copyWith(...)`; rebuilding a request through the
SDK's typed JSON input decoder can reject raw reasoning items. Native fields
belong in `options` or `extra`. Neither path can replace runtime history or
registered function definitions. Native JSON client methods are separate for
requests the normalized agent does not implement.

## Generated images

Use [Chat image output](openrouter-images.md) with explicit text/image modalities
for a completed assistant message. Ordinary text uses SSE; image requests are
buffered because the pinned Chat stream schema does not define image deltas.
Images and opaque replay fields survive tool approvals and server-owned history.
For the dedicated `/images` endpoint, use `OpenRouterImageModel`. It supports
buffered results, native SSE events, same-request JSON fallback and model/endpoint
discovery. See the [dedicated Image API guide](openrouter-image-api.md).

## Responses and private replay

Use `OpenRouterResponsesModel(client: client, model: modelId, options: ...)`
for `/responses`. It has its own private replay namespace. OpenRouter Responses
is stateless: send complete input history. The adapter rejects `store: true` and
non-null `previous_response_id`; it does not depend on a server-stored response.
It excludes automatic OpenAI encrypted-reasoning includes; OpenRouter documents
automatic encrypted content for supported reasoning providers.

Returned Responses output items retain opaque fields and order through the next
tool turn. Chat retains ordered `reasoning_details` fragments as returned, in
`openrouter.chat.reasoning`, and replays them only to the Chat endpoint. It does
not sort or deduplicate blocks. If only plaintext `reasoning` is returned, it
streams as reasoning text and is privately retained in
`openrouter.chat.reasoning_text` for the next turn. Structured details take
precedence when both representations are returned. The fixture verifies ordered replay, not every
provider's incremental-fragment behavior. Unknown or cross-provider private
history is not substituted for this provider's replay. File handles owned by
another provider are rejected; Responses URL and inline document sources remain
separate from provider-owned IDs. Chat document parts are not implemented.

## Metadata and native responses

`X-OpenRouter-Metadata: enabled` opts into router metadata when supplied by the
service. The adapter retains actual generation/model/provider identity, usage,
cost and unknown response metadata in private assistant `providerData` under
`openrouter.chat.metadata` or `openrouter.responses.metadata`. Missing values
stay absent. It does not infer the provider or compute an invoice. Reasoning and
metadata stay out of UI hydration; `AgentResult` is trusted backend data.

Normalized metadata is a compact merged snapshot. It is not a log of every
stream frame. For complete native envelopes, headers and event IDs, use
`client.createChat`, `streamChat`, `createResponse`, or `streamResponse`. Native
JSON responses expose `data`, `statusCode` and headers. Streaming preserves
unknown event fields and detects inline errors and premature EOF.

The native client does not implement management APIs or every modality. Hosted
server tools, background-job handling, other output media and all model variants still
need dedicated runtime behavior. See the [API inventory](openrouter-api-reference.md)
for all pinned operations and fields, including those not integrated.

## Errors and cancellation

Direct streams propagate redacted `JsonHttpException` diagnostics.
`generateText` wraps failures in `AgentRunException`; use its `code`, and inspect
`cause` only on the trusted backend. Error details and headers may contain private
provider information, so do not send them to a UI. Resolver failures and malformed
stream payloads use generic messages. Known request credentials are redacted.

Requests have per-call deadlines and cancellation. Cancelling one subscription
signals that call without cancelling siblings sharing a parent token; cancelling
the parent signals all active calls. This does not undo requests already accepted
remotely. The client does not automatically retry POSTs.

## Validation and migration

Offline loopback cases exercise Chat and Responses schema output, persisted tool
approval and replay, opaque reasoning, metadata, error privacy, rotating
credentials, cancellation and client ownership. They do not establish live model
support, cache hits, routing, billing, or all native fields.

Earlier development versions returned an `OpenAIClient` from `openRouterClient`
and exported SDK routing types. `openRouterClient` now returns `OpenRouterClient`.
Use `options: OpenRouterChatOptions(...)` for provider/reasoning/fallback settings;
use native enums and non-const option constructors for immutable snapshots.
Consumers explicitly typing the old SDK client must migrate. `configure` remains
available for SDK-compatible parameters. See [coverage](provider-coverage.md),
[validation](validation.md) and [the independent review](dx-review.md).
