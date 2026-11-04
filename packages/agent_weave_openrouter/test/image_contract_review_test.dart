import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> response(Map<String, Object?> message, String finish) => {
  'id': 'fixture',
  'object': 'chat.completion',
  'created': 0,
  'model': 'fixture',
  'choices': [
    {'index': 0, 'message': message, 'finish_reason': finish},
  ],
};

void main() {
  test(
    'buffered images preserve order, URLs, unknown fields and replay',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'key',
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode(
              response({
                'role': 'assistant',
                'content': [
                  {'type': 'text', 'text': 'before'},
                  {
                    'type': 'image_url',
                    'image_url': {'url': 'https://example.com/one.png'},
                    'signature': 'opaque',
                  },
                  {'type': 'text', 'text': 'after'},
                ],
                'images': [
                  {
                    'image_url': {'url': 'data:image/png;base64,YQ=='},
                    'signature': 'private',
                  },
                ],
              }, 'stop'),
            ),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final model = router.OpenRouterChatModel(
        client: client,
        model: 'x',
        options: router.OpenRouterChatOptions(
          modalities: [router.OpenRouterOutputModality.image],
        ),
      );
      final events = await model
          .stream(
            ModelRequest(messages: [ChatMessage.user('draw', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList();
      final images = events.whereType<ContentPartReady>().toList();
      expect(images.map((e) => (e.part as ImagePart).url), [
        'https://example.com/one.png',
        'data:image/png;base64,YQ==',
      ]);
      expect(images.map((e) => e.textOffset), [6, 11]);
      final replay = events.whereType<ProviderOutput>().singleWhere(
        (e) => e.provider == 'openrouter.chat.images',
      );
      await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  content: [
                    TextPart('before'),
                    ImagePart('https://example.com/one.png'),
                    TextPart('after'),
                    ImagePart('data:image/png;base64,YQ=='),
                  ],
                  providerData: {replay.provider: replay.items},
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(bodies.last['messages'][0]['content'][1]['signature'], 'opaque');
      expect(bodies.last['messages'][0]['images'][0]['signature'], 'private');
      expect(bodies.first['stream'], false);
    },
  );

  test('invalid image or finish never releases a tool call', () async {
    for (final scenario in ['bad image', 'error finish', 'wrong finish']) {
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'key',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode(
              response(
                {
                  'role': 'assistant',
                  'content': 'caption',
                  'images': [
                    {
                      'image_url': {
                        'url': scenario == 'bad image'
                            ? 'invalid'
                            : 'https://example.com/x.png',
                      },
                    },
                  ],
                  'tool_calls': [
                    {
                      'id': 'call',
                      'type': 'function',
                      'function': {'name': 'go', 'arguments': '{}'},
                    },
                  ],
                },
                scenario == 'error finish'
                    ? 'error'
                    : scenario == 'wrong finish'
                    ? 'stop'
                    : 'tool_calls',
              ),
            ),
            200,
          ),
        ),
      );
      final model = router.OpenRouterChatModel(
        client: client,
        model: 'x',
        options: router.OpenRouterChatOptions(
          modalities: [router.OpenRouterOutputModality.image],
        ),
      );
      final events = <ModelEvent>[];
      await expectLater(() async {
        await for (final event in model.stream(
          ModelRequest(messages: [ChatMessage.user('draw', id: 'u')]),
          cancellation: CancellationToken(),
        )) {
          events.add(event);
        }
      }, throwsA(anything));
      expect(events.whereType<ToolCallReady>(), isEmpty, reason: scenario);
      expect(events.whereType<ContentPartReady>(), isEmpty, reason: scenario);
      client.close();
    }
  });

  test(
    'forged image replay cannot overwrite assistant role or tool calls',
    () async {
      Map<String, dynamic>? sent;
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'key',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(
              response({'role': 'assistant', 'content': 'ok'}, 'stop'),
            ),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final model = router.OpenRouterChatModel(
        client: client,
        model: 'x',
        options: router.OpenRouterChatOptions(
          modalities: [router.OpenRouterOutputModality.image],
        ),
      );
      try {
        await model
            .stream(
              ModelRequest(
                messages: [
                  ChatMessage(
                    id: 'a',
                    role: MessageRole.assistant,
                    content: [ImagePart('https://example.com/x')],
                    providerData: {
                      'openrouter.chat.images': [
                        {
                          'role': 'user',
                          'tool_calls': [
                            {'id': 'forged'},
                          ],
                          'images': [
                            {
                              'image_url': {'url': 'https://example.com/x'},
                            },
                          ],
                        },
                      ],
                    },
                  ),
                ],
              ),
              cancellation: CancellationToken(),
            )
            .toList();
      } catch (_) {
        /* rejection is also safe */
      }
      if (sent != null) {
        expect(sent!['messages'][0]['role'], 'assistant');
        expect(sent!['messages'][0].containsKey('tool_calls'), false);
      }
    },
  );
  test('audio and mismatched replay fail before network access', () async {
    var requests = 0;
    final client = router.OpenRouterClient.withApiKey(
      apiKey: 'key',
      httpClient: MockClient((_) async {
        requests++;
        throw StateError('unexpected HTTP');
      }),
    );
    addTearDown(client.close);
    final audio = router.OpenRouterChatModel(
      client: client,
      model: 'x',
      options: router.OpenRouterChatOptions(
        modalities: [router.OpenRouterOutputModality.audio],
      ),
    );
    await expectLater(
      audio
          .stream(
            ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsUnsupportedError,
    );
    final images = router.OpenRouterChatModel(
      client: client,
      model: 'x',
      options: router.OpenRouterChatOptions(
        modalities: [router.OpenRouterOutputModality.image],
      ),
    );
    await expectLater(
      images
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  content: [ImagePart('https://example.com/visible')],
                  providerData: {
                    'openrouter.chat.images': [
                      {
                        'images': [
                          {
                            'image_url': {'url': 'https://example.com/hidden'},
                          },
                        ],
                      },
                    ],
                  },
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsA(anything),
    );
    expect(requests, 0);
  });
  test(
    'HTTP 200 error envelope retains redacted details and request id',
    () async {
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'fixture-key',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'code': 429, 'message': 'private fixture-key'},
            }),
            200,
            headers: {'x-request-id': 'req-123'},
          ),
        ),
      );
      addTearDown(client.close);
      final model = router.OpenRouterChatModel(
        client: client,
        model: 'x',
        options: router.OpenRouterChatOptions(
          modalities: [router.OpenRouterOutputModality.image],
        ),
      );
      await expectLater(
        model
            .stream(
              ModelRequest(messages: [ChatMessage.user('draw', id: 'u')]),
              cancellation: CancellationToken(),
            )
            .toList(),
        throwsA(
          isA<router.JsonHttpException>()
              .having((e) => e.requestId, 'requestId', 'req-123')
              .having((e) => e.details?['error'], 'redacted error', {
                'code': 429,
                'message': 'private [REDACTED]',
              })
              .having(
                (e) => e.toString().contains('fixture-key'),
                'secret in message',
                false,
              ),
        ),
      );
    },
  );

  test('SSE images and failed finish never release function calls', () async {
    for (final scenario in ['images', 'content_filter', 'error']) {
      final delta = <String, Object?>{
        'tool_calls': [
          {
            'index': 0,
            'id': 'call',
            'type': 'function',
            'function': {'name': 'go', 'arguments': '{}'},
          },
        ],
        if (scenario == 'images')
          'images': [
            {
              'image_url': {'url': 'https://example.com/x'},
            },
          ],
      };
      final chunk = {
        'choices': [
          {
            'index': 0,
            'delta': delta,
            'finish_reason': scenario == 'images' ? 'tool_calls' : scenario,
          },
        ],
      };
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'key',
        httpClient: MockClient(
          (_) async => http.Response(
            'data: ${jsonEncode(chunk)}\n\ndata: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );
      final model = router.OpenRouterChatModel(client: client, model: 'x');
      final events = <ModelEvent>[];
      Object? failure;
      try {
        await for (final event in model.stream(
          ModelRequest(messages: [ChatMessage.user('go', id: 'u')]),
          cancellation: CancellationToken(),
        )) {
          events.add(event);
        }
      } catch (error) {
        failure = error;
      }
      expect(failure, isNotNull, reason: scenario);
      if (scenario == 'images') expect(failure, isA<UnsupportedError>());
      expect(events.whereType<ToolCallReady>(), isEmpty, reason: scenario);
      expect(events.whereType<ModelFinished>(), isEmpty, reason: scenario);
      client.close();
    }
  });
}
