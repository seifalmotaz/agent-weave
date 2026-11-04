# Use Together Chat Completions

`agent_weave_together` provides a native Together Chat Completions client and a
`ChatModel` adapter. The agent runtime owns tool execution, approvals, and
history. Model support for tools, schemas, images, video, and audio varies.

## Run a backend request

From the workspace root, run `dart pub get`. Save this example as
`examples/together_demo.dart`. Set `TOGETHER_API_KEY` and `TOGETHER_MODEL` in
your backend environment, choosing a model available to your account. Running
the example makes a paid provider request. Keep the key on the backend.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_together/agent_weave_together.dart' as together;

Future<void> main() async {
  final key = Platform.environment['TOGETHER_API_KEY'];
  final modelId = Platform.environment['TOGETHER_MODEL'];
  if (key == null || modelId == null) {
    throw StateError('Set TOGETHER_API_KEY and TOGETHER_MODEL.');
  }
  final client = together.TogetherClient(apiKey: key);
  try {
    final model = together.TogetherChatModel(
      client: client,
      model: modelId,
      options: together.TogetherChatOptions(temperature: 0.3),
    );
    final result = await generateText(model: model, prompt: 'Say hello.');
    print(result.text);
  } finally {
    client.close();
  }
}
```

Run `dart run examples/together_demo.dart` to print the response. The same
model works with `AiAgent` and its registered tools, approvals, schema output,
and history. See [tools and approvals](tools.md) and the
[Dart API guide](dart-api.md).

## Choose typed options or native JSON

See [all reviewed request fields](together-options.md) for their Dart entry points.

`TogetherChatOptions` snapshots its input values and exposes typed options,
including enums for compliance, context length behavior, and reasoning effort.
`logprobs` is an integer from 0 to 20. The runtime owns `max_tokens` through
`ModelRequest.maxOutputTokens` or the corresponding agent setting. The agent
adapter requests one choice (`n: 1`).

For multiple choices (`n > 1`), legacy `function_call`, or other native fields,
use `TogetherClient.createChat` or `streamChat` with native JSON. These methods
return native JSON; `streamChat` sets `stream: true`. The agent adapter does not
normalize legacy function calls. Native JSON access does not establish support
for every Together operation.

The agent adapter rejects document inputs. Inline audio must be WAV. Image,
video, audio, tool, and schema acceptance depends on the selected model.

## Handle requests and errors

The default request timeout is two minutes for the entire HTTP request. Set
`requestTimeout` on `TogetherClient` to change it. Timeout and a user-provided
`CancellationToken` abort the HTTP request. Cancelling a native stream
subscription also aborts that request without closing the shared client. The client does not automatically
retry POST requests. Close the `TogetherClient` when finished. If you inject an
HTTP client, you own and must close that HTTP client.

A `TogetherException` provides `statusCode`, `requestId`, and optional JSON
`details` to trusted backend code. Its `toString()` omits provider response
bodies. Do not expose a provider error's cause or details to the UI; they can
contain private data. Protect logs and avoid logging request or response bodies.

A `length` finish returns partial text with `finishReason: 'length'`. Truncated
tool calls fail rather than execute. Choose output limits appropriate to your
application and handle partial results.

## Review the pinned contract

The AST-generated [chat inventory](together-chat-inventory.json) records 27
top-level request fields and their dispositions for the pinned declaration. It
is an inventory, not a certification of nested fields, response handling,
lifecycle, models, or other operations. The pin is in
`tool/contracts/together/source.json`; dispositions are in
`tool/contracts/together/coverage.json`. Headers and query parameters are
captured as maps; this does not claim coverage of every operation.

From the repository root, install the inventory tool dependencies and run the
checks:

```sh
npm ci --prefix tool/interop --ignore-scripts --no-audit --no-fund
dart run tool/together_contract.dart
node tool/interop/inventory.mjs --check
```

`node tool/interop/inventory.mjs --upstream` compares the pinned files with
upstream main. Review changes before running `--write` to update the inventory.
Offline fixtures cover selected requests and streams. No live Together request,
model acceptance, or billing has been verified.

The normal checks include an independent, runnable offline consumer:

```sh
dart --enable-asserts run examples/review_cases/together.dart
```

It exercises a real loopback HTTP service, schema output, tool approval and
continuation, private reasoning replay, partial output and backend diagnostics.
Response log probabilities, prompt echoes, warnings and arbitrary provider
metadata are available through the raw native client and are not normalized into
`AgentResult`. Message names and URL audio also require native requests.
