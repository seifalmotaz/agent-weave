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
