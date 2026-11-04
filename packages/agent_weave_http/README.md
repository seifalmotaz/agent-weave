# AgentWeave HTTP

Optional JSON and binary HTTP and JSON SSE transport for native provider adapters. The core
agent package does not depend on HTTP. Together, Vercel Gateway, and Cloudflare share this
transport; protocol-specific completion checks stay in their adapters.

```dart
import 'package:agent_weave_http/agent_weave_http.dart';

final transport = JsonHttpClient(baseUrl: backendBaseUrl);
try {
  final response = await transport.sendJson('/chat', prepare: () async {
    final token = await loadBackendToken();
    return JsonHttpRequest(
      body: {'model': modelId, 'messages': messages},
      headers: {'Authorization': 'Bearer $token'},
    );
  });
  // response preserves status, headers and bytes for this invocation.
} finally {
  transport.close();
}
```

This is a provider-author recipe: supply the application-specific functions and
values above on the backend. Do not send credentials to a client application.

`requestTimeout` defaults to two minutes and includes request preparation,
connection and body consumption. Cancellation prevents late preparation from
sending a request. Cancelling a stream subscription aborts that request and
pausing it pauses consumption. Closing the transport cancels its own active
requests. An injected `http.Client` remains caller-owned; other clients using it
are not closed. Actual I/O cancellation requires an injected client to honor
`http.AbortableRequest`; an accepted remote operation cannot be rolled back.

`send` supports GET and byte request bodies for provider discovery and binary payloads.

`streamJson` emits `JsonSseData` with JSON, event name, ID and response headers,
and a separate `JsonSseDone` for `[DONE]`. It handles split UTF-8, CRLF and
multiline data. It rejects malformed JSON and unfinished frames. It does not
interpret a provider's finish reasons or retry POST requests. Redirects are
disabled to keep request credentials on the configured endpoint.

`JsonHttpException` omits response data from its printable message. Its optional
immutable details and headers are trusted-backend diagnostics; error bodies
are bounded to 64 KB. Provider adapters remain responsible for credential
redaction and their own protocol semantics.
