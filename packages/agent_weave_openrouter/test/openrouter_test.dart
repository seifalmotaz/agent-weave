import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;
import 'package:test/test.dart';

Map<String, Object?> chunk({
  Map<String, Object?> delta = const {},
  String? finish,
  Map<String, Object?>? usage,
}) => {
  'id': 'fixture',
  'object': 'chat.completion.chunk',
  'created': 0,
  'model': 'actual/fallback',
  'choices': usage == null
      ? [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ]
      : [],
  'usage': ?usage,
};

void main() {
  test(
    'loopback sends routing, runtime tools and schema and reads streamed tool and actual model',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        expect(request.uri.path, '/api/v1/chat/completions');
        expect(request.headers.value('authorization'), 'Bearer fixture');
        expect(request.headers.value('http-referer'), 'https://example.com');
        expect(request.headers.value('x-title'), 'fixture app');
        expect(request.headers.value('x-session-id'), 'session');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['models'], ['fallback/model']);
        expect(body['route'], 'fallback');
        expect(body['temperature'], 0.2);
        expect(body['provider'], {
          'order': ['provider'],
          'allow_fallbacks': false,
        });
        expect(body['reasoning'], {'effort': 'low'});
        expect(body['usage'], {'include': true});
        expect(body['max_completion_tokens'], 50);
        expect(body['response_format']['json_schema']['schema'], {
          'type': 'object',
        });
        expect(body['tools'][0]['function']['name'], 'lookup');
        expect(body['messages'][0]['role'], 'system');
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        for (final event in [
          chunk(
            delta: {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call',
                  'type': 'function',
                  'function': {'name': 'lookup', 'arguments': '{"id":'},
                },
              ],
            },
          ),
          chunk(
            delta: {
              'tool_calls': [
                {
                  'index': 0,
                  'function': {'arguments': '42}'},
                },
              ],
            },
            finish: 'tool_calls',
          ),
          chunk(
            usage: {
              'prompt_tokens': 5,
              'completion_tokens': 2,
              'total_tokens': 7,
            },
          ),
        ]) {
          request.response.write('data: ${jsonEncode(event)}\n\n');
        }
        request.response.write('data: [DONE]\n\n');
        await request.response.close();
      });
      final client = router.openRouterClient(
        apiKey: 'fixture',
        baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
        siteUrl: 'https://example.com',
        appName: 'fixture app',
        sessionId: 'session',
      );
      addTearDown(client.close);
      final model = router.OpenRouterChatModel(
        client: client,
        model: 'initial/model',
        fallbackModels: ['fallback/model'],
        route: 'fallback',
        configure: (request) => request.copyWith(temperature: 0.2),
        provider: const router.OpenRouterProviderPreferences(
          order: ['provider'],
          allowFallbacks: false,
        ),
        reasoning: const router.OpenRouterReasoning(effort: 'low'),
        usage: const router.OpenRouterUsageConfig(include: true),
      );
      final events = await model
          .stream(
            ModelRequest(
              messages: [ChatMessage.user('Hi', id: 'u')],
              instructions: 'Be brief',
              maxOutputTokens: 50,
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
      expect(events.whereType<TokenUsage>().single.model, 'actual/fallback');
      expect(events.whereType<ModelFinished>().single.reason, 'tool_calls');
    },
  );

  test('inline stream errors surface rather than completing', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: {"error":{"message":"upstream failed","code":502}}\n\n',
      );
      await request.response.close();
    });
    final client = router.openRouterClient(
      apiKey: 'fixture',
      baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
    );
    addTearDown(client.close);
    await expectLater(
      router.OpenRouterChatModel(client: client, model: 'x')
          .stream(
            ModelRequest(messages: [ChatMessage.user('Hi', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('upstream failed'),
        ),
      ),
    );
  });
  test('pre-cancellation does not send a request', () async {
    final client = router.openRouterClient(apiKey: 'fixture');
    addTearDown(client.close);
    final token = CancellationToken()..cancel();
    await expectLater(
      router.OpenRouterChatModel(client: client, model: 'x')
          .stream(
            ModelRequest(messages: [ChatMessage.user('Hi', id: 'u')]),
            cancellation: token,
          )
          .toList(),
      throwsA(isA<RunCancelled>()),
    );
  });
}
