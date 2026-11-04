# Anthropic Messages

Use `AnthropicNativeClient` for native JSON and SSE access, including fields the
pinned Dart SDK does not know. Its `chatModel` also integrates supported
Messages streams with AgentWeave's text, structured output and tool loop. The
package is independent and unofficial.

## Run the example

From the workspace, set `ANTHROPIC_API_KEY` and `ANTHROPIC_MODEL` in the
backend environment, then run `dart run examples/anthropic_demo.dart`. Optionally
set `ANTHROPIC_VERSION`; it defaults to `2023-06-01` for backwards
compatibility. The example requests adaptive thinking, caching and structured
output, so choose a model and API version that support that combination. It
makes a billable request. See [Anthropic's versioning documentation](https://docs.anthropic.com/en/api/versioning)
and verify the current model and feature requirements before selecting a newer
version.

The example's `configure` receives a read-only JSON snapshot. Return a new map,
as it does with `...body`. The agent owns messages, max tokens, system
instructions and tools, and protects the runtime output schema. You can add
supported native options without replacing these values; this does not imply
AgentWeave implements the behavior of every forwarded field.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

Future<void> main() async {
  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
  final modelId = Platform.environment['ANTHROPIC_MODEL'];
  if (apiKey == null || apiKey.isEmpty || modelId == null || modelId.isEmpty) {
    throw StateError('Set ANTHROPIC_API_KEY and ANTHROPIC_MODEL.');
  }
  final client = anthropic.AnthropicNativeClient.withApiKey(
    apiKey: apiKey,
    apiVersion: Platform.environment['ANTHROPIC_VERSION'] ?? '2023-06-01',
  );
  try {
    final model = client.chatModel(
      model: modelId,
      configure: (body) => {
        ...body,
        'thinking': {'type': 'adaptive'},
        'cache_control': {'type': 'ephemeral'},
      },
    );
    final result = await generateObject<String>(
      model: model,
      prompt: 'Give one concise title for a guide to growing herbs indoors.',
      schema: const {
        'type': 'object',
        'properties': {
          'title': {'type': 'string'},
        },
        'required': ['title'],
        'additionalProperties': false,
      },
      decode: (json) => (json as Map<String, Object?>)['title'] as String,
    );
    print(result.value);
  } finally {
    client.close();
  }
}
```

## Native requests and streams

`client.createMessage(body)` returns an `AnthropicNativeResponse` with the raw
JSON in `data`, HTTP `statusCode`, and sanitized response `headers`.
`client.countTokens(body)` calls the native token-counting endpoint and returns
the same response shape, including fields such as `input_tokens` when supplied
by the service. Both methods and `streamMessages(body)` accept per-request
`headers`, `query` and `cancellation`; query values are lists of strings.
`streamMessages` yields `JsonSseData` with raw event `data`, event name, ID and
response headers. Error details retain private provider content after credential
scrubbing; do not expose them directly in a UI or logs. It requires a complete stream ending in `message_stop`.
`send` provides native JSON access to other paths without claiming endpoint
coverage.

The client defaults to API version `2023-06-01`; set `apiVersion` explicitly
when your integration needs another version. Constructor options `betas`,
`workspaceId`, and `userProfileId` set headers. In particular the
`anthropic-workspace-id` and `anthropic-user-profile-id` headers are separate
from any `workspace_id` and `user_profile_id` fields you put in a native JSON
body. Check the provider contract for the endpoint and version you use.

A `credentialResolver` can fetch or rotate a key for each request; alternatively
use `withApiKey`. Keep credentials on the backend. Close the native client when
finished; an injected `http.Client` is borrowed and remains the caller's
responsibility. There are no automatic retries. Cancellation aborts local
request work; it does not undo a request or external effect already accepted by
the provider.

## SDK-backed facade

Existing integrations can still construct `AnthropicChatModel` with an
`anthropic_sdk_dart` `AnthropicClient` and a typed `MessageCreateRequest`
`configure` callback. The SDK client is caller-owned. The typed callback's patch
preserves unknown unchanged JSON fields; edits to fields or lists can replace the
corresponding values. The SDK's typed representation still cannot express every
new provider field. Prefer the native client for unknown fields and
request-scoped transport cancellation.

## Replay and limits

The agent preserves provider content blocks for continuation, including
signatures and unknown fields on supported block types. This replay data and raw
responses may contain sensitive content; keep them private on the backend and
out of user-facing hydration or logs. The normalized agent currently handles
text, thinking, redacted thinking, client tool-use and pinned hosted-tool blocks with supported
text, thinking, signature and input JSON deltas. Citation blocks are normalized as typed message annotations and additive UI
events; opaque native fields remain private. See [document citations](citations.md). Unknown block types or deltas
fail explicitly. Hosted tools and bounded `pause_turn` continuation are integrated; see the
[hosted-tool guide](anthropic-hosted.md). Audio/video, MCP, browser tools and
complete nested semantics remain unfinished. Use raw native access for other
protocols.
For client computer use, see the [computer-use guide](anthropic-computer.md).
File-ID document parts are supported by the native agent path; the typed SDK
configuration path cannot yet decode them. URL and supported inline documents
are also available.

See the [request field inventory](anthropic-parameters.md) for the pinned
contract and disposition of each field. Fixtures exercise selected behavior;
they do not establish live model support or complete endpoint parity.

## Upstream SDK cancellation fix

[SDK PR #432](https://github.com/davidmigloz/ai_clients_dart/pull/432) adds prompt
cancellation before response headers, during stalled bodies, and through the
public stream wrappers while retaining shared-client ownership. The contribution
is submitted, not merged or released. AgentWeave's native client already uses
its own shared transport and does not require this unreleased SDK change.

## Upstream citation file identifiers

The pinned SDK 9.0.1 drops `file_id` on known document citation response types.
AgentWeave preserves raw native blocks independently. The typed SDK correction
was merged in [upstream PR #441](https://github.com/davidmigloz/ai_clients_dart/pull/441).
The dependency remains pinned to 9.0.1 until an upstream release includes the fix.

## MCP connector boundary

The agent model does not yet normalize Anthropic MCP server calls and results.
Nonempty `mcp_servers` configuration is rejected before HTTP dispatch, as is
unsupported `mcp_toolset` injection. Null or empty server lists and unrelated
request options remain available. This is an interim execution guard, not MCP
integration; the complete owned lifecycle remains planned work.

Use explicit raw `AnthropicNativeClient.createMessage` or `streamMessages` for
advanced API access when your application owns the full provider contract.
Raw access does not add agent normalization, checkpointing or effect recovery.
The pinned typed SDK cannot represent `mcp_servers`; a typed JSON reconstruction
can discard that field and send an ordinary request. It does not enable MCP.
