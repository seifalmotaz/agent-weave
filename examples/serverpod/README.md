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
  persistence: const ChatPersistenceOptions.server(),
  connection: serverpodConnection(
    send: backend.ai.chat,
    loadHistory: backend.ai.history,
  ),
);
await chat.attach();
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

## Run an approval across process restarts

Start the offline backend as above. In a separate terminal in
`examples/serverpod/agent_weave_demo_server`, run:

```sh
dart run example/approval_workflow.dart start approval-demo-1
```

The client asks the deterministic demo model to greet Ada. It stops before the
registered tool executes and exits with `PAUSED`. The database owns the pending
approval. You may stop the backend and restart it with the same development
database directory before continuing. Do not delete `.serverpod/development`.

After making an explicit decision, start a fresh client process:

```sh
dart run example/approval_workflow.dart approve approval-demo-1
# Or reject instead:
# dart run example/approval_workflow.dart reject approval-demo-1
```

Approval completes with `Hello Ada`; rejection completes without invoking the
greeting. Repeating a decision after completion fails clearly. Use a new thread
ID for a new demonstration. An optional final argument selects a different
server URL if your local ports differ.

The complete [CLI source](https://github.com/seifalmotaz/agent-weave/blob/main/examples/serverpod/agent_weave_demo_server/example/approval_workflow.dart)
registers the matching client-side tool schema, enables
`ChatPersistenceOptions.server()`, supplies `loadHistory`, and calls `attach()`.
All four are necessary for typed approval restoration. `canResolve` alone is
not proof of matching: the example also checks the interrupt kind and tool name.
The local demo credential is for this explicitly enabled example only.

`loadHistory` returns the whole snapshot. For paging, provide a custom `hydrate`
callback and a corresponding paged server endpoint; do not configure both.
Supplying a loader without server persistence leaves a ChatClient ephemeral.

The automated `test/integration/restart_test.dart` runs fresh server and client
processes against a temporary PostgreSQL data directory and verifies restored
approval plus repeated-decision rejection. This verifies graceful restart. It
does not prove recovery at arbitrary crash points or exactly-once effects in
an unrelated external service. Keep external operations idempotent.

## Generate OpenRouter images

The optional `createOpenRouterImageRoute` factory in
`agent_weave_demo_server/lib/src/ai/openrouter_image_route.dart` uses your existing
authentication, fixes model/count policy on the server and persists native image
results. Register it explicitly with an application-owned OpenRouter client;
the default offline backend does not enable paid image generation.
See the [dedicated Image API guide](https://seifalmotaz.github.io/agent-weave/openrouter-image-api/)
for the complete factory and streaming/result distinctions.

The integration fixture `test/integration/openrouter_image_api_test.dart` uses
actual local HTTP, PostgreSQL and the official JavaScript generation client.
It tests server-owned policy and authentication, multiple final images, a
single-request JSON fallback and failed generation without successful output.
The provider is a loopback fixture; it makes no paid request.
