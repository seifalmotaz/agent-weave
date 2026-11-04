import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as weave;
import 'package:openai_dart/openai_dart.dart' as sdk;
import 'package:test/test.dart';

void main() {
  const extra = {
    'type': 'function',
    'function': {
      'name': 'unregistered',
      'parameters': {'type': 'object'},
    },
  };
  const registered = ModelTool(
    name: 'lookup',
    description: 'Look up a value',
    inputSchema: {'type': 'object'},
  );

  for (final tools in <List<ModelTool>>[
    [],
    [registered],
  ]) {
    test(
      'Chat rejects unregistered configured tool with ${tools.length} registered',
      () async {
        var sent = false;
        final model = weave.ChatCompletionsProtocolModel(
          model: 'fixture',
          configure: (request) => sdk.ChatCompletionCreateRequest.fromJson({
            ...request.toJson(),
            'tools': [...?request.toJson()['tools'] as List?, extra],
          }),
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
                  tools: tools,
                ),
                cancellation: CancellationToken(),
              )
              .toList(),
          throwsArgumentError,
        );
        expect(sent, isFalse);
      },
    );
  }

  test('Chat preserves a registered tool without an override', () async {
    var sent = false;
    final model = weave.ChatCompletionsProtocolModel(
      model: 'fixture',
      transport: (request, _) async* {
        final tools = request.toJson()['tools'] as List;
        expect(tools.single['function']['name'], 'lookup');
        sent = true;
        yield {
          'choices': [
            {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': 'stop'},
          ],
        };
      },
    );
    await model
        .stream(
          ModelRequest(
            messages: [ChatMessage.user('Hi', id: 'u')],
            tools: const [registered],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    expect(sent, isTrue);
  });

  test('Chat rejects removal of a registered tool', () async {
    final model = weave.ChatCompletionsProtocolModel(
      model: 'fixture',
      configure: (request) => sdk.ChatCompletionCreateRequest.fromJson({
        ...request.toJson(),
        'tools': <Object?>[],
      }),
      transport: (_, _) => throw StateError('must not dispatch'),
    );
    await expectLater(
      model
          .stream(
            ModelRequest(
              messages: [ChatMessage.user('Hi', id: 'u')],
              tools: const [registered],
            ),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsArgumentError,
    );
  });
  test(
    'Chat rejects large integer changes inside an owned tool schema',
    () async {
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
      final model = weave.ChatCompletionsProtocolModel(
        model: 'fixture',
        configure: (request) {
          final json = request.toJson();
          final tools = (json['tools'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final function = Map<String, dynamic>.from(
            tools.first['function'] as Map,
          );
          function['parameters'] = {
            'type': 'object',
            'properties': {
              'n': {'type': 'integer', 'maximum': 9007199254740993},
            },
          };
          tools.first['function'] = function;
          return sdk.ChatCompletionCreateRequest.fromJson({
            ...json,
            'tools': tools,
          });
        },
        transport: (_, _) => throw StateError('must not dispatch'),
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
    },
  );
}
