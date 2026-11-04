# Dart Frog

`agent_weave_dart_frog` exposes native Dart Frog handlers for streaming chat,
owner-scoped history, and typed generation. Add `agent_weave`,
`agent_weave_dart_frog`, and `dart_frog` to your application dependencies.

The following complete example runs without a provider key:

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_dart_frog/agent_weave_dart_frog.dart';
import 'package:dart_frog/dart_frog.dart';

Future<void> main() async {
  final token = Platform.environment['DEMO_TOKEN'];
  if (token == null || token.isEmpty) {
    stderr.writeln('Set DEMO_TOKEN to run this local demonstration.');
    exitCode = 1;
    return;
  }
  final handler = chatHandler<void>(
    agent: AiAgent<void>(model: const OfflineModel()),
    authenticate: (context) =>
        context.request.headers['authorization'] == 'Bearer $token'
        ? (ownerId: 'demo-user', context: null)
        : null,
  );
  final server = await serve(handler, InternetAddress.loopbackIPv4, 8080);
  print('Demo listening at http://${server.address.address}:${server.port}');
}

final class OfflineModel implements ChatModel {
  const OfflineModel();
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    yield const TextDelta('Hello from the offline Dart Frog example.');
    yield const ModelFinished();
  }
}
```

For an existing Dart Frog application, return the handler's response from your route. Authentication must
verify the request and supply the owner from trusted server-side identity, not
from JSON. The handler accepts POST chat requests and GET history using
`?threadId=...`, with optional `limit` and `before`. Reconnect to a run
with `?runId=...&offset=...` to replay events after a sequence. The streaming response
uses server-sent events. Cancellation follows the Dart stream subscription;
network disconnect detection depends on the HTTP server and intermediaries.

For typed generation, use `generationHandler<C, P, R>` with a
`GenerationTask<P, R>`, the same authentication callback, and a `decode`
function that receives both request parameters and the trusted authenticated
context: `decode: (input, context) => ...`. Use the context to bind any
user-specific parameters rather than trusting identity fields in the body. Both
handlers limit request bodies to 1 MiB
by default; configure `maxRequestBytes` when needed.

Run the offline example from the workspace root:

```sh
DEMO_TOKEN=local-example dart run examples/dart_frog/server.dart
curl -N -H 'Authorization: Bearer local-example' -H 'Content-Type: application/json' \
  -d '{"threadId":"demo","runId":"first","messages":[{"id":"u1","role":"user","content":"Hello"}]}' \
  http://127.0.0.1:8080/
```

The fixed token and fixed owner are for local demonstration only, not production
authentication. The default in-memory store is process-local and is not durable.

Your application owns the agent, store, and provider client lifetimes. Keep any
authenticated context resources valid until the response stream finishes.
Close shared provider clients when the application shuts down.
