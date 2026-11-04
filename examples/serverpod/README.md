# Run the Serverpod example

The example provides a PostgreSQL-backed agent, a native streaming endpoint,
and a standard HTTP/SSE route. By default, it uses an offline model and makes no paid requests.

From the repository root:

```sh
dart pub get
cp examples/serverpod/agent_weave_demo_server/config/passwords.example.yaml \
  examples/serverpod/agent_weave_demo_server/config/passwords.yaml
cd examples/serverpod/agent_weave_demo_server
AGENT_WEAVE_DEMO_MODE=true dart run bin/main.dart --apply-migrations
```

Serverpod manages the embedded development PostgreSQL configured in
`config/development.yaml`. The API listens on 8080 and the HTTP web server on
8082. If these ports are in use, change your local development configuration.

Use the explicitly enabled local demo credential only for development:

```sh
curl -N http://localhost:8082/api/chat \
  -H 'Authorization: Bearer agent-weave-local-demo' \
  -H 'Content-Type: application/json' \
  -d '{"threadId":"demo","runId":"first","messages":[{"id":"u1","role":"user","content":"Hello"}]}'
```

You should receive `RUN_STARTED`, text events, and `RUN_FINISHED`. Reusing
`runId` is rejected. Use a new ID for the next turn.

Set `AGENT_WEAVE_USE_OPENAI=true` and `OPENAI_API_KEY` in the backend
environment to use OpenAI. The optional
`OPENAI_MODEL` overrides the example model. Provider calls incur charges.

For production, replace the demo authentication handler with your application's
authentication. Leave `AGENT_WEAVE_DEMO_MODE` unset. Configure the production
database, TLS, and host settings for your deployment.

## Native Flutter connection

Use the generated client with your application's `ClientAuthKeyProvider`:

```dart
final backend = Client(serverUrl)..authKeyProvider = yourAuthProvider;
final chat = ChatClient(
  threadId: conversationId,
  connection: serverpodConnection(send: backend.ai.chat),
);
```

Subscribe to `chat.states` in your Flutter state-management layer. Cancel that
subscription and dispose the chat client when its owning widget/controller is
disposed. This repository does not impose a Flutter state-management package.

## Run integration tests

```sh
# From the repository root, install the pinned official JS interop client:
npm ci --prefix tool/interop --ignore-scripts
cd examples/serverpod/agent_weave_demo_server
dart test test/integration
```

The tests use an isolated embedded PostgreSQL database. They cover native
endpoint authentication, a real generated-client WebSocket, HTTP/SSE, history,
replay, owner isolation, concurrent reservations, and the official JavaScript
client against the actual Serverpod chat and generation routes. Node.js 22 or
later is required for that interop check.
