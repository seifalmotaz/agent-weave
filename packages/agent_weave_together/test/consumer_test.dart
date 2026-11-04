import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_together/agent_weave_together.dart' as together;
import 'package:test/test.dart';

void main() {
  test(
    'consumer streams tool calls and usage through a loopback server',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(request.uri.path, '/v1/chat/completions');
        expect(request.headers.value('authorization'), 'Bearer fixture');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['model'], 'fixture-model');
        expect(body['temperature'], 0.2);
        expect(body['max_tokens'], 64);
        expect(body['messages'][0]['content'], 'Be brief');
        expect(body['tools'][0]['function']['name'], 'lookup');
        expect(body['response_format']['json_schema']['schema'], {
          'type': 'object',
        });
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        for (final event in [
          {
            'model': 'actual-model',
            'choices': [
              {
                'index': 0,
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call-1',
                      'type': 'function',
                      'function': {'name': 'lookup', 'arguments': '{"id":'},
                    },
                  ],
                },
                'finish_reason': null,
              },
            ],
          },
          {
            'choices': [
              {
                'index': 0,
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': '42}'},
                    },
                  ],
                },
                'finish_reason': 'tool_calls',
              },
            ],
          },
          {
            'choices': <Object?>[],
            'usage': {
              'prompt_tokens': 5,
              'completion_tokens': 2,
              'total_tokens': 7,
            },
          },
        ]) {
          request.response.write('data: ${jsonEncode(event)}\n\n');
        }
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      final client = together.TogetherClient(
        apiKey: 'fixture',
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
      );
      addTearDown(client.close);
      final model = together.TogetherChatModel(
        client: client,
        model: 'fixture-model',
        options: together.TogetherChatOptions(temperature: 0.2),
      );
      final events = await model
          .stream(
            ModelRequest(
              messages: [ChatMessage.user('Find it', id: 'u')],
              instructions: 'Be brief',
              maxOutputTokens: 64,
              tools: const [
                ModelTool(
                  name: 'lookup',
                  description: 'Look up',
                  inputSchema: {'type': 'object'},
                ),
              ],
              outputSchema: const {'type': 'object'},
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(events.whereType<ToolCallReady>().single.call.arguments, {
        'id': 42,
      });

      expect(events.whereType<TokenUsage>().single.model, 'actual-model');
      expect(events.whereType<ModelFinished>().single.reason, 'tool_calls');
    },
  );

  test('cancelled consumer request fails before network access', () async {
    final client = together.TogetherClient(apiKey: 'fixture');
    addTearDown(client.close);
    final token = CancellationToken()..cancel();
    await expectLater(
      together.TogetherChatModel(client: client, model: 'x')
          .stream(
            ModelRequest(messages: [ChatMessage.user('Hi', id: 'u')]),
            cancellation: token,
          )
          .toList(),
      throwsA(isA<RunCancelled>()),
    );
  });
}
