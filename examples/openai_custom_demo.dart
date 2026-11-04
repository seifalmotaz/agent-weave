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
