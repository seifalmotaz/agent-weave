# Run a support workflow without an API key

Run these commands from the cloned workspace after `dart pub get`:

```sh
dart run examples/offline_support.dart
dart run examples/offline_support.dart --approve
```

The first command prints an interrupted result and `Application effects: 0`.
The second starts a fresh demo, pauses, then simulates a human approval. It
prints a completed result, `Application effects: 1`, and `Reference: Support policy`.
Neither command uses a network service or bills a provider.

Each command starts its own `MemoryRunStore`. The approved path recreates the
agent inside the same process with that shared store. It does not restore data
across process restarts. Use the [Serverpod restart example](../examples/serverpod/README.md#run-an-approval-across-process-restarts)
for durable database history.

## Run the complete application

The source below is the checked-in `examples/offline_support.dart`. Copy it to
a Dart file in the workspace and run it with `--approve` for the completed path.

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

const ticketSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'ticket': {'type': 'integer'},
  },
  'required': ['ticket'],
  'additionalProperties': false,
};

final class SupportDesk {
  final _completed = <String, String>{};
  int get escalations => _completed.length;

  String escalate(int ticket, ToolContext<SupportDesk> context) =>
      _completed.putIfAbsent(
        context.idempotencyKey,
        () => 'Ticket $ticket escalated for ${context.ownerId}',
      );
}

Future<void> main(List<String> arguments) async {
  const finalAnswer = 'Ticket 42 is now in the supervisor queue.';
  final desk = SupportDesk();
  final store = MemoryRunStore();
  final tool = Tool<int, String, SupportDesk>(
    name: 'escalate',
    description: 'Escalate a support ticket after approval',
    inputSchema: ticketSchema,
    outputSchema: const {'type': 'string'},
    needsApproval: true,
    decode: (json) => json['ticket'] as int,
    encode: (value) => value,
    execute: (ticket, context) => context.value.escalate(ticket, context),
  );
  AiAgent<SupportDesk> agent(ChatModel model) =>
      AiAgent<SupportDesk>(model: model, store: store, tools: [tool]);
  final paused =
      await agent(
        ScriptedChatModel(
          capabilities: const ModelCapabilities(tools: true),
          steps: [
            [
              const TextDelta('I can escalate ticket 42 for review.'),
              ToolCallReady(
                ToolCall(
                  id: 'escalation',
                  name: 'escalate',
                  arguments: {'ticket': 42},
                ),
              ),
              const TokenUsage(inputTokens: 8, outputTokens: 4),
              const ModelFinished(),
            ],
          ],
        ),
      ).generate(
        ChatRequest(
          threadId: 'support',
          runId: 'proposal',
          messages: [ChatMessage.user('Escalate ticket 42', id: 'question')],
        ),
        ownerId: 'demo-user',
        context: desk,
      );
  print('${paused.status.name}: ${paused.text}');
  print('Application effects: ${desk.escalations}');
  if (paused.status != RunStatus.interrupted || desk.escalations != 0) {
    throw StateError('The tool must wait for approval before causing effects.');
  }
  if (!arguments.contains('--approve')) {
    print('Use --approve to exercise approval in a fresh demo process.');
    return;
  }
  // This CLI flag simulates a recorded human decision. No external service runs.
  final completed =
      await agent(
        ScriptedChatModel(
          capabilities: const ModelCapabilities(tools: true),
          steps: [
            [
              const TextDelta(finalAnswer),
              ReferenceReady(
                OutputReference(
                  provider: 'demo',
                  source: FileCitationSource(
                    provider: 'demo',
                    fileId: 'synthetic-policy',
                    filename: 'Support policy',
                  ),
                  partStart: 0,
                  partEnd: finalAnswer.length,
                  position: FileListPosition(0),
                ),
              ),
              const ModelFinished(),
            ],
          ],
        ),
      ).generate(
        ChatRequest(
          threadId: paused.threadId,
          runId: 'approved',
          parentRunId: paused.runId,
          resume: [paused.interrupts.single.approve()],
        ),
        ownerId: 'demo-user',
        context: desk,
      );
  print('${completed.status.name}: ${completed.text}');
  print('Application effects: ${desk.escalations}');
  if (completed.status != RunStatus.completed ||
      completed.text != finalAnswer ||
      desk.escalations != 1 ||
      completed.responseMessages.last.references.single.source.title !=
          'Support policy') {
    throw StateError(
      'The approved run did not retain its result and reference.',
    );
  }
  for (final message in completed.responseMessages) {
    for (final reference in message.references) {
      print('Reference: ${reference.source.title}');
    }
  }
}
```

The CLI flag represents a recorded human decision. In your application, wait
for that decision before calling `approve()`. Derive `ownerId` from backend
authentication, and pass your trusted services as the agent context.
The example's in-memory idempotency map is not a durable external-effect ledger.
Use `context.idempotencyKey` at the destination service to reconcile retries.

The file reference is synthetic. It demonstrates the typed source and position
API; it does not download or authorize a file. See [output references](output-references.md)
for provider coordinates, client metadata, and authenticated retrieval boundaries.

## Cancel or debug a run

Run `dart run examples/cancellation.dart` to cancel a provider after it starts.
Run `dart run examples/schema_diagnostics.dart` to inspect a rejected structured
value on the backend. The [Dart API recipes](dart-api.md) explain cancellation
and which error details can be exposed to a client.
