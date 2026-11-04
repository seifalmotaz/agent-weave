# agent_weave_serverpod_client

Connect a generated Serverpod endpoint returning Stream<String> to the TanStack AI Dart client with `serverpodConnection(send: backend.ai.chat)`. Provider credentials do not belong in Flutter.

Development version, not published to pub.dev yet. Requires Dart 3.12.2 or later.

See the [workspace guide](https://github.com/seifalmotaz/agent-weave),
[compatibility limits](https://github.com/seifalmotaz/agent-weave/blob/main/docs/compatibility.md),
and [Serverpod example](https://github.com/seifalmotaz/agent-weave/tree/main/examples/serverpod).

Independent and unofficial. Not endorsed by TanStack, OpenAI, or Serverpod.

## Restore server history

```dart
final chat = ChatClient(
  threadId: conversationId,
  persistence: const ChatPersistenceOptions.server(),
  connection: serverpodConnection(
    send: backend.ai.chat,
    loadHistory: backend.ai.history,
  ),
);
await chat.attach();
```

Register matching client tool schemas for typed approval restoration. The full
[runnable approval flow](https://seifalmotaz.github.io/agent-weave/getting-started/serverpod/#run-an-approval-across-process-restarts)
uses separate client processes and survives a graceful backend restart. The
loader decodes full history JSON; supply `hydrate` instead for custom paging.


## Read and resolve provider approvals

Import this package alongside `tanstack_ai_dart`. The same helper works with
`serverpodConnection` or an HTTP connection:

```dart
final approval = chat.getInterrupts().single.providerApproval;
if (approval != null && approval.canResolve) {
  print('${approval.serverLabel}: ${approval.toolName}');
  print(approval.arguments);
  await approval.approve(reason: 'Reviewed');
}
```

This snippet assumes one pending approval; render all returned interrupts for a
batch. Call an action only after the owner chooses. Use `reject(reason: ...)` to decline. These methods stage a generic interrupt
decision; observe `chat.states` for the resumed answer or error. They do not
execute a local tool. Arguments are an immutable snapshot, and provider-native
request IDs remain on the backend. Use the current snapshot after reconnecting.
See [MCP approvals](https://seifalmotaz.github.io/agent-weave/openai-mcp/) for
backend setup, credential binding and uncertain-execution recovery.
