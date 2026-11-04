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
