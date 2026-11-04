# OpenAI native computer use

Register `OpenAIComputerTool<C>` in `AiAgent.tools` alongside an unchanged
`OpenAIResponsesModel`. The application owns the computer, driver, permissions,
and screenshots; AgentWeave does not control an operating system or browser.
Use a model that supports the Responses computer tool. Running this example
makes paid model requests and sends actions to your driver.

## Complete CLI example

Run `dart pub get` in this workspace. A standalone application also needs
the `agent_weave_http` dependency for this driver example. Set `OPENAI_API_KEY`,
`OPENAI_COMPUTER_MODEL`, `COMPUTER_ENVIRONMENT_ID`, `COMPUTER_DRIVER_URL`, and
`COMPUTER_DRIVER_TOKEN`. The environment ID must identify the same stable
computer across the entire thread. `USER` identifies the trusted local CLI
operator. In a server, obtain `ownerId` from authenticated server-side identity,
never from the request body. Save this program as `examples/computer_demo.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

Future<void> main(List<String> args) async {
  String requiredEnv(String name) {
    final value = Platform.environment[name];
    if (value == null || value.trim().isEmpty) throw StateError('Set $name.');
    return value;
  }

  if (args.length != 1 || args.single.trim().isEmpty) {
    throw ArgumentError('Pass one quoted task as the argument.');
  }
  final apiKey = requiredEnv('OPENAI_API_KEY');
  final modelId = requiredEnv('OPENAI_COMPUTER_MODEL');
  final environmentId = requiredEnv('COMPUTER_ENVIRONMENT_ID');
  final driverUrl = Uri.parse(requiredEnv('COMPUTER_DRIVER_URL'));
  final driverToken = requiredEnv('COMPUTER_DRIVER_TOKEN');
  if (driverUrl.scheme != 'https' ||
      driverUrl.host.isEmpty ||
      driverUrl.userInfo.isNotEmpty ||
      driverUrl.hasFragment) {
    throw ArgumentError(
      'COMPUTER_DRIVER_URL must be an HTTPS URL without credentials or fragment.',
    );
  }
  // The CLI operator is the trusted identity, not a request-body field.
  final ownerId = requiredEnv('USER');
  final driver = JsonHttpClient(
    baseUrl: driverUrl.origin,
    requestTimeout: const Duration(seconds: 30),
  );
  final client = openai.OpenAIClient(
    config: openai.OpenAIConfig(
      authProvider: openai.ApiKeyProvider(apiKey),
      retryPolicy: const openai.RetryPolicy(maxRetries: 0),
    ),
  );
  try {
    final agent = AiAgent<void>(
      model: openai.OpenAIResponsesModel(client: client, model: modelId),
      tools: [
        openai.OpenAIComputerTool<void>(
          environmentId: environmentId,
          execute: (call, context) async {
            context.cancellation.throwIfCancelled();
            if (!context.approved) throw StateError('Approval required.');
            final response = await driver.sendJson(
              driverUrl.path.isEmpty ? '/' : driverUrl.path,
              query: driverUrl.queryParametersAll,
              cancellation: context.cancellation,
              prepare: () => JsonHttpRequest(
                headers: {'Authorization': 'Bearer $driverToken'},
                body: {
                  'environment_id': environmentId,
                  'idempotency_key': context.idempotencyKey,
                  'actions': [
                    for (final action in call.actions) action.toJson(),
                  ],
                },
              ),
            );
            context.cancellation.throwIfCancelled();
            if (response.statusCode != 200) {
              throw StateError(
                'Computer driver failed (${response.statusCode}).',
              );
            }
            final result = jsonDecode(response.body);
            if (result is! Map ||
                result['environment_id'] != environmentId ||
                result['image_url'] is! String ||
                (result['image_url'] as String).isEmpty) {
              throw const FormatException('Invalid computer driver response.');
            }
            return openai.OpenAIComputerScreenshot.url(
              result['image_url'] as String,
            );
          },
        ),
      ],
    );
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    var result = await agent.generate(
      ChatRequest(
        threadId: 'computer-$id',
        runId: 'run-$id',
        messages: [ChatMessage.user(args.single, id: 'message-$id')],
      ),
      ownerId: ownerId,
      context: null,
    );
    var continuation = 0;
    while (result.status == RunStatus.interrupted) {
      final answers = <ResumeAnswer>[];
      for (final interrupt in result.interrupts) {
        stdout.writeln(
          'Proposed computer call: ${jsonEncode(interrupt.call.arguments)}',
        );
        stdout.write('Approve this entire call and its safety checks? [y/N] ');
        final approved = stdin.readLineSync()?.trim().toLowerCase() == 'y';
        answers.add(approved ? interrupt.approve() : interrupt.reject());
      }
      result = await agent.generate(
        ChatRequest(
          threadId: result.threadId,
          runId: 'run-$id-${++continuation}',
          parentRunId: result.runId,
          resume: answers,
        ),
        ownerId: ownerId,
        context: null,
      );
    }
    stdout.writeln(result.text);
  } on RunCancelled {
    stderr.writeln(
      'Computer run stopped. Inspect the environment before starting a new thread.',
    );
  } finally {
    driver.close();
    client.close();
  }
}
```

Run `dart run examples/computer_demo.dart "Your task"` only after setting up
and securing the driver. Every proposed batch is shown to the operator, who
must enter `y` to approve it and all its safety checks. Any other answer rejects
it. Keep the terminal and environment under the operator's control. The sample
uses an in-memory store and is intended for a single process; durable applications
need an appropriate `RunStore` and authenticated approval UI.

## Driver contract

`COMPUTER_DRIVER_URL` is your HTTPS endpoint, not an AgentWeave or OpenAI
endpoint. This example sends an authenticated JSON POST:

```json
{"environment_id":"desktop-1","idempotency_key":"stable-key","actions":[{"type":"click","button":"left","x":100,"y":200}]}
```

The driver must authorize the caller and environment, validate the entire batch,
revalidate the target and current screen before acting, execute the supplied
SDK action objects in order, and return one **fresh** screenshot after the
complete batch: `{"environment_id":"desktop-1","image_url":"https://..."}`.
It must deduplicate by the supplied idempotency key and preserve a durable record
of partial execution. A screenshot URL must be accessible to the model and
correspond to the configured screen coordinates. A driver must stop and report
failure on an invalid action, policy denial, execution failure, or screenshot
failure; it must not fabricate success. The driver client has a 30-second request timeout, observes cancellation, and
rejects redirects to avoid
forwarding its bearer token to another host. Secure the URL, token, images,
logs and environment, and restrict the environment's access and permissions.

`context.idempotencyKey` is stable across approval continuations and scoped to
owner, thread, and tool call. Deduplication belongs to your driver; neither that
key nor this example guarantees exactly-once external effects after a crash.
Neither the driver request nor model request is automatically retried here. A
cancelled or failed in-flight request may already have changed the computer;
inspect its state before taking further action. Cancellation is cooperative:
check `context.cancellation` before and after work and inside your driver where
possible.

## Approval and continuation

The default `ComputerApproval.always` requires approval for every call.
`ComputerApproval.safetyChecks` requires it when the provider supplies safety
checks. Any nonempty checks force human approval under either policy, including
unknown check codes. Approval covers the entire immutable call and all checks;
native arguments cannot be edited. `context.approved` tells the executor that
approval was granted. The application must enforce its own per-action policy and
verify the screen still matches the approved target.

Only validated calls from a terminal completed response are executable; streaming
deltas and incomplete or failed calls are not. Actions are immutable and must be
executed in their given order. Unknown action fields are rejected before the
executor runs. The runtime matches the screenshot output to the
exact provider `call_id` and retains opaque provider replay privately. Keep
stored continuation data private and use the authorized history interface for UI.

A rejection or cancellation stops locally and throws `RunCancelled`; the
continuation is closed with its audit history intact. Start a new thread after
reviewing the actual environment. Never invent a screenshot, result, or safety
acknowledgement to continue a denied call. Do not resume a pending call with a
different environment ID or stale screen: abandon it and start a new thread
with fresh state and approval. A completed model call means generation completed,
not that an action succeeded.

## Options and interoperability

The standard constructor sends the GA tool definition `{"type":"computer"}`.
For the legacy preview protocol, use `OpenAIComputerTool.preview` with positive
`width` and `height` and `environment` set to a `ComputerEnvironment` value:
`browser`, `mac`, `windows`, `linux`, or `ubuntu` (for example,
`openai.ComputerEnvironment.browser`). Both require a stable, nonempty `environmentId` and an application
executor. `OpenAIComputerCall.actions` uses the exported OpenAI SDK action
classes; inspect their types or serialize each action with `toJson()` as above.

Return `OpenAIComputerScreenshot.url(url)` or
`OpenAIComputerScreenshot.fileId(id)` with exactly one nonempty source. Both
accept `detail: openai.ImageDetail.original` when supported by the model.
Safety checks are acknowledged only after approval; support for nonempty
acknowledgements on the GA server is not guaranteed.

See OpenAI's [computer use guide](https://developers.openai.com/api/docs/guides/tools-computer-use)
and [driver integration](https://developers.openai.com/api/docs/guides/tools-computer-use-integration)
for provider requirements. Local fixtures and compilation do not verify a live
model, driver, remote actions, or billing.

## TanStack client approval UI

Native computer approvals use the generic interrupt API with the server's
read-only argument snapshot and response schema. Resolve an interrupt with
`{approved: true}` or `{approved: false}`. The native Dart agent API provides
`interrupt.approve()` and `interrupt.reject()`. Function-tool registration on
a JavaScript client uses a different approval schema that permits argument
edits; use the generic schema supplied by this native interrupt. Local tests
exercise both resolutions with the pinned official JavaScript client and
rehydrate its history without exposing private provider state.
