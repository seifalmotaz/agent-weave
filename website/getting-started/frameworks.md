# Connect Flutter and other frameworks

Choose the model's execution location first. A backend keeps provider credentials and tool permissions under server control. An on-device model runs through your own `ChatModel` adapter.

## Flutter with a Serverpod backend

Start the [Serverpod example](serverpod.md), then use its generated client with your application's authentication provider:

```dart
final backend = Client(serverUrl)..authKeyProvider = yourAuthProvider;
final chat = ChatClient(
  threadId: conversationId,
  connection: serverpodConnection(send: backend.ai.chat),
);

final subscription = chat.states.listen(renderConversation);
await chat.sendText('Hello');

// When the owning controller or widget is disposed:
await subscription.cancel();
await chat.dispose();
```

This recipe needs your generated Serverpod `Client`, `ChatClient` from `tanstack_ai_dart`, and `serverpodConnection` from `agent_weave_serverpod_client`. `serverUrl`, `yourAuthProvider`, `conversationId`, and `renderConversation` belong to your application.

The existing Dart client currently requires a workspace Git override. Read [compatibility](../compatibility.md) before installing the native bridge in another project.

## Flutter with a local model

Implement [ChatModel](../providers.md) around the local model library. Use the core `agent_weave` package without importing Serverpod. Propagate cancellation to the model operation and emit exactly one `ModelFinished` after a successful invocation.

A local model that cannot call tools must report `ModelCapabilities(tools: false)`. The runtime checks declared capabilities before submitting a request.

Do not ship a private hosted-provider key inside a Flutter application. A custom local model needs no hosted-provider key.

## Dart Frog, Shelf, or your HTTP framework

The runtime is framework independent. Your route authenticates the user, parses a `ChatRequest`, and forwards the event stream:

```dart
final events = agent.run(
  request,
  ownerId: authenticatedUserId,
  context: applicationContext,
);
final body = events.map((event) => event.toSse());
```

Set `Content-Type: text/event-stream` and prevent proxy buffering. Cancel the stream subscription when the HTTP client disconnects. Derive `ownerId` from authentication and pass a trusted context; never take either from request JSON.

This is a transport recipe, not a dedicated Dart Frog or Shelf integration package. Translate `body` into your framework's streaming response type. The first-party route implementation is [AgentChatRoute in the repository](https://github.com/seifalmotaz/agent-weave/blob/main/packages/agent_weave_serverpod/lib/src/chat_route.dart).

## Official TanStack clients

The official JavaScript client can use `fetchServerSentEvents` against an `AgentChatRoute`. The runtime and native bridge have interoperability tests against pinned client versions. This does not claim compatibility with the Vercel AI SDK wire protocol. Check the exact tested versions and limits in [compatibility](../compatibility.md).
