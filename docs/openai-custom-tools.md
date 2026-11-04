# OpenAI Responses custom text tools

Use `OpenAICustomTool<C>` when a Responses model should send a text string to an application-owned tool. Your backend supplies the executor, validates its input and controls approval. Custom tools are separate from OpenAI hosted tools and JSON-schema function tools.

## Interactive example

Set `OPENAI_API_KEY` and `OPENAI_CUSTOM_TOOL_MODEL` to a model that supports custom tools, then run `dart run examples/openai_custom_demo.dart`. This makes billable requests. The example reads from a small in-memory ticket table, uses no shell or code evaluator, and asks for a decision before each proposed lookup. It limits the number of approval rounds; a run that reaches the limit stays interrupted.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

Future<void> main() async {
  final key = Platform.environment['OPENAI_API_KEY'];
  final model = Platform.environment['OPENAI_CUSTOM_TOOL_MODEL'];
  if (key == null || key.isEmpty || model == null || model.isEmpty) {
    throw StateError('Set OPENAI_API_KEY and OPENAI_CUSTOM_TOOL_MODEL.');
  }
  final client = openai.OpenAIClient.fromEnvironment();
  try {
    final agent = AiAgent<void>(
      model: openai.OpenAIResponsesModel.native(client: client, model: model),
      tools: [
        openai.OpenAICustomTool<void>(
          name: 'lookup_ticket',
          bindingId: 'local-ticket-lookup-v1',
          description: 'Look up the status of a ticket',
          needsApproval: true,
          format: openai.OpenAICustomToolFormat.grammar(
            r'TICKET-[0-9]+',
            syntax: openai.OpenAICustomGrammarSyntax.regex,
          ),
          execute: (input, context) {
            // Validate model text locally; provider grammar is not authorization.
            if (!RegExp(r'^TICKET-[0-9]+$').hasMatch(input)) {
              return openai.OpenAICustomToolResult.error('Invalid ticket ID.');
            }
            const tickets = {'TICKET-42': 'open'};
            return openai.OpenAICustomToolResult.text(
              tickets[input] ?? 'Ticket not found.',
            );
          },
        ),
      ],
    );
    var request = ChatRequest(
      threadId: 'ticket-demo',
      runId: 'question',
      messages: [ChatMessage.user('Look up TICKET-42.', id: 'user')],
    );
    for (var round = 0; round < 4; round++) {
      AgentResult? finished;
      await for (final update in agent.stream(
        request,
        ownerId: 'local-demo',
        context: null,
      )) {
        if (update case AgentTextDelta(:final text)) stdout.write(text);
        if (update case AgentRunFinished(:final result)) finished = result;
      }
      final result = finished!;
      if (result.status != RunStatus.interrupted) {
        stdout.writeln();
        break;
      }
      if (round == 3) {
        stderr.writeln(
          'Approval round limit reached; the run remains interrupted.',
        );
        break;
      }
      final answers = <ResumeAnswer>[];
      for (final interrupt in result.interrupts) {
        stdout.writeln(
          '\n${interrupt.call.name}: ${interrupt.call.arguments['input']}',
        );
        stdout.write('Approve this lookup? Type yes, otherwise deny: ');
        answers.add(
          stdin.readLineSync() == 'yes'
              ? interrupt.approve()
              : interrupt.reject(),
        );
      }
      request = ChatRequest(
        threadId: result.threadId,
        runId: 'decision-$round',
        parentRunId: result.runId,
        resume: answers,
      );
    }
  } on AgentRunException catch (error) {
    stderr.writeln('${error.code}: ${error.message}');
    exitCode = 1;
  } on RunCancelled {
    stderr.writeln('Run cancelled.');
    exitCode = 1;
  } finally {
    client.close();
  }
}
```

The [offline consumer](https://github.com/seifalmotaz/agent-weave/blob/main/examples/review_cases/openai_custom.dart) runs without a key or network: `dart --enable-asserts run examples/review_cases/openai_custom.dart`. It exercises approval, denial, application validation, private replay and native output with a MockClient. It does not prove live provider acceptance.

## Input and authorization

`OpenAICustomToolFormat.text()` requests unconstrained text. `OpenAICustomToolFormat.grammar` accepts a `regex` or `lark` syntax and native grammar definition. The grammar is sent to the provider as a generation constraint; AgentWeave does not execute the grammar locally. Validate the returned string in your executor before doing work, even if the provider applied a grammar. Use the authenticated `ToolContext` to check the owner's access and pass its idempotency key to an external service that supports one.

The native proposal is represented to the application as a `NativeToolCall` whose arguments contain only `{'input': text}`. Raw provider items and caller fields stay in backend provider replay, not in public call arguments or `chatHydration`. Treat all tool inputs and results as application data, and do not return private `AgentResult` provider state directly to a UI. `needsApproval: true` pauses before invoking the executor; validate the entire decision batch and obtain the person's decision before resuming. Editing custom-tool arguments in an approval is unsupported.

## Results and failure

`OpenAICustomToolResult.text(value)` returns a string. `error(message)` represents an expected failure with an explicit message that the model may see; avoid including secrets. `content([...])` supports native `input_text`, `input_image`, and `input_file` blocks through `OpenAICustomToolContent`:

- `text(text, cache: ...)` includes text.
- `image(detail: ..., imageUrl: ..., fileId: ..., cache: ...)` carries image detail and a URL or file handle. Detail accepts `auto`, `low`, `high` or `original`.
- `file(detail: ..., fileData: ..., fileId: ..., fileUrl: ..., filename: ..., cache: ...)` carries file data, a handle or URL, optional filename and detail (`auto`, `low` or `high`).
- `OpenAICustomPromptCacheBreakpoint(ttl: ...)` sets an explicit cache breakpoint; the optional TTL is `30m` or `12h`.

Each result factory also accepts an optional application-owned `id` and direct `caller` JSON metadata. These values are validated and snapshotted; no provider ID is invented. `fromJson` preserves an explicitly null caller. The adapter sends the returned output as `custom_tool_call_output` with the matching native call ID. The runtime owns `type` and `call_id`; result metadata cannot replace them. `isError` marks the application/runtime result; the native output item contains the output text or content, so phrase an expected error meaningfully for the model. Authorize file handles and URLs in your application; typed content does not grant retrieval permission or validate a remote resource's trustworthiness.

Rejecting or cancelling a **custom-tool approval** produces a safe declined/cancelled output and can continue the native conversation without executing that tool. A returned `OpenAICustomToolResult.error` likewise provides a known error result. An unexpected thrown executor error closes the unfinished native continuation; verify any external effects and start a new conversation rather than automatically rerunning it. A declined or cancelled computer-tool approval still closes the native continuation, including a mixed batch; custom-tool fallback does not change computer-tool semantics. Cancellation of a whole run also does not undo an effect.

## Namespaces, binding and scope

For a native namespace, pass `namespace: OpenAIToolNamespace(name: ..., description: ...)`. When two namespaces use the same native tool name, assign distinct `localName` values so the application's registered tools have unique names. The model uses the native namespace/name while the runtime dispatches the local alias. A stable `bindingId` identifies the executor and its authority; change it when its behavior or authorization scope changes.

Automatic selection supports registered custom tools in namespaces. A forced custom selector accepts exactly `{'type': 'custom', 'name': ...}` and selects a registered top-level custom tool. Forced namespace selection is unsupported. With the pinned `openai_dart` 11.0.1, use `OpenAIResponsesModel.native` or `ResponsesProtocolModel.native` for this selector: the SDK's typed `ResponseToolChoice` union cannot represent `custom`, so the typed transport rejects it during registration. The native transport preserves the selector without changing SDK decoding.

[Upstream PR #451](https://github.com/davidmigloz/ai_clients_dart/pull/451) adds the missing typed selector. It is separate from the workspace's published SDK dependency. Recheck the upstream release and rerun the contract checks before updating that pin.

The runtime binds the complete registered tool profile and model continuation configuration across unfinished turns, before approving or invoking any tool. Recreate an agent with the same profile when resuming. Changed profiles fail before effects. Older unfinished checkpoints without the required contract cannot be reconstructed safely; start a new conversation while retaining completed history. See [approval contracts](approval-contracts.md).

This integration supports direct custom calls. Asynchronous and programmatic custom execution are rejected; unsupported provider features do not become available merely because the underlying SDK has a type. Custom tools and [computer tools](computer-use.md) have distinct continuation contracts. See the [official OpenAI guide](https://developers.openai.com/api/docs/guides/function-calling) for the provider format. Offline fixtures do not prove live model support, grammar acceptance, real external effects, or PostgreSQL restart behavior.
