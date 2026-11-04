# agent_weave

Provider-independent Dart agent runtime. Start with `AiAgent<C>`, implement `ChatModel` for a custom provider, and use `Tool<I, O, C>` for schema-validated tools.

Use `streamText` for typed incremental updates and an `AgentRunFinished` result
from the same execution. Stateful agents use `AiAgent.stream`, retaining typed
approvals and the existing store. `AiAgent.run` serves existing JSON clients.
See the [native streaming guide](https://seifalmotaz.github.io/agent-weave/native-streaming/)
and run `dart run examples/native_streaming.dart` from the workspace.

Development version, not published to pub.dev yet. Requires Dart 3.12.2 or later.

See the [workspace guide](https://github.com/seifalmotaz/agent-weave),
[compatibility limits](https://github.com/seifalmotaz/agent-weave/blob/main/docs/compatibility.md),
and [Serverpod example](https://github.com/seifalmotaz/agent-weave/tree/main/examples/serverpod).

Independent and unofficial. Not endorsed by TanStack, OpenAI, or Serverpod.
