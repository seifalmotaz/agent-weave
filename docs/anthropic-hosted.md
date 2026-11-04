# Anthropic hosted tools

Add provider-executed search, fetch, code execution or tool search to an ordinary
AgentWeave agent. Your `Tool` registrations remain application-executed; hosted
tools do not call their executors or produce local approval requests.

This complete example makes a billable request when you run it. Choose a model
that accepts web search and set `ANTHROPIC_API_KEY` and `ANTHROPIC_MODEL`.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

Future<void> main() async {
  final key = Platform.environment['ANTHROPIC_API_KEY'];
  final modelId = Platform.environment['ANTHROPIC_MODEL'];
  if (key == null || key.isEmpty || modelId == null || modelId.isEmpty) {
    throw StateError('Set ANTHROPIC_API_KEY and ANTHROPIC_MODEL.');
  }
  final client = anthropic.AnthropicNativeClient.withApiKey(apiKey: key);
  try {
    final agent = AiAgent<void>(
      model: client.chatModel(
        model: modelId,
        hostedTools: [
          anthropic.AnthropicHostedTool(
            const anthropic.WebSearchTool(maxUses: 3),
          ),
        ],
      ),
      maxSteps: 4,
      maxOutputTokens: 1024,
    );
    final result = await agent.generate(
      ChatRequest(
        threadId: 'research',
        runId: 'first',
        messages: [
          ChatMessage.user(
            'Find the latest stable Dart release.',
            id: 'question',
          ),
        ],
      ),
      ownerId: 'local-example',
      context: null,
    );
    print(result.text);
  } finally {
    client.close();
  }
}
```

## Configure hosted tools

`AnthropicHostedTool` snapshots a typed SDK `BuiltInTool`. Its `fromJson`
constructor retains unknown native option fields. Both constructors check an
explicit supported type/name pair and exclude client-executed tools such as
bash, memory, browser and computer. They also reject conflicting domain lists.
Other nested options and model acceptance are validated by the provider.

The current source pin contains 15 type spellings across web search, web fetch,
code execution and regex/BM25 tool search, including the unversioned tool-search
aliases. `dart run tool/anthropic_hosted_contract.dart` checks each spelling
against the extracted official declarations and rejects the known client tools.
This checks configuration coverage, not every nested option or live workflow.

For typed code execution, use:

```dart
final hosted = anthropic.AnthropicHostedTool(
  anthropic.CodeExecutionBuiltInTool(),
);
```

Pass the resulting values through `hostedTools` on
`AnthropicNativeClient.chatModel`, `AnthropicProtocolModel`, or the SDK-backed
`AnthropicChatModel`. Hosted names must be unique and cannot shadow registered
application tool names. The runtime protects the complete tool list from
replacement by `configure`. Provider decorations such as `allowed_callers`,
`defer_loading`, `strict` and cache control can be set through configuration.

## Pauses, replay and containers

A complete `pause_turn` response yields `ModelFinished.continuation`. The core
agent stores the response before its next invocation and counts every invocation
against `maxSteps`. It continues with the ordered native content and the same
tools. It preserves the latest returned container ID from message-start or
message-delta metadata. Configuration cannot replace an inherited container ID.
These rules follow the [official server-tool lifecycle](https://platform.claude.com/docs/en/agents-and-tools/tool-use/server-tools).

Each pause is a checkpoint, rather than an automatic retry of a failed request.
A malformed stream, EOF, error or cancellation does not automatically dispatch
another request. The existing error and cancellation APIs still apply. Usage
accumulates across completed model invocations. With a schema, paused text is
progress and only the final response is validated as the answer. A sanitized
message snapshot closes the intermediate structured UI state without showing a
false failure. Completed structured data survives history hydration. `maxSteps` bounds invocations,
not provider-side searches, code execution, tokens or money; also configure the
provider's limits and your application budget.

If the step limit is reached while paused, the run returns `STEP_LIMIT` and keeps
its private continuation. A new run on the same owner/thread, with no new
messages and the same model/tool configuration, can explicitly continue it.
New user messages are rejected while that continuation is pending. Use a new
run ID; a recreated agent can share the same store. This is not automatic
recovery from an arbitrary process crash or an unknown external effect.

## Mixing hosted and application tools

The adapter keeps `server_tool_use` and result blocks private and never turns
them into an application call. Your ordinary tool follows its usual schema,
approval, context and result contract. A response can defer a hosted action
while your application tool waits for approval. The next user content must then
contain all of that turn's client tool results, without additional user text.
The adapter validates this shape before dispatch.

Programmatic calls from provider code execution require an explicit
`allowed_callers` opt-in on the registered application tool's provider definition.
The adapter checks the caller type and its reference to an active code-execution
call before emitting an application call. The documented `code_execution_20260521`
caller option accepts the canonical `code_execution_20260120` response tag.
Unfinished code execution requires a returned or explicitly configured container
ID; missing identity fails before local execution. Tool input validation still applies, and `needsApproval` uses the normal
approval flow. Tool-search results stay opaque. References do not install executors or grant
permissions; the runtime invokes only application tools you separately register.

## Private data and current evidence

Ordered content lives in `anthropic.messages`, cumulative metadata and containers
in `anthropic.messages.metadata`, and the configured continuation tool list in
`anthropic.messages.tools`. Keep these fields on the backend. They can contain
sensitive fetched text, opaque encrypted values, caller IDs, container IDs and
citations. `chatHydration` excludes them. Citation deltas remain on the native
text blocks for replay; this release has no public citation-rendering event.

The normalizer accepts the pinned content union, including search, fetch, code,
bash-code, text-editor-code and tool-search results plus container uploads.
Unknown top-level blocks or deltas fail explicitly. MCP, browser tools and
complete nested response semantics remain outside this integration.

Local fixtures cover typed and raw definitions, fragmented server input, opaque
results, paused turns, exact tool/container replay, programmatic caller checks,
mixed approvals, cancellation, malformed output, hydration privacy and bounds.
They do not prove model availability, real search quality, downloaded files,
container expiry, billing or live provider behavior. See
[validation](validation.md) and [the independent developer review](dx-review.md).

The [official programmatic-calling guide](https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling)
describes caller aliases, required containers and timeout limits. Container
expiry can still reject a later continuation; application tools must implement
idempotency and reconcile external effects. No live expiry policy is certified.
