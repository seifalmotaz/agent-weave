import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart';
import 'package:test/test.dart';

void main() {
  const tool = ModelTool(
    name: 'lookup',
    description: 'lookup',
    inputSchema: {
      'type': 'object',
      'properties': {
        'n': {'type': 'integer', 'maximum': 9007199254740992},
      },
    },
  );
  test(
    'native configure cannot change a large integer in an owned tool schema',
    () async {
      var sent = false;
      final model = AnthropicProtocolModel(
        model: 'fixture',
        configure: (body) {
          final tools = (body['tools'] as List)
              .map((e) => Map<String, Object?>.from(e as Map))
              .toList();
          tools.first['input_schema'] = {
            'type': 'object',
            'properties': {
              'n': {'type': 'integer', 'maximum': 9007199254740993},
            },
          };
          return {...body, 'tools': tools};
        },
        transport: (_, _) {
          sent = true;
          return const Stream.empty();
        },
      );
      await expectLater(
        model
            .stream(
              ModelRequest(
                messages: [ChatMessage.user('Hi', id: 'u')],
                tools: const [tool],
              ),
              cancellation: CancellationToken(),
            )
            .toList(),
        throwsArgumentError,
      );
      expect(sent, false);
    },
  );
  test('native configure cannot add an unregistered tool', () async {
    var sent = false;
    final model = AnthropicProtocolModel(
      model: 'fixture',
      configure: (body) => {
        ...body,
        'tools': [
          ...?body['tools'] as List?,
          {
            'name': 'unregistered',
            'input_schema': {'type': 'object'},
          },
        ],
      },
      transport: (_, _) {
        sent = true;
        return const Stream.empty();
      },
    );
    await expectLater(
      model
          .stream(
            ModelRequest(
              messages: [ChatMessage.user('Hi', id: 'u')],
              tools: const [tool],
            ),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsArgumentError,
    );
    expect(sent, false);
  });
}
