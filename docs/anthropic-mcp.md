# Connect Anthropic MCP tools

Use `mcpServers` with `AnthropicNativeClient.chatModel`, `AnthropicChatModel`, or
`AnthropicProtocolModel`. Anthropic executes the selected remote tools. They do
not become local `Tool` registrations or application approval requests.

## Run the example

Set `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `MCP_SERVER_URL` and
`MCP_ALLOWED_TOOL`, then run `dart run examples/anthropic_mcp_demo.dart`.
Choose a trusted server and one tool appropriate for the request. Optional
`MCP_ACCESS_TOKEN` supplies its OAuth token; `MCP_PROMPT` changes the question.
Running this example makes billable requests and can execute that remote tool.
The example uses memory storage and bounds provider continuations with
`maxSteps`; repository checks compile it without running it.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

Future<void> main() async {
  final environment = Platform.environment;
  final key = environment['ANTHROPIC_API_KEY'];
  final model = environment['ANTHROPIC_MODEL'];
  final url = environment['MCP_SERVER_URL'];
  final tool = environment['MCP_ALLOWED_TOOL'];
  if ([key, model, url, tool].any((value) => value == null || value.isEmpty)) {
    throw StateError(
      'Set ANTHROPIC_API_KEY, ANTHROPIC_MODEL, MCP_SERVER_URL and MCP_ALLOWED_TOOL.',
    );
  }
  final token = environment['MCP_ACCESS_TOKEN'];
  final client = anthropic.AnthropicNativeClient.withApiKey(apiKey: key!);
  try {
    final agent = AiAgent<void>(
      model: client.chatModel(
        model: model!,
        authorityBindingId: 'local-example/anthropic-account',
        options: {'temperature': 0.2},
        mcpServers: [
          anthropic.AnthropicMcpServer(
            name: 'support',
            url: Uri.parse(url!),
            beta: anthropic.AnthropicMcpBeta.client20260915,
            toolset: anthropic.AnthropicMcpToolset(
              defaultConfig: anthropic.AnthropicMcpToolConfig(enabled: false),
              configs: {tool!: anthropic.AnthropicMcpToolConfig(enabled: true)},
            ),
            credentialBindingId: token == null
                ? null
                : 'local-example/mcp-account',
            authorizationToken: token == null ? null : () => token,
          ),
        ],
      ),
      maxSteps: 4,
      maxOutputTokens: 1024,
    );
    final result = await agent.generate(
      ChatRequest(
        threadId: 'support',
        runId: 'question',
        messages: [
          ChatMessage.user(
            environment['MCP_PROMPT'] ??
                'Use $tool to find information about Dart streams.',
            id: 'u',
          ),
        ],
      ),
      ownerId: 'local-example',
      context: null,
    );
    print(result.text);
  } on AgentRunException catch (error) {
    stderr.writeln('${error.code}: ${error.message}');
    exitCode = 1;
  } finally {
    client.close();
  }
}
```

For the reproducible offline application, run:

```sh
dart --enable-asserts run examples/review_cases/anthropic_mcp.dart
```

It uses an SDK-compatible HTTP fixture and two MCP servers. It verifies a
mixed local approval, deferred remote result, configuration rejection and
credential rotation. It does not contact Anthropic or execute remote effects.

## Declare servers, tools and authority

Each `AnthropicMcpServer` has a unique name, an HTTPS URL and an explicit beta.
All servers in one model use the same beta. Modern modes generate exactly one
matching toolset per server. `AnthropicMcpToolset` supports default and per-tool
`enabled`/`deferLoading`, `cacheControl` and native `fromJson` extensions. Unknown
tool names in `configs` are retained because discovery can change.

| Beta | Wire configuration |
| --- | --- |
| `client20260915` | Modern server/toolset plus recorded listings and optional pinned tools; documented for the Claude API |
| `client20251120` | Modern server/toolset; cloud-platform availability differs |
| `legacy20250404` | Deprecated server `tool_configuration`; no toolsets or pinned descriptors |

The modes follow the [official connector contract](https://platform.claude.com/docs/en/agents-and-tools/mcp-connector).
Legacy mode requires `legacyToolConfiguration` or the native
`tool_configuration` field through `fromJson`. It rejects modern toolsets.
Pinned tool descriptors belong in `AnthropicMcpToolset(tools: [...])` and require
`client20260915`. Each descriptor has a name, input schema and optional
description. Beta acceptance by a live model or cloud platform is unverified.

The SDK-backed facade sends the owned native MCP JSON through its raw stream
method; the pinned SDK's typed Messages request does not represent these server
fields. Reconstructing an SDK request from arbitrary JSON is not MCP support.

Managed MCP or hosted tools require a stable, nonsecret `authorityBindingId`
for the provider account and endpoint/routing configuration. Change it when
that authority changes; never use an API key. Additional request parameters
belong in frozen `options`, with `toolChoice` for selection. Configuration
callbacks are rejected when managed tools are present. Core binds the original
model, beta flags, authority, toolsets, options and credential identities before
resuming local effects or dispatch. Changing them invalidates the unfinished
turn. See [continuation contracts](approval-contracts.md).

Client-level beta flags are merged with the owned MCP header rather than
replaced. Duplicate flags collapse; conflicting MCP versions fail before
transport. The effective beta list is retained in the private model profile.

## Resolve owner-bound credentials

Create the model in the authenticated backend scope. Derive the owner from the
session, and resolve that owner's token on each outbound request:

```dart
final server = anthropic.AnthropicMcpServer(
  name: 'support',
  url: Uri.https('support.example.com', '/mcp'),
  beta: anthropic.AnthropicMcpBeta.client20260915,
  credentialBindingId: account.stableAuthorizationIdentity,
  authorizationToken: () => tokens.accessTokenFor(authenticatedOwner, account),
);
```

`account` and `tokens` are application services. The binding identifies the
remote account and authorization scope. Token refresh under that same binding
is allowed. Literal `authorization_token` through `fromJson` is extracted into
a private resolver and requires the same kind of binding. Authless servers are
valid. OAuth acquisition and refresh policy belong to the application.

Definitions and contracts exclude owned credentials. Resolution errors and
known transport/metadata echoes are sanitized. Keep secrets out of URLs,
unknown options and logs. Returned tool content, signed thinking and opaque
replay may contain private data; those blocks are kept exactly on the backend.
They are not a promise that arbitrary provider-generated content is secret-free.
Only publish `chatHydration` and normal agent events to clients.

## Mixed calls, pauses and recovery

MCP calls and results remain provider-owned `mcp_tool_use` and
`mcp_tool_result` blocks. Discovery listings remain private, including unknown
fields. Matching uses native IDs and server names; it does not share the local
function namespace. A remote tool may have the same name as a registered local
tool without invoking that local executor.

A `tool_use` response may defer remote execution until the application supplies
its local results. `AiAgent` can pause for those local approvals, persist them
and recreate the model with the same profile. It sends local results before the
next invocation and retains the original MCP blocks. A `pause_turn` uses normal
step accounting and durable continuation. These mechanics follow the
[server-tool lifecycle](https://platform.claude.com/docs/en/agents-and-tools/tool-use/server-tools).
No OpenAI-style remote approval is invented for Anthropic MCP.

The 2026 listing is replayed unchanged with its beta on subsequent requests.
You can copy a trusted listing into `toolset.tools` for an explicitly pinned
configuration after completing the current turn, or in a new conversation.
Do not replace the profile of an unfinished turn to pin or change its tools.

For Serverpod, use `ServerpodRunStore(session)` behind the authenticated agent
factory. The original private model profile survives local approvals and
provider-only step-limit restarts. Owner-scoped history and event journals keep
native MCP IDs, inputs, results and credentials out of client snapshots.

Each potentially effectful dispatch checkpoints `ProviderExecutionStarting`
first. Failure, cancellation or a crash after that boundary leaves an
indeterminate outcome and blocks automatic resend, including initial requests.
Inspect external effects and start a new conversation; a matching configuration
does not prove the effect did not occur. This is conservative if a crash occurs
between the checkpoint and the actual send. A validated terminal checkpoint
clears the marker atomically with the continuation state.

Cancellation during credential resolution stops waiting without dispatching;
it cannot cancel the application's underlying OAuth operation. Set OAuth
timeouts in that resolver; the provider HTTP timeout begins at transport work. A request that
was already accepted may still execute remotely. Backend `AgentRunException.cause` retains a sanitized `JsonHttpException` for
HTTP failures, with status and the native transport's redacted request ID.
Error bodies and response headers are dropped. SDK 9.0.1 streaming exceptions
retain status but omit the server request ID; do not mistake a client correlation
ID for it. [Upstream PR #445](https://github.com/davidmigloz/ai_clients_dart/pull/445)
addresses this loss and is separate from a released SDK dependency.
The native transport has no
automatic retries. The SDK-backed stream also makes one send, but pinned SDK
9.0.1 cannot abort while waiting for response headers. Prefer the native client
for request-scoped transport cancellation.

## Preserved options and current limits

Managed tools use immutable `options`, `functionToolOptions`, `container`,
`messageDecorations` and `systemCacheControl` in place of callback mutations.
These preserve the existing function, caching and document configuration paths;
see [hosted-tool options](anthropic-hosted.md#immutable-request-options).
Unknown request fields retain native JSON but do not establish orchestration.

The current pinned MCP result content is a string or an array of text blocks.
Current calls disabled by the server/toolset policy or absent from an explicit
pin fail before accompanying local calls are exposed. Completed historical calls
remain replayable when a later turn narrows its policy. Malformed correlation,
missing required fields, duplicate IDs and unsupported
block kinds fail explicitly. Unfinished MCP calls require a genuine local-tool
turn or `pause_turn`; they cannot silently finish on truncation or refusal.

Live remote execution, OAuth providers, platform/model availability, mobile
rendering and exactly-once effects remain unverified. Inline mid-conversation
tool-addition/removal message directives, Managed Agents and other endpoint
lifecycles are outside this integration. Explicit raw native APIs remain
available when the application owns the full protocol.

The [MCP field inventory](anthropic-mcp-parameters.md) records the selected
pinned declarations and executable configuration fixture. Its presence is not
evidence of complete Anthropic API coverage.
