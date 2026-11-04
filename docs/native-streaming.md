# Typed native streaming

Use `streamText` to consume typed Dart updates from a stateless run. The final `AgentRunFinished` carries the result of that same run; it does not start a second generation. This offline example uses `ScriptedChatModel`, so it runs without credentials or network access. Replace it with a configured provider model in an application.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

Future<void> main() async {
  // Replace this deterministic model with a configured provider model.
  final model = ScriptedChatModel(
    steps: [
      [const TextDelta('Hello'), const TextDelta('!'), const ModelFinished()],
    ],
  );

  try {
    await for (final update in streamText(model: model, prompt: 'Say hello')) {
      switch (update) {
        case AgentTextDelta(:final text):
          stdout.write(text);
        case AgentRunFinished(:final result):
          print('\nRun status: ${result.status.name}');
        default:
          break;
      }
    }
  } on AgentRunException catch (error) {
    print('Run failed: ${error.message}');
    // error.result contains the partial backend snapshot for recovery.
  } on RunCancelled {
    print('Run cancelled.');
  }
}
```

Run it from the workspace root with `dart run examples/native_streaming.dart`.

## Updates and results

`AgentTextDelta` and `AgentReasoningDelta` carry text and its assistant message ID. `AgentContentPart` carries a non-text part and its offset in the assistant text. `AgentCitation` and `AgentReference` carry typed metadata and their message-local indices. `AgentUsage` reports usage when supplied by the model. Native updates are Dart objects: callers do not parse wire event maps to use this API.

Updates before `AgentRunFinished` are provisional. An `AgentToolCallReady` is a proposed call; it does not prove approval or execution. An `AgentToolResult` identifies a recorded outcome, including executed, denied, skipped and client-resolved calls; its JSON collection values are deeply immutable snapshots. Return JSON values from `Tool.encode`, converting custom Dart objects with your own serializer first. An effect may occur before a later failure or cancellation, so do not infer rollback from a missing final update. The final result follows committed completion or interruption and includes the status, messages, usage and any interrupts.

The updates and `AgentResult` are **backend** data. Tool arguments, results, reasoning and the final result can contain private information; the result can also contain private provider continuation state. Use the existing `chatHydration` projection when serving UI history, and apply your application's authorization and data-handling rules. Native streaming provides typed access independently of wire-map parsing; the runtime still maintains its existing wire event journal, and no optional package extraction is implied.

## Failures and cancellation

A classified runtime failure throws `AgentRunException`. Precondition, setup or storage failures can propagate their original exception, matching `generate`. Its safe `message` and `code` are suitable for reporting; `result` provides the partial backend result, and the private cause is for trusted diagnostics. A caller-provided `CancellationToken` can cancel a run and yields `RunCancelled` after cleanup. Cancelling the stream subscription stops delivery and requests cleanup; the closed subscription does not receive a later cancellation error. Custom models and tools must honor cancellation; underlying application work can continue if it cannot be cancelled. Neither cancellation mechanism proves that a dispatched remote provider effect stopped.

## Stateful agents and approvals

For resumable approvals, persistent threads or typed application context, use `AiAgent<C>.stream` with a `ChatRequest`, trusted `ownerId`, and trusted `context`. Reuse the agent's store when resuming. The stateless `streamText` helper does not expose its internal store for a later resume. A finished update can have `RunStatus.interrupted`; inspect `result.interrupts` and obtain the user's decision before resuming. Each `ToolInterrupt` provides `approve()`, `reject()`, or, for a client-executed tool, `resolve(output)` or `cancel()` as appropriate. Provider approvals may also accept a reason; editing arguments applies only to supported local approvals.

Resume by issuing another `agent.stream` call with the same thread ID and trusted owner/context, a new run ID, the interrupted run's ID as `parentRunId`, and the collected typed answers in `ChatRequest.resume`. Collect the entire approval batch in your application flow and show only authorized details to the user. The runtime validates the batch and stored tool/model contracts before proceeding. A pause is not a tool result and denial is not a local execution.
