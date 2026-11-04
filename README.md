# AgentWeave

Build AI applications in Dart with a Serverpod backend and Flutter or TanStack
AI clients. Define typed tools, stream responses, pause for approval, and keep
conversation history on your server.

AgentWeave is independent and unofficial. It is not maintained or endorsed by
TanStack, OpenAI, or Serverpod.

**Development version.** The packages are not published to pub.dev yet. Start
from this workspace. See [coverage and limits](docs/compatibility.md) before
using it in production.

## Packages

| Package | Use it for |
| --- | --- |
| [`agent_weave`](packages/agent_weave) | Provider contracts, agent loops, typed tools, approvals, generation tasks, and protocol events |
| [`agent_weave_anthropic`](packages/agent_weave_anthropic) | Native Anthropic JSON/SSE, Messages agent loop, private replay, cache controls, and cancellation |
| [`agent_weave_ollama`](packages/agent_weave_ollama) | Local Ollama chat, typed options, embeddings and native NDJSON |
| [`agent_weave_dart_frog`](packages/agent_weave_dart_frog) | Authenticated Dart Frog chat, history, replay and generation handlers |
| [`agent_weave_http`](packages/agent_weave_http) | Shared JSON HTTP transport for provider adapters |
| [`agent_weave_vercel_gateway`](packages/agent_weave_vercel_gateway) | Vercel AI Gateway Chat and Responses adapters |
| [`agent_weave_cloudflare`](packages/agent_weave_cloudflare) | Workers AI and AI Gateway REST clients and selected model adapters |
| [`agent_weave_together`](packages/agent_weave_together) | Native Together Chat Completions and typed options |
| [`agent_weave_openrouter`](packages/agent_weave_openrouter) | OpenRouter native Chat/Responses, routing, replay and metadata |
| [`agent_weave_openai`](packages/agent_weave_openai) | Responses, Chat Completions, images, audio, Decisions, embeddings, video jobs, realtime, and access to provider resources |
| [`agent_weave_serverpod`](packages/agent_weave_serverpod) | Authenticated HTTP/SSE routes and native endpoint helpers |
| [`agent_weave_serverpod_client`](packages/agent_weave_serverpod_client) | Connect the existing TanStack Dart client to generated Serverpod streaming methods |
| [`agent_weave_serverpod_storage_server`](packages/agent_weave_serverpod_storage_server) | Optional PostgreSQL history, run reservations, and event journals |
| [`agent_weave_serverpod_storage_client`](packages/agent_weave_serverpod_storage_client) | Generated types for the optional Serverpod module |

Requires Dart 3.12.2 or later. The integration targets Serverpod 4.1.0.

## Try the workspace

```sh
git clone https://github.com/seifalmotaz/agent-weave.git
cd agent-weave
dart pub get
dart run examples/basic_chat.dart
```

The first example uses an offline provider. It needs no API key and makes no
paid requests. See [the Serverpod example](examples/serverpod/README.md) for a
backend with a database, HTTP streaming, and generated Dart endpoints.

## Define an agent

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

final client = openai.OpenAIClient.fromEnvironment();
final agent = AiAgent<void>(
  model: openai.OpenAIResponsesModel(
    client: client,
    model: 'gpt-5.4-nano',
  ),
  instructions: 'Answer briefly.',
  maxSteps: 8,
  maxOutputTokens: 512,
);

// Derive ownerId from backend authentication, never from the request body.
final events = agent.run(
  ChatRequest(
    threadId: 'conversation-1',
    runId: 'run-1',
    messages: [ChatMessage.user('Hello', id: 'message-1')],
  ),
  ownerId: authenticatedUserId,
  context: null,
);
```

Close the provider client when your application shuts down. Keep OpenAI keys
on the backend. Use the provider import prefix because provider SDK types can
share names with core types.

## Connect Flutter through Serverpod

```dart
final chat = ChatClient(
  threadId: 'conversation-1',
  persistence: const ChatPersistenceOptions.server(),
  connection: serverpodConnection(
    send: serverpodClient.ai.chat,
    loadHistory: serverpodClient.ai.history,
  ),
);

final subscription = chat.states.listen(renderConversation);
await chat.attach(); // Restore server-owned messages and pending approvals.
await chat.sendText('Hello');

// At disposal:
await subscription.cancel();
await chat.dispose();
```

The generated Serverpod client handles authentication and its WebSocket.
AgentWeave handles conversion to the existing TanStack Dart client protocol.
For JavaScript, use the official client's `fetchServerSentEvents` against an
`AgentChatRoute` HTTP endpoint.

## Learn and contribute

[Browse the documentation site](https://seifalmotaz.github.io/agent-weave/).

- [Acceptance roadmap and open work](ROADMAP.md)
- [Dart API, typed results, and application recipes](docs/dart-api.md)
- [Dart Frog backend](docs/dart-frog.md)
- [Ollama local models](docs/ollama.md)
- [Architecture and ownership](docs/architecture.md)
- [Typed tools and approvals](docs/tools.md)
- [Provider author guide](docs/providers.md)
- [Documents](docs/documents.md)
- [OpenAI native computer use](docs/computer-use.md)
- [OpenAI capabilities](docs/openai.md)
- [OpenAI hosted tools and images](docs/openai-hosted.md)
- [Anthropic Messages](docs/anthropic.md)
- [Anthropic hosted tools and paused turns](docs/anthropic-hosted.md)
- [Anthropic computer tools](docs/anthropic-computer.md)
- [OpenRouter](docs/openrouter.md)
- [Cloudflare Workers AI and AI Gateway](docs/cloudflare.md)
- [Together Chat Completions](docs/together.md)
- [Vercel AI Gateway](docs/vercel-gateway.md)
- [Compatibility and limitations](docs/compatibility.md)
- [Validation evidence](docs/validation.md)
- [Upstream updates](docs/updating.md)
- [Contribution guide](CONTRIBUTING.md)
- [Coding-agent entry point](AGENTS.md) and [LLM index](llms.txt)

Run `dart run tool/check.dart` for the normal checks. Paid provider tests are
separate and opt-in.
