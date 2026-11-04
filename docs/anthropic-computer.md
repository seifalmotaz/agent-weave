# Anthropic computer use

`AnthropicComputerTool` connects Anthropic's `computer_toolset_20260801` calls
to a desktop driver you provide. AgentWeave does not provide the desktop or
operate it itself. The [executable example](https://github.com/seifalmotaz/agent-weave/blob/main/examples/anthropic_computer_demo.dart)
uses the native Messages client, an application-owned HTTPS driver and a console
approval for each requested turn. It makes billable Anthropic requests when run.
Choose a model that supports the toolset using the [official computer-use
documentation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool).

Set `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `COMPUTER_DRIVER_URL`,
`COMPUTER_DRIVER_TOKEN` and `COMPUTER_ENVIRONMENT_ID` in the backend
environment. Run `dart run examples/anthropic_computer_demo.dart "your task"`.
The sample uses the default in-memory run store and fixed local owner and thread
identifiers; it is a single-process demonstration, not durable or multi-user
storage. Production applications must authenticate owners, protect private
conversation state, and configure a suitable store and approval interface.
The console prints action arguments for review, which may contain sensitive data.

## Complete CLI example

Optionally set `ANTHROPIC_VERSION` to select a supported API version.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;
import 'package:agent_weave_http/agent_weave_http.dart';

String environment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) throw StateError('Set $name.');
  return value;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) throw ArgumentError('Pass the task as command arguments.');
  final driverUrl = environment('COMPUTER_DRIVER_URL');
  if (Uri.parse(driverUrl).scheme != 'https') {
    throw ArgumentError('COMPUTER_DRIVER_URL must use HTTPS.');
  }
  final driverToken = environment('COMPUTER_DRIVER_TOKEN');
  final environmentId = environment('COMPUTER_ENVIRONMENT_ID');
  final driver = JsonHttpClient(
    baseUrl: driverUrl,
    requestTimeout: const Duration(seconds: 30),
  );
  final client = anthropic.AnthropicNativeClient.withApiKey(
    apiKey: environment('ANTHROPIC_API_KEY'),
    apiVersion: Platform.environment['ANTHROPIC_VERSION'] ?? '2023-06-01',
  );
  try {
    final agent = AiAgent<void>(
      model: client.chatModel(model: environment('ANTHROPIC_MODEL')),
      tools: [
        anthropic.AnthropicComputerTool<void>(
          environmentId: environmentId,
          needsApproval: true,
          allowedCallers: const ['direct'],
          execute: (call, context) async {
            final response = await driver.sendJson(
              '/execute',
              cancellation: context.cancellation,
              prepare: () => JsonHttpRequest(
                headers: {'Authorization': 'Bearer $driverToken'},
                body: {
                  'environment_id': environmentId,
                  'tool_call_id': context.toolCallId,
                  'idempotency_key': context.idempotencyKey,
                  'call': call.raw,
                },
              ),
            );
            final value = jsonDecode(response.body);
            if (value is! Map<String, dynamic>) {
              throw const FormatException('Expected a driver result object.');
            }
            return anthropic.AnthropicComputerResult.fromJson(value);
          },
        ),
      ],
    );
    var sequence = 0;
    var result = await agent.generate(
      ChatRequest(
        threadId: 'computer-demo',
        runId: 'run-${sequence++}',
        messages: [ChatMessage.user(args.join(' '), id: 'user')],
      ),
      ownerId: 'local-user',
      context: null,
    );
    while (result.status == RunStatus.interrupted) {
      stdout.writeln('Requested actions:');
      for (final interrupt in result.interrupts) {
        stdout.writeln(jsonEncode(interrupt.call.toJson()));
      }
      stdout.write('Approve this turn? [y/N] ');
      final approve = stdin.readLineSync()?.trim().toLowerCase() == 'y';
      final previous = result;
      result = await agent.generate(
        ChatRequest(
          threadId: previous.threadId,
          runId: 'run-${sequence++}',
          parentRunId: previous.runId,
          resume: [
            for (final interrupt in previous.interrupts)
              approve ? interrupt.approve() : interrupt.reject(),
          ],
        ),
        ownerId: 'local-user',
        context: null,
      );
    }
    stdout.writeln(result.text);
  } finally {
    driver.close();
    client.close();
  }
}
```

## Typed actions

The callback receives a sealed `AnthropicComputerAction`. Points are named
Dart records with `x` and `y`; regions have `x0`, `y0`, `x1`, and `y1`.
Scroll direction and click/empty-action kinds are enums. `call.raw` retains the
validated wire shape for a remote driver. Unknown input fields fail before execution.

| Action type | Values |
| --- | --- |
| `AnthropicComputerKey` | `text`, optional `repeat` |
| `AnthropicComputerHoldKey` | `text`, `duration` |
| `AnthropicComputerType` | `text` |
| `AnthropicComputerEmptyAction` | Screenshot, cursor position, mouse down/up `kind` |
| `AnthropicComputerMove` | `coordinate` point |
| `AnthropicComputerClickAction` | Click `kind`, optional `coordinate` and modifier `text` |
| `AnthropicComputerDrag` | `startCoordinate`, `coordinate`, optional modifier `text` |
| `AnthropicComputerScroll` | `amount`, `direction`, optional `coordinate` and modifier `text` |
| `AnthropicComputerWait` | `duration` |
| `AnthropicComputerZoom` | `region` |

Success from screenshot or zoom requires an image result; cursor position
requires nonempty text. Return a typed error for an action that failed. Image
contents and the truth of reported coordinates remain the driver's responsibility.

## Driver contract

The sample sends a JSON POST to `/execute` on your HTTPS driver. It sends a
bearer token, uses a 30-second timeout and passes the run cancellation token;
redirects and automatic retries are disabled. The request contains:

```json
{
  "environment_id": "desktop-1",
  "tool_call_id": "toolu_example",
  "idempotency_key": "stable-per-owner-thread-and-call",
  "call": {"type":"tool_use","id":"toolu_example","toolset_name":"computer","name":"screenshot","input":{}}
}
```

Your driver must authenticate the request, bind `environment_id` to the
approved isolated desktop, validate inputs and deduplicate effects using the
idempotency key. Cancellation or timeout does not undo an action already
accepted by the driver. The driver returns an object with `content`, a list of
Anthropic text and image blocks, and optional boolean `is_error`. For example,
`{"content":[{"type":"text","text":"Clicked."}]}` is an acknowledgement;
a failure can be `{"content":[{"type":"text","text":"Action failed."}],"is_error":true}`.
For screenshot and zoom, return an image block, for example with a base64 PNG
source. `AnthropicComputerResult.fromJson` validates this response before the
runtime forwards it. A thrown driver/transport/decoding exception fails the
run; returning `is_error: true` reports a tool failure to Claude so it can
continue.

The runtime executes computer actions in order. After a computer result marks
an error, later executors in that turn do not run. Computer members receive the
prescribed skipped error; ordinary functions receive a generic skipped error.
The next model turn can recover from those results. By default, a turn containing a
computer action requires approval for the whole batch; native call arguments
are read-only. If approval is declined, the application must start a new thread
rather than execute the rejected native turn.

After a pause, recheck the target and current screen before applying approved actions.

The driver owns coordinate validation and conversion, screenshot capture,
image sizing and desktop isolation. Coordinates refer to full screenshots,
including after zoom; AgentWeave does not scale them. Check bounds against the
actual screenshot and enforce action limits before operating the desktop.
For documented action fields, limits, result rules and the pinned SDK projection,
see the [computer contract inventory](anthropic-computer-parameters.md).

Raw native Messages document blocks support provider file IDs in the agent;
the SDK-backed typed `configure` path still cannot decode those IDs until the
upstream SDK change is released. Neither the example nor the contract inventory
establishes live model compatibility or verifies your driver.
