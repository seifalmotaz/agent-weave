import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

Future<void> main() async {
  final client = openai.OpenAIClient.fromEnvironment();
  try {
    final agent = AiAgent<void>(
      model: openai.OpenAIResponsesModel.native(
        client: client,
        model: Platform.environment['OPENAI_MODEL'] ?? 'gpt-5.4-nano',
        mcpTools: [
          openai.OpenAIMcpTool.fromJson({
            'type': 'mcp',
            'server_label': 'openai_docs',
            'server_url': 'https://developers.openai.com/mcp',
            'require_approval': 'always',
          }),
        ],
      ),
    );
    var result = await agent.generate(
      ChatRequest(
        threadId: 'docs',
        runId: 'question',
        messages: [
          ChatMessage.user(
            'Find the OpenAI Responses streaming guide.',
            id: 'u',
          ),
        ],
      ),
      ownerId: 'local-demo',
      context: null,
    );
    for (
      var round = 0;
      round < 4 && result.status == RunStatus.interrupted;
      round++
    ) {
      final answers = <ResumeAnswer>[];
      for (final interrupt in result.interrupts) {
        final call = interrupt.call as ProviderApprovalCall;
        print('${call.serverLabel}: ${call.name} ${call.arguments}');
        stdout.write('Approve this request? Type yes, otherwise deny: ');
        answers.add(
          stdin.readLineSync() == 'yes'
              ? interrupt.approve()
              : interrupt.reject(reason: 'Declined in the CLI'),
        );
      }
      result = await agent.generate(
        ChatRequest(
          threadId: result.threadId,
          runId: 'decision-$round',
          parentRunId: result.runId,
          resume: answers,
        ),
        ownerId: 'local-demo',
        context: null,
      );
    }
    print('${result.status.name}: ${result.text}');
  } finally {
    client.close();
  }
}
