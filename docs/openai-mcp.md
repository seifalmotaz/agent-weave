# Approve remote MCP tools

Use `OpenAIResponsesModel` with `mcpTools` for provider-executed MCP calls.
The runtime pauses on a returned approval request. Approval and denial both
continue the provider conversation; neither invokes a local `AgentTool`.

## Run the interactive example

Set `OPENAI_API_KEY` and optionally `OPENAI_MODEL`, then run
`dart run examples/openai_mcp_demo.dart`. This makes billable requests and
contacts the configured MCP server. Repository checks compile this example;
they do not run it. Each proposed tool call requires your CLI decision.
The example uses in-process memory and bounds the number of approval rounds.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

Future<void> main() async {
  final client = openai.OpenAIClient.fromEnvironment();
  try {
    final agent = AiAgent<void>(
      model: openai.OpenAIResponsesModel.native(
        client: client,
        model: Platform.environment['OPENAI_MODEL'] ?? 'gpt-5.4-nano',
        mcpTools: [
          openai.OpenAIMcpTool.fromJson({
            'type': 'mcp',
            'server_label': 'openai_docs',
            'server_url': 'https://developers.openai.com/mcp',
            'require_approval': 'always',
          }),
        ],
      ),
    );
    var result = await agent.generate(
      ChatRequest(
        threadId: 'docs',
        runId: 'question',
        messages: [
          ChatMessage.user(
            'Find the OpenAI Responses streaming guide.',
            id: 'u',
          ),
        ],
      ),
      ownerId: 'local-demo',
      context: null,
    );
    for (
      var round = 0;
      round < 4 && result.status == RunStatus.interrupted;
      round++
    ) {
      final answers = <ResumeAnswer>[];
      for (final interrupt in result.interrupts) {
        final call = interrupt.call as ProviderApprovalCall;
        print('${call.serverLabel}: ${call.name} ${call.arguments}');
        stdout.write('Approve this request? Type yes, otherwise deny: ');
        answers.add(
          stdin.readLineSync() == 'yes'
              ? interrupt.approve()
              : interrupt.reject(reason: 'Declined in the CLI'),
        );
      }
      result = await agent.generate(
        ChatRequest(
          threadId: result.threadId,
          runId: 'decision-$round',
          parentRunId: result.runId,
          resume: answers,
        ),
        ownerId: 'local-demo',
        context: null,
      );
    }
    print('${result.status.name}: ${result.text}');
  } finally {
    client.close();
  }
}
```

For an offline fixture, run `dart run examples/review_cases/openai_mcp.dart`.
It exercises two configured servers, approval and denial, recreated agents,
credential rotation, owner isolation, changed configuration and a real Dart
client over loopback HTTP. It does not execute a remote tool.

## Configure servers and credentials

Each tool has a unique `server_label`. Use a `server_url`, `tunnel_id`, or
legacy `connector_id`. The provider and model determine address availability.
`OpenAIMcpTool` accepts the pinned SDK's `McpTool`; `fromJson` preserves native
options not represented by that SDK, including allowed-tool filters,
`require_approval` policies, deferred loading and future JSON fields.
Configured MCP tools cannot be injected or replaced through `configure`.
When using MCP, declare other hosted tools through `hostedTools` as well;
`configure` cannot add extra tools. Pending approvals bind the whole ordered
MCP configuration and hosted-tool set, including credential identities.

Keep credentials separate from the persisted configuration. Construct the model
for the authenticated owner and resolve that owner's credential on each request:

```dart
final mcp = openai.OpenAIMcpTool.fromJson(
  {
    'type': 'mcp',
    'server_label': 'support',
    'server_url': 'https://support.example.com/mcp',
    'require_approval': 'always',
  },
  credentialBindingId: account.stableAuthorizationIdentity,
  credentials: () async => openai.OpenAIMcpCredentials(
    authorization: await tokens.accessTokenFor(authenticatedOwner, account),
  ),
);
```

`account` and `tokens` are application services. Derive the owner from backend
authentication. The binding identifies the account and authorization scope;
change it when that authority changes. Refreshing a token for the same binding
is allowed. Literal `authorization` and `headers` are also accepted with a
binding ID and extracted into private request-time credentials.

`definition` and `contract` omit these credentials. Known MCP credentials are
also removed from response configuration metadata. Keep secrets out of URLs,
unknown options and application logs. Call arguments and native results can
contain private data and remain in backend history; only use `chatHydration`
for a client snapshot. The backend `AgentResult` includes private replay.

## Resume a saved decision

Use `ServerpodRunStore(session)` for durable history, recreating the agent with
the same nonsecret configuration and credential binding on each request.
For complete database setup, see the [Serverpod example](../examples/serverpod/README.md).
The approved or rejected run supplies a new run ID and the interrupted parent.
Resolve every pending interrupt once. `approve(reason: ...)` and
`reject(reason: ...)` accept an optional string; editing provider arguments is
unsupported. A changed server or policy fails before local effects or provider
continuation. Cancelling a pending approval before continuation preserves it and does not
send denial. Cancellation after dispatch can instead leave the run indeterminate.

Both pinned clients expose these as **generic interrupts** without registering
a fake local tool. Use the same payload shape in Dart and JavaScript:

```dart
final interrupt = chat.getInterrupts().single;
interrupt.resolveInterrupt({'approved': false, 'reason': 'Outside the scope'});
```

```javascript
const [interrupt] = chat.getInterrupts();
interrupt.resolveInterrupt({approved: false, reason: 'Outside the scope'});
```

Read `metadata.providerApproval` for the provider and server label. This differs
from the [typed local-tool JavaScript approval API](tools.md#edit-tool-arguments-in-a-client).
Never send raw provider request IDs or replay from a client. The runtime maps
its public local call IDs to private MCP approval IDs.

## Failure and continuation boundaries

The adapter reconciles terminal MCP discovery, calls, approvals and matching
approval-response echoes before exposing a call or executing a local tool.
Echoes must match the saved decision and are retained for audit without sending
the same approval response twice on later turns.
Native approval responses follow their source output in ordered, stateless
replay with `store: false`. See the [official MCP guide](https://developers.openai.com/api/docs/guides/tools-connectors-mcp)
for the provider protocol; fixture coverage does not establish live acceptance.

Provider continuations consume normal model steps. In a mixed local/provider
turn, local calls wait for the complete approval batch to validate before effects.
The runtime checkpoints before a possible provider execution. If a request fails,
is cancelled, or loses its authoritative checkpoint after it might have started,
the thread becomes indeterminate and cannot automatically resend. This guard
is conservative once a decision batch is accepted, even if the failure occurs
before a network send can be confirmed. Preserve its
history, reconcile external effects, and start a new thread when needed.
A denial continues normally. The SDK's streaming path does not automatically retry.

Explicitly setting `require_approval: never` or selective policies can authorize
remote execution without a pause. Neither the runtime nor a cancelled network
request can undo a remote effect. Live MCP servers, OAuth, tunnel/connector
availability, remote idempotency and provider execution quality remain unverified.
See [validation](validation.md) for offline and durable test evidence.
