import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'plain Chat reasoning streams and replays when structured details are absent',
    () async {
      var calls = 0;
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'fixture',
        httpClient: MockClient((request) async {
          if (++calls == 2) {
            final messages =
                (jsonDecode(request.body) as Map)['messages'] as List;
            expect(messages.first['reasoning'], 'first second');
            expect(messages.first.containsKey('reasoning_details'), false);
          }
          return http.Response(
            'data: {"choices":[{"index":0,"delta":{"reasoning":"first "},"finish_reason":null}]}\n\ndata: {"choices":[{"index":0,"delta":{"reasoning":"second"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
            200,
          );
        }),
      );
      final model = router.OpenRouterChatModel(
        client: client,
        model: 'fixture',
      );
      final first = await model
          .stream(
            ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(
        first.whereType<ReasoningDelta>().map((event) => event.text).join(),
        'first second',
      );
      final replay = first.whereType<ProviderOutput>().singleWhere(
        (event) => event.provider == 'openrouter.chat.reasoning_text',
      );
      await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  providerData: {replay.provider: replay.items},
                ),
                ChatMessage.user('next', id: 'u2'),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      client.close();
    },
  );

  test(
    'chat reasoning is replayed in order and foreign data is excluded',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'key',
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          final chunks = [
            {
              'model': 'actual',
              'provider': 'vendor',
              'choices': [
                {
                  'index': 0,
                  'delta': {
                    'reasoning_details': [
                      {'type': 'reasoning.encrypted', 'data': 'first'},
                    ],
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call',
                        'type': 'function',
                        'function': {'name': 'lookup', 'arguments': '{}'},
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
                    'reasoning_details': [
                      {'type': 'reasoning.text', 'text': 'second'},
                    ],
                  },
                  'finish_reason': 'tool_calls',
                },
              ],
              'usage': {
                'prompt_tokens': 1,
                'completion_tokens': 2,
                'cost': 0.01,
              },
              'unknown': 'retained',
            },
          ];
          return http.Response(
            '${chunks.map((e) => 'data: ${jsonEncode(e)}\n\n').join()}data: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      addTearDown(client.close);
      final model = router.OpenRouterChatModel(
        client: client,
        model: 'x',
        options: router.OpenRouterChatOptions(
          extra: {
            'future_option': {'x': 1},
          },
        ),
      );
      final events = await model
          .stream(
            ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(events.whereType<TokenUsage>().single.model, 'actual');
      final outputs = events.whereType<ProviderOutput>().toList();
      final reasoning = outputs
          .singleWhere((e) => e.provider == 'openrouter.chat.reasoning')
          .items;
      expect(reasoning.map((e) => e['type']), [
        'reasoning.encrypted',
        'reasoning.text',
      ]);
      expect(
        outputs
            .singleWhere((e) => e.provider == 'openrouter.chat.metadata')
            .items
            .last['unknown'],
        'retained',
      );
      await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage.user('hi', id: 'u'),
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  toolCalls: [
                    ToolCall(id: 'call', name: 'lookup', arguments: const {}),
                  ],
                  providerData: {
                    'openrouter.chat.reasoning': reasoning,
                    'openai.responses': [
                      {'secret': 'foreign'},
                    ],
                  },
                ),
                ChatMessage(
                  id: 't',
                  role: MessageRole.tool,
                  toolCallId: 'call',
                  content: [const TextPart('ok')],
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(bodies.last['messages'][1]['reasoning_details'], reasoning);
      expect(jsonEncode(bodies.last), isNot(contains('foreign')));
      expect(bodies.first['future_option'], {'x': 1});
    },
  );
  test('rotating credentials and raw response metadata', () async {
    var n = 0;
    final seen = <String?>[];
    final client = router.OpenRouterClient(
      credentialResolver: () => 'key${++n}',
      httpClient: MockClient((request) async {
        seen.add(request.headers['authorization']);
        return http.Response(
          '{"unknown":{"cost":0.5}}',
          200,
          headers: {'x-actual': 'present'},
        );
      }),
    );
    addTearDown(client.close);
    expect((await client.createChat({'model': 'x'})).data['unknown'], {
      'cost': 0.5,
    });
    await client.createResponse({'model': 'x'});
    expect(seen, ['Bearer key1', 'Bearer key2']);
  });
  test('options protect runtime fields and snapshot caller data', () {
    expect(
      () => router.OpenRouterChatOptions(extra: {'messages': []}),
      throwsArgumentError,
    );
    expect(
      () => router.OpenRouterResponsesOptions(
        extra: {'previous_response_id': 'id'},
      ),
      throwsArgumentError,
    );
    final order = ['one'];
    final options = router.OpenRouterChatOptions(
      provider: router.OpenRouterProviderPreferences(order: order),
    );
    order.add('two');
    expect((options.toJson()['provider'] as Map)['order'], ['one']);
  });
  test('errors redact credentials and headers', () async {
    final client = router.OpenRouterClient.withApiKey(
      apiKey: 'secret',
      httpClient: MockClient(
        (request) async => http.Response(
          '{"error":"secret"}',
          400,
          headers: {'x-test': 'secret', 'set-cookie': 'secret'},
        ),
      ),
    );
    addTearDown(client.close);
    try {
      await client.createChat({'model': 'x'});
      fail('expected error');
    } on router.JsonHttpException catch (e) {
      expect(e.toString(), isNot(contains('secret')));
      expect(jsonEncode(e.details), isNot(contains('secret')));
      expect(e.responseHeaders.toString(), isNot(contains('secret')));
      expect(e.responseHeaders.containsKey('set-cookie'), isFalse);
    }
  });
  test(
    'cancellation while credential resolver is pending is bounded',
    () async {
      final pending = Completer<String>();
      final client = router.OpenRouterClient(
        credentialResolver: () => pending.future,
      );
      addTearDown(client.close);
      final token = CancellationToken();
      final future = client.createChat({'model': 'x'}, cancellation: token);
      token.cancel();
      await expectLater(future, throwsA(isA<RunCancelled>()));
      pending.complete('key');
    },
  );
  test('truncated stream fails', () async {
    final client = router.OpenRouterClient.withApiKey(
      apiKey: 'key',
      httpClient: MockClient(
        (_) async => http.Response('data: {"choices":[]}\n\n', 200),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      client.streamChat({'model': 'x'}).toList(),
      throwsA(isA<router.JsonHttpException>()),
    );
  });
  test('responses replay retains unknown reasoning fields', () async {
    final bodies = <Map<String, dynamic>>[];
    final responseItem = {
      'id': 'rs_1',
      'type': 'reasoning',
      'summary': <Object?>[],
      'encrypted_content': 'opaque',
      'signature': 'signature',
      'future_field': {'x': 1},
    };
    final client = router.OpenRouterClient.withApiKey(
      apiKey: 'key',
      httpClient: MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        final terminal = {
          'type': 'response.completed',
          'response': {
            'id': 'resp',
            'model': 'actual',
            'output': [responseItem],
            'usage': {'input_tokens': 1, 'output_tokens': 2},
          },
        };
        return http.Response(
          'data: ${jsonEncode(terminal)}\n\ndata: [DONE]\n\n',
          200,
        );
      }),
    );
    addTearDown(client.close);
    final model = router.OpenRouterResponsesModel(client: client, model: 'x');
    final events = await model
        .stream(
          ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
          cancellation: CancellationToken(),
        )
        .toList();
    final replay = events
        .whereType<ProviderOutput>()
        .singleWhere((e) => e.provider == 'openrouter.responses')
        .items;
    await model
        .stream(
          ModelRequest(
            messages: [
              ChatMessage.user('hi', id: 'u'),
              ChatMessage(
                id: 'a',
                role: MessageRole.assistant,
                providerData: {'openrouter.responses': replay},
              ),
            ],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    expect(bodies.last['input'][1], responseItem);
  });
  test(
    'cancelling stream subscription during pending headers returns promptly',
    () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'key',
        httpClient: MockClient((_) {
          started.complete();
          return pending.future;
        }),
      );
      addTearDown(client.close);
      final subscription = client.streamChat({'model': 'x'}).listen((_) {});
      await started.future;
      await subscription.cancel().timeout(const Duration(seconds: 1));
      pending.complete(http.Response('', 200));
    },
  );
  test('borrowed transport stays usable after wrapper close', () async {
    final transport = router.JsonHttpClient(
      baseUrl: 'https://example.com',
      httpClient: MockClient((_) async => http.Response('{"ok":true}', 200)),
    );
    final client = router.OpenRouterClient.withTransport(
      transport: transport,
      credentialResolver: () => 'key',
    );
    client.close();
    expect((await client.createChat({'model': 'x'})).data['ok'], true);
    transport.close();
  });
  test('malformed SSE and resolver errors never expose credentials', () async {
    final malformed = router.OpenRouterClient.withApiKey(
      apiKey: 'secret',
      httpClient: MockClient(
        (_) async => http.Response('data: secret\n\n', 200),
      ),
    );
    addTearDown(malformed.close);
    await expectLater(
      malformed.streamChat({'model': 'x'}).toList(),
      throwsA(
        isA<router.JsonHttpException>().having(
          (e) => e.toString(),
          'redacted',
          isNot(contains('secret')),
        ),
      ),
    );
    final badResolver = router.OpenRouterClient(
      credentialResolver: () => throw StateError('secret'),
    );
    addTearDown(badResolver.close);
    await expectLater(
      badResolver.createChat({'model': 'x'}),
      throwsA(
        isA<router.JsonHttpException>().having(
          (e) => e.toString(),
          'redacted',
          isNot(contains('secret')),
        ),
      ),
    );
  });
}
