// Offline typed backend stream with a local approval.
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  var effects = 0;
  final model = ScriptedChatModel(
    capabilities: const ModelCapabilities(tools: true),
    steps: [
      [
        const TextDelta('I can escalate ticket 42.'),
        ToolCallReady(
          ToolCall(id: 'call', name: 'escalate', arguments: {'ticket': 42}),
        ),
        const TokenUsage(inputTokens: 4, outputTokens: 2),
        const ModelFinished(),
      ],
      [const TextDelta('Escalated.'), const ModelFinished()],
    ],
  );
  final store = MemoryRunStore();
  AiAgent<void> agent() => AiAgent<void>(
    store: store,
    model: model,
    tools: [
      Tool<int, String, void>(
        name: 'escalate',
        description: 'Escalate a support ticket',
        needsApproval: true,
        inputSchema: const {
          'type': 'object',
          'properties': {
            'ticket': {'type': 'integer'},
          },
          'required': ['ticket'],
          'additionalProperties': false,
        },
        outputSchema: const {'type': 'string'},
        decode: (json) => json['ticket'] as int,
        encode: (value) => value,
        execute: (ticket, context) {
          effects++;
          return 'Escalated $ticket';
        },
      ),
    ],
  );
  try {
    AgentResult? paused;
    await for (final update in agent().stream(
      ChatRequest(
        threadId: 'support',
        runId: 'first',
        messages: [ChatMessage.user('Escalate ticket 42', id: 'question')],
      ),
      ownerId: 'owner',
      context: null,
    )) {
      switch (update) {
        case AgentTextDelta(:final text):
          print('Text: $text');
        case AgentToolCallReady(:final call):
          print('Proposed: ${call.name}');
        case AgentUsage(:final usage):
          print('Input tokens: ${usage.inputTokens}');
        case AgentRunFinished(:final result):
          paused = result;
        default:
          break;
      }
    }
    check(
      paused?.status == RunStatus.interrupted && effects == 0,
      'Approval must precede the effect',
    );
    final decision = paused!.interrupts.single
        .approve(); // Simulated decision for this offline example.
    AgentResult? completed;
    await for (final update in agent().stream(
      ChatRequest(
        threadId: paused.threadId,
        runId: 'second',
        parentRunId: paused.runId,
        resume: [decision],
      ),
      ownerId: 'owner',
      context: null,
    )) {
      if (update case AgentToolResult(:final result)) {
        print('Tool result: $result');
      }
      if (update case AgentTextDelta(:final text)) print('Text: $text');
      if (update case AgentRunFinished(:final result)) completed = result;
    }
    check(
      completed?.text == 'Escalated.' &&
          effects == 1 &&
          model.requests.length == 2,
      'Expected one effect and two model invocations',
    );
    print('PASS typed stream and approval');
  } on AgentRunException catch (error) {
    print('Run failed: ${error.code}; partial: ${error.result.text}');
    rethrow;
  } on RunCancelled {
    print('Run cancelled');
    rethrow;
  }
}
