import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;
import 'package:test/test.dart';

void main() {
  test(
    'foreign provider approval state fails before Chat or Anthropic dispatch',
    () async {
      final call = ProviderApprovalCall(
        id: 'local',
        name: 'escalate',
        arguments: {},
        provider: 'openai.responses',
        serverLabel: 'desk',
        providerRequestId: 'private',
      );
      final history = ChatMessage(
        id: 'm',
        role: MessageRole.assistant,
        toolCalls: [call],
      );
      var dispatched = false;
      final models = <ChatModel>[
        openai.ChatCompletionsProtocolModel(
          model: 'm',
          transport: (_, _) async* {
            dispatched = true;
          },
        ),
        anthropic.AnthropicProtocolModel(
          model: 'm',
          transport: (_, _) async* {
            dispatched = true;
          },
        ),
      ];
      for (final model in models) {
        for (final request in [
          ModelRequest(messages: [history]),
          ModelRequest(
            messages: [],
            providerApprovalDecisions: [
              const ProviderApprovalDecision(
                provider: 'openai.responses',
                providerRequestId: 'private',
                approved: true,
              ),
            ],
          ),
        ]) {
          await expectLater(
            model.stream(request, cancellation: CancellationToken()).toList(),
            throwsUnsupportedError,
          );
        }
      }
      expect(dispatched, false);
    },
  );
}
