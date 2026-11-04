import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_ollama/agent_weave_ollama.dart'
    hide ChatMessage, MessageRole, ToolCall;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('replay cannot change a large integer in the local tool call', () async {
    var sent = false;
    final transport = MockClient((_) async {
      sent = true;
      throw StateError('must not send');
    });
    final client = OllamaNativeClient(httpClient: transport);
    final message = ChatMessage(
      id: 'assistant',
      role: MessageRole.assistant,
      toolCalls: [
        ToolCall(
          id: 'local',
          name: 'lookup',
          arguments: {'n': 9007199254740992},
        ),
      ],
      providerData: {
        'ollama.chat': [
          {
            'role': 'assistant',
            'tool_calls': [
              {
                'function': {
                  'name': 'lookup',
                  'arguments': {'n': 9007199254740993},
                },
              },
            ],
          },
        ],
      },
    );
    try {
      await expectLater(
        client
            .chatModel(model: 'fixture')
            .stream(
              ModelRequest(messages: [message]),
              cancellation: CancellationToken(),
            )
            .toList(),
        throwsFormatException,
      );
      expect(sent, false);
    } finally {
      client.close();
      transport.close();
    }
  });
}
