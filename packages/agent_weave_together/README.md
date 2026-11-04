# Together for AgentWeave

Native Together Chat Completions integration. `TogetherChatModel` plugs into the
existing `AiAgent`; the agent owns tool execution, approvals and history.
Provider options are immutable snapshots. Image, video, audio, tools and JSON
schema support depend on the chosen Together model. Inline audio must be WAV;
documents and legacy function calls are unsupported by the agent adapter.

```dart
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_together/agent_weave_together.dart';

Future<void> main() async {
  final key = Platform.environment['TOGETHER_API_KEY'];
  final modelId = Platform.environment['TOGETHER_MODEL'];
  if (key == null || modelId == null) {
    throw StateError('Set TOGETHER_API_KEY and TOGETHER_MODEL.');
  }
  final client = TogetherClient(apiKey: key);
  try {
    final model = TogetherChatModel(client: client, model: modelId,
        options: TogetherChatOptions(temperature: 0.3));
    await for (final event in model.stream(
      ModelRequest(messages: [ChatMessage.user('Hello', id: '1')]),
      cancellation: CancellationToken(),
    )) {
      if (event is TextDelta) stdout.write(event.text);
    }
  } finally {
    client.close();
  }
}
```

Create a Together account and choose a model available to that account. Keep
keys server-side. `TogetherClient.createChat` and `streamChat` accept native
JSON requests and return native JSON metadata; use these for `n > 1` or other
native fields. `streamChat` forces streaming. Neither method retries POSTs.
A caller-supplied HTTP client remains caller-owned. Never log request or response
payloads containing private data.

Offline tests cover request serialization and streaming behavior; no paid live
Together calls or model-specific capability checks have been performed. Together
can change model support independently of this adapter.

Requests time out after two minutes by default; set `requestTimeout` on the
client to change this. A timeout aborts the individual HTTP request and throws
`TogetherException`; user cancellation throws `RunCancelled`. Streaming reads
through `[DONE]` or EOF so usage events following the finish reason are kept.

Use `TogetherException.statusCode`, `requestId` and immutable `details` only in
trusted backend code. Error bodies are omitted by `toString()`; diagnostics are
bounded to 64 KB and unavailable for non-JSON or oversized HTTP error bodies.
The high-level API wraps provider failures in `AgentRunException.cause`.

A normal `length` finish returns partial text and the finish reason. Incomplete
tool calls fail before execution. Raw native methods retain prompt echoes,
logprobs, warnings and other JSON metadata; these fields are not normalized into
`AgentResult`. See the [complete guide](https://seifalmotaz.github.io/agent-weave/together/).

Cancelling a native stream subscription aborts that request; pausing the
subscription pauses stream consumption. Other requests on the client remain usable.
