import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> responseJson({List<JsonObject> output = const []}) => {
  'id': 'response',
  'object': 'response',
  'created_at': 0,
  'status': 'completed',
  'model': 'fixture',
  'output': output,
  'usage': {'input_tokens': 5, 'output_tokens': 2, 'total_tokens': 7},
};
Map<String, Object?> responseEvent(
  String type, [
  Map<String, Object?> data = const {},
]) => {'type': type, 'sequence_number': 0, ...data};
Map<String, Object?> chatEvent({
  Map<String, Object?> delta = const {},
  String? finish,
  Map<String, Object?>? usage,
}) => {
  'id': 'chat',
  'object': 'chat.completion.chunk',
  'created': 0,
  'model': 'fixture',
  'choices': usage == null
      ? [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ]
      : [],
  'usage': ?usage,
};

openai.OpenAIClient fixtureClient(
  List<Map<String, Object?>> events,
  void Function(http.Request request) inspect,
) {
  final transport = MockClient((request) async {
    inspect(request);
    return http.Response(
      '${events.map((e) => 'data: ${jsonEncode(e)}\n\n').join()}data: [DONE]\n\n',
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  });
  final client = openai.OpenAIClient(
    config: const openai.OpenAIConfig(
      authProvider: openai.ApiKeyProvider('fixture-key'),
      retryPolicy: openai.RetryPolicy(maxRetries: 0),
    ),
    httpClient: transport,
    streamClientFactory: () => transport,
  );
  addTearDown(client.close);
  return client;
}

final modelRequest = ModelRequest(
  messages: [ChatMessage.user('Hello', id: 'user')],
  instructions: 'Be brief',
  maxOutputTokens: 16,
);

void main() {
  test(
    'protocol subscription cancellation signals only its linked token',
    () async {
      final started = Completer<CancellationToken>();
      final ended = Completer<void>();
      final model = openai.ResponsesProtocolModel(
        model: 'fixture',
        transport: (_, token) async* {
          started.complete(token);
          await token.whenCancelled;
          ended.complete();
          throw const RunCancelled();
        },
      );
      final parent = CancellationToken();
      final sub = model
          .stream(modelRequest, cancellation: parent)
          .listen((_) {});
      final child = await started.future;
      await sub.cancel().timeout(const Duration(seconds: 2));
      await ended.future.timeout(const Duration(seconds: 2));
      expect(child.isCancelled, isTrue);
      expect(parent.isCancelled, isFalse);
    },
  );

  for (final responses in [true, false]) {
    test(
      'SDK ${responses ? "Responses" : "Chat"} subscription cancellation aborts pending headers independently',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requests = <HttpRequest>[];
        final accepted = Completer<void>();
        server.listen((request) async {
          requests.add(request);
          if (requests.length == 2) accepted.complete();
        });
        final client = openai.OpenAIClient(
          config: openai.OpenAIConfig(
            baseUrl: 'http://127.0.0.1:${server.port}/v1',
            authProvider: const openai.ApiKeyProvider('fixture'),
            retryPolicy: const openai.RetryPolicy(maxRetries: 0),
          ),
        );
        addTearDown(client.close);
        final ChatModel model = responses
            ? openai.OpenAIResponsesModel(client: client, model: 'fixture')
            : openai.OpenAIChatModel(client: client, model: 'fixture');
        final token = CancellationToken();
        final first = model
            .stream(modelRequest, cancellation: token)
            .listen((_) {});
        final second = model.stream(modelRequest, cancellation: token).toList();
        await accepted.future.timeout(const Duration(seconds: 3));
        await first.cancel().timeout(const Duration(seconds: 2));
        expect(token.isCancelled, isFalse);
        final response = requests[1].response;
        response.headers.contentType = ContentType('text', 'event-stream');
        final event = responses
            ? responseEvent('response.completed', {'response': responseJson()})
            : chatEvent(delta: {'content': 'ok'}, finish: 'stop');
        response.write('data: ${jsonEncode(event)}\n\ndata: [DONE]\n\n');
        await response.close();
        expect(
          (await second.timeout(
            const Duration(seconds: 3),
          )).whereType<ModelFinished>(),
          hasLength(1),
        );
      },
    );
  }

  for (final useSdk in [false, true]) {
    test(
      'Chat ${useSdk ? "SDK facade" : "protocol"} continues tool calls',
      () async {
        final requests = <Map<String, dynamic>>[];
        List<JsonObject> capture(Map<String, dynamic> request) {
          requests.add(request);
          return requests.length == 1
              ? [
                  chatEvent(
                    delta: {
                      'tool_calls': [
                        {
                          'index': 0,
                          'id': 'call',
                          'type': 'function',
                          'function': {
                            'name': 'lookup',
                            'arguments': '{"id":42}',
                          },
                        },
                      ],
                    },
                    finish: 'tool_calls',
                  ),
                ]
              : [
                  chatEvent(delta: {'content': 'done'}, finish: 'stop'),
                ];
        }

        late final ChatModel model;
        if (useSdk) {
          final httpClient = MockClient((request) async {
            final events = capture(
              jsonDecode(request.body) as Map<String, dynamic>,
            );
            return http.Response(
              '${events.map((event) => 'data: ${jsonEncode(event)}\n\n').join()}data: [DONE]\n\n',
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          });
          final client = openai.OpenAIClient(
            config: const openai.OpenAIConfig(
              authProvider: openai.ApiKeyProvider('fixture'),
            ),
            httpClient: httpClient,
            streamClientFactory: () => httpClient,
          );
          addTearDown(client.close);
          model = openai.OpenAIChatModel(client: client, model: 'fixture');
        } else {
          model = openai.ChatCompletionsProtocolModel(
            model: 'fixture',
            transport: (request, _) =>
                Stream.fromIterable(capture(request.toJson())),
          );
        }
        final first = await model
            .stream(modelRequest, cancellation: CancellationToken())
            .toList();
        final call = first.whereType<ToolCallReady>().single.call;
        final second = await model
            .stream(
              ModelRequest(
                messages: [
                  ChatMessage.user('Hello', id: 'u'),
                  ChatMessage(
                    id: 'a',
                    role: MessageRole.assistant,
                    toolCalls: [call],
                  ),
                  ChatMessage(
                    id: 't',
                    role: MessageRole.tool,
                    toolCallId: call.id,
                    content: [TextPart('42')],
                  ),
                  ChatMessage(
                    id: 'a2',
                    role: MessageRole.assistant,
                    content: [TextPart('Earlier answer')],
                  ),
                ],
              ),
              cancellation: CancellationToken(),
            )
            .toList();
        final messages = requests.last['messages'] as List;
        expect((messages[1] as Map)['tool_calls'], isNotEmpty);
        expect((messages[1] as Map)['content'], isNull);
        expect((messages[2] as Map)['content'], '42');
        expect((messages[3] as Map)['content'], 'Earlier answer');
        expect(second.whereType<TextDelta>().single.text, 'done');
      },
    );
  }
  test('Chat rejects assistant multimedia before dispatch', () async {
    final model = openai.ChatCompletionsProtocolModel(
      model: 'fixture',
      transport: (_, _) => throw StateError('must not dispatch'),
    );
    await expectLater(
      model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  content: [ImagePart('https://example.com/a.png')],
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsFormatException,
    );
  });

  test(
    'Responses compatibility can omit encrypted reasoning includes',
    () async {
      for (final configured in [false, true]) {
        final model = openai.ResponsesProtocolModel(
          model: 'fixture',
          includeEncryptedReasoning: false,
          configure: configured
              ? (request) => openai.CreateResponseRequest.fromJson({
                  ...request.toJson(),
                  'include': ['web_search_call.action.sources'],
                })
              : null,
          transport: (request, _) {
            final body = request.toJson();
            if (configured) {
              expect(body['include'], ['web_search_call.action.sources']);
            } else {
              expect(body.containsKey('include'), false);
            }
            return Stream.value(
              responseEvent('response.completed', {'response': responseJson()}),
            );
          },
        );
        await model
            .stream(modelRequest, cancellation: CancellationToken())
            .toList();
      }
    },
  );

  test(
    'Responses preserves raw reasoning and tool output input fields',
    () async {
      final items = <JsonObject>[
        {
          'type': 'reasoning',
          'id': 'reasoning-1',
          'encrypted_content': 'private',
          'summary': <Object?>[],
          'signature': 'opaque-signature',
          'future': {
            'nested': [1, 2],
          },
        },
        {
          'type': 'function_call_output',
          'call_id': 'call',
          'output': 'done',
          'name': 'lookup',
          'namespace': 'app',
        },
      ];
      final model = openai.ResponsesProtocolModel(
        model: 'fixture',
        providerDataKey: 'router.responses',
        configure: (request) => request.copyWith(temperature: 0.2),
        transport: (request, _) {
          expect((request.toJson()['input'] as List).take(2).toList(), items);
          expect(request.toJson()['temperature'], 0.2);
          return Stream.value(
            responseEvent('response.completed', {'response': responseJson()}),
          );
        },
      );
      await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  providerData: {'router.responses': items},
                ),
                ChatMessage.user('next', id: 'u'),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
    },
  );
  test(
    'Responses SDK facade replays encrypted reasoning on the next call',
    () async {
      var calls = 0;
      final client = fixtureClient(
        [
          responseEvent('response.completed', {
            'response': {
              ...responseJson(),
              'output': [
                {
                  'type': 'reasoning',
                  'id': 'reasoning-1',
                  'summary': <Object?>[],
                  'encrypted_content': 'private',
                },
              ],
            },
          }),
        ],
        (request) {
          if (++calls == 2) {
            final input = (jsonDecode(request.body) as Map)['input'] as List;
            expect(input.first['type'], 'reasoning');
            expect(input.first['encrypted_content'], 'private');
          }
        },
      );
      final model = openai.OpenAIResponsesModel(
        client: client,
        model: 'fixture',
      );
      final first = await model
          .stream(modelRequest, cancellation: CancellationToken())
          .toList();
      await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  providerData: {
                    'openai.responses': first
                        .whereType<ProviderOutput>()
                        .singleWhere(
                          (event) => event.provider == 'openai.responses',
                        )
                        .items,
                  },
                ),
                ChatMessage.user('next', id: 'u'),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(calls, 2);
    },
  );
  for (final overrides in <Map<String, Object?>>[
    {'max_tokens': 1000000},
    {
      'stream_options': {'include_usage': false},
    },
  ]) {
    test(
      'Chat configure cannot inject alternate bounds or stream controls: $overrides',
      () async {
        final model = openai.ChatCompletionsProtocolModel(
          model: 'fixture',
          transport: (_, _) => throw StateError('must not dispatch'),
          configure: (request) => openai.ChatCompletionCreateRequest.fromJson({
            ...request.toJson(),
            ...overrides,
          }),
        );
        await expectLater(
          model
              .stream(modelRequest, cancellation: CancellationToken())
              .toList(),
          throwsArgumentError,
        );
      },
    );
  }
  test('Responses configure cannot add absent runtime instructions', () async {
    final model = openai.ResponsesProtocolModel(
      model: 'fixture',
      transport: (_, _) => throw StateError('must not dispatch'),
      configure: (request) => request.copyWith(instructions: 'overridden'),
    );
    await expectLater(
      model
          .stream(
            ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsArgumentError,
    );
  });
  test(
    'Chat configure mutation cannot change the canonical history baseline',
    () async {
      final model = openai.ChatCompletionsProtocolModel(
        model: 'fixture',
        transport: (_, _) => throw StateError('must not dispatch'),
        configure: (request) {
          request.messages.clear();
          return request;
        },
      );
      await expectLater(
        model.stream(modelRequest, cancellation: CancellationToken()).toList(),
        throwsA(anyOf(isA<ArgumentError>(), isA<UnsupportedError>())),
      );
    },
  );

  for (final reported in <String?>[null, 'actual/routed']) {
    test(
      'Chat usage retains only reported model identity: $reported',
      () async {
        final finish = chatEvent(finish: 'stop')..remove('model');
        if (reported != null) finish['model'] = reported;
        final usage = chatEvent(
          usage: {'prompt_tokens': 1, 'completion_tokens': 2},
        )..remove('model');
        final model = openai.ChatCompletionsProtocolModel(
          model: 'requested/alias',
          transport: (_, _) => Stream.fromIterable([finish, usage]),
        );
        final events = await model
            .stream(modelRequest, cancellation: CancellationToken())
            .toList();
        expect(events.whereType<TokenUsage>().single.model, reported);
      },
    );
    test(
      'Responses usage retains only reported model identity: $reported',
      () async {
        final response = responseJson()..remove('model');
        final model = openai.ResponsesProtocolModel(
          model: 'requested/alias',
          transport: (_, _) => Stream.fromIterable([
            if (reported != null)
              responseEvent('response.created', {
                'response': {'model': reported},
              }),
            responseEvent('response.completed', {'response': response}),
          ]),
        );
        final events = await model
            .stream(modelRequest, cancellation: CancellationToken())
            .toList();
        expect(events.whereType<TokenUsage>().single.model, reported);
      },
    );
  }

  test(
    'Chat accepts native reasoning text without duplicating aliases',
    () async {
      for (final delta in [
        {'reasoning': 'native thought'},
        {
          'reasoning_content': 'primary thought',
          'reasoning': 'duplicate thought',
        },
      ]) {
        final model = openai.ChatCompletionsProtocolModel(
          model: 'fixture',
          transport: (_, _) =>
              Stream.value(chatEvent(delta: delta, finish: 'stop')),
        );
        final events = await model
            .stream(modelRequest, cancellation: CancellationToken())
            .toList();
        expect(
          events.whereType<ReasoningDelta>().single.text,
          delta['reasoning_content'] ?? delta['reasoning'],
        );
      }
    },
  );

  test('protocol isolates replay and guards conversation ownership', () async {
    Map<String, dynamic>? sent;
    final model = openai.ResponsesProtocolModel(
      model: 'fixture',
      providerDataKey: 'vercel.gateway.responses',
      fileIdProvider: null,
      transport: (request, _) {
        sent = request.toJson();
        return Stream.value(
          responseEvent('response.completed', {'response': responseJson()}),
        );
      },
    );
    final events = await model
        .stream(
          ModelRequest(
            messages: [
              ChatMessage(
                id: 'a',
                role: MessageRole.assistant,
                content: [TextPart('visible')],
                providerData: {
                  'openai.responses': [
                    {'type': 'reasoning', 'id': 'secret'},
                  ],
                },
              ),
            ],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    expect(jsonEncode(sent!['input']), isNot(contains('secret')));
    expect(jsonEncode(sent!['input']), contains('visible'));
    expect(
      events.whereType<ProviderOutput>().single.provider,
      'vercel.gateway.responses',
    );
    final guarded = openai.ResponsesProtocolModel(
      model: 'fixture',
      transport: (_, _) => throw StateError('must not dispatch'),
      configure: (r) => openai.CreateResponseRequest.fromJson({
        ...r.toJson(),
        'input': <Object?>[],
      }),
    );
    await expectLater(
      guarded.stream(modelRequest, cancellation: CancellationToken()).toList(),
      throwsArgumentError,
    );
  });

  test(
    'gateway protocol rejects provider handles and legacy file parts before dispatch',
    () async {
      final model = openai.ResponsesProtocolModel(
        model: 'fixture',
        fileIdProvider: null,
        transport: (_, _) => throw StateError('must not dispatch'),
      );
      for (final part in [
        FilePart('id'),
        DocumentPart.fileId('id', provider: 'openai'),
      ]) {
        await expectLater(
          model
              .stream(
                ModelRequest(
                  messages: [
                    ChatMessage(
                      id: 'u',
                      role: MessageRole.user,
                      content: [part],
                    ),
                  ],
                ),
                cancellation: CancellationToken(),
              )
              .toList(),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'Responses protocol rejects EOF without terminal and provider failure',
    () async {
      for (final events in <List<JsonObject>>[
        [],
        [responseEvent('response.failed')],
        [responseEvent('error')],
      ]) {
        final model = openai.ResponsesProtocolModel(
          model: 'fixture',
          transport: (_, _) => Stream.fromIterable(events),
        );
        await expectLater(
          model
              .stream(modelRequest, cancellation: CancellationToken())
              .toList(),
          throwsStateError,
        );
      }
    },
  );

  for (final option in <Map<String, Object?>>[
    {'n': 2},
    {
      'modalities': ['text', 'audio'],
    },
  ]) {
    test('Chat protocol rejects $option before dispatch', () async {
      var sent = false;
      final model = openai.ChatCompletionsProtocolModel(
        model: 'fixture',
        transport: (_, _) {
          sent = true;
          return const Stream.empty();
        },
        configure: (r) => openai.ChatCompletionCreateRequest.fromJson({
          ...r.toJson(),
          ...option,
        }),
      );
      await expectLater(
        model.stream(modelRequest, cancellation: CancellationToken()).toList(),
        throwsArgumentError,
      );
      expect(sent, isFalse);
    });
  }

  for (final (part, field, value) in <(DocumentPart, String, String)>[
    (
      DocumentPart.url(
        'https://example.com/report.pdf',
        filename: 'report.pdf',
      ),
      'file_url',
      'https://example.com/report.pdf',
    ),
    (
      DocumentPart.bytes(
        utf8.encode('fixture'),
        mimeType: 'application/pdf',
        filename: 'report.pdf',
      ),
      'file_data',
      'data:application/pdf;base64,Zml4dHVyZQ==',
    ),
    (
      DocumentPart.fileId(
        'file-123',
        provider: 'openai',
        filename: 'report.pdf',
      ),
      'file_id',
      'file-123',
    ),
  ]) {
    test(
      'Responses encodes ${part.runtimeType} without dropping document metadata',
      () async {
        final client = fixtureClient(
          [
            responseEvent('response.completed', {'response': responseJson()}),
          ],
          (request) {
            final body = jsonDecode(request.body) as Map;
            final content =
                (((body['input'] as List).single as Map)['content'] as List)
                        .single
                    as Map;
            expect(content['type'], 'input_file');
            expect(content[field], value);
            expect(content['filename'], 'report.pdf');
          },
        );
        await openai.OpenAIResponsesModel(client: client, model: 'fixture')
            .stream(
              ModelRequest(
                messages: [
                  ChatMessage(id: 'u', role: MessageRole.user, content: [part]),
                ],
              ),
              cancellation: CancellationToken(),
            )
            .drain<void>();
      },
    );
  }
  test('a foreign provider file handle is rejected before dispatch', () async {
    final client = fixtureClient([], (_) => fail('Must not submit'));
    final model = openai.OpenAIResponsesModel(client: client, model: 'fixture');
    await expectLater(
      model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'u',
                  role: MessageRole.user,
                  content: [
                    DocumentPart.fileId('anthropic-id', provider: 'anthropic'),
                  ],
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsArgumentError,
    );
  });

  test(
    'computer-use actions fail explicitly instead of silently completing',
    () async {
      final client = fixtureClient([
        responseEvent('response.output_item.done', {
          'output_index': 0,
          'item': {
            'type': 'computer_call',
            'id': 'cu_1',
            'call_id': 'call_1',
            'actions': [
              {'type': 'screenshot'},
            ],
            'pending_safety_checks': <Object?>[],
            'status': 'completed',
          },
        }),
        responseEvent('response.completed', {'response': responseJson()}),
      ], (_) {});
      final model = openai.OpenAIResponsesModel(
        client: client,
        model: 'fixture',
      );
      await expectLater(
        model.stream(modelRequest, cancellation: CancellationToken()).toList(),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.toString(),
            'message',
            contains('native continuation handler'),
          ),
        ),
      );
    },
  );

  test('local OpenAI-compatible chat works over real loopback HTTP', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      expect(request.uri.path, '/v1/chat/completions');
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect((body['messages'] as List).last['content'], [
        {'type': 'text', 'text': 'Hello'},
      ]);
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      for (final event in [
        chatEvent(delta: {'content': 'Local answer'}),
        chatEvent(finish: 'stop'),
      ]) {
        request.response.write('data: ${jsonEncode(event)}\n\n');
      }
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final client = openai.OpenAIClient(
      config: openai.OpenAIConfig(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        authProvider: openai.ApiKeyProvider('local-fixture'),
      ),
    );
    addTearDown(client.close);
    final result = await generateText(
      model: openai.OpenAIChatModel(client: client, model: 'local'),
      prompt: 'Hello',
    );
    expect(result.text, 'Local answer');
  });

  for (final responses in [true, false]) {
    test(
      '${responses ? "Responses" : "Chat"} configuration cannot replace authoritative conversation',
      () async {
        var sent = false;
        final client = fixtureClient([], (_) {
          sent = true;
        });
        final ChatModel model = responses
            ? openai.OpenAIResponsesModel(
                client: client,
                model: 'fixture',
                configure: (request) => openai.CreateResponseRequest.fromJson({
                  ...request.toJson(),
                  'input': <Object?>[],
                }),
              )
            : openai.OpenAIChatModel(
                client: client,
                model: 'fixture',
                configure: (request) =>
                    openai.ChatCompletionCreateRequest.fromJson({
                      ...request.toJson(),
                      'messages': <Object?>[],
                    }),
              );
        await expectLater(
          model
              .stream(modelRequest, cancellation: CancellationToken())
              .toList(),
          throwsArgumentError,
        );
        expect(sent, isFalse);
      },
    );
  }
  test(
    'Responses options preserve caching and required encrypted reasoning replay',
    () async {
      final client = fixtureClient(
        [
          responseEvent('response.completed', {'response': responseJson()}),
        ],
        (request) {
          final body = jsonDecode(request.body) as Map;
          expect(body['prompt_cache_key'], 'tenant-cache');
          expect(body['include'], contains('reasoning.encrypted_content'));
          expect(body['metadata'], {'tenant': 'fixture'});
        },
      );
      final model = openai.OpenAIResponsesModel(
        client: client,
        model: 'configured-model',
        configure: (request) => openai.CreateResponseRequest.fromJson({
          ...request.toJson(),
          'prompt_cache_key': 'tenant-cache',
          'include': <Object?>[],
          'metadata': {'tenant': 'fixture'},
        }),
      );
      final events = await model
          .stream(modelRequest, cancellation: CancellationToken())
          .toList();
      expect(events.whereType<TokenUsage>().single.model, 'fixture');
    },
  );

  test(
    'Responses streams text and usage and sends bounded server options',
    () async {
      final client = fixtureClient(
        [
          responseEvent('response.output_text.delta', {
            'item_id': 'item',
            'output_index': 0,
            'content_index': 0,
            'delta': 'Hello',
          }),
          responseEvent('response.completed', {'response': responseJson()}),
        ],
        (request) {
          expect(request.url.path, '/v1/responses');
          expect(request.headers['authorization'], 'Bearer fixture-key');
          final body = jsonDecode(request.body) as Map;
          expect(body['max_output_tokens'], 16);
          expect(body['instructions'], 'Be brief');
          expect(body['store'], isFalse);
          expect(body['stream'], isTrue);
        },
      );
      final model = openai.OpenAIResponsesModel(
        client: client,
        model: 'fixture',
      );
      final events = await model
          .stream(modelRequest, cancellation: CancellationToken())
          .toList();
      expect(events.map((e) => e.runtimeType), [
        TextDelta,
        ProviderOutput,
        ProviderOutput,
        TokenUsage,
        ModelFinished,
      ]);
      expect((events.first as TextDelta).text, 'Hello');
    },
  );

  test('Responses converts a completed function call', () async {
    final client = fixtureClient([
      responseEvent('response.output_item.done', {
        'output_index': 0,
        'item': {
          'type': 'function_call',
          'id': 'item',
          'call_id': 'call',
          'name': 'lookup',
          'arguments': '{"id":42}',
          'status': 'completed',
        },
      }),
      responseEvent('response.completed', {
        'response': responseJson(
          output: [
            {
              'type': 'function_call',
              'id': 'item',
              'call_id': 'call',
              'name': 'lookup',
              'arguments': '{"id":42}',
              'status': 'completed',
            },
          ],
        ),
      }),
    ], (_) {});
    final events = await openai.OpenAIResponsesModel(
      client: client,
      model: 'fixture',
    ).stream(modelRequest, cancellation: CancellationToken()).toList();
    expect((events.first as ToolCallReady).call.arguments, {'id': 42});
  });

  test(
    'Responses converts tools, tool results, images, files and structured output',
    () async {
      final client = fixtureClient(
        [
          responseEvent('response.completed', {'response': responseJson()}),
        ],
        (request) {
          final body = jsonDecode(request.body) as Map;
          final input = body['input'] as List;
          expect((input[0] as Map)['content'], [
            {'type': 'input_text', 'text': 'Look'},
            {'type': 'input_image', 'image_url': 'https://example.com/a.png'},
            {'type': 'input_file', 'file_id': 'file-1'},
          ]);
          expect((input[1] as Map)['type'], 'function_call');
          expect((input[2] as Map)['type'], 'function_call_output');
          expect(
            (body['text'] as Map)['format'],
            containsPair('type', 'json_schema'),
          );
          expect(((body['tools'] as List).single as Map)['name'], 'lookup');
        },
      );
      final request = ModelRequest(
        messages: [
          ChatMessage(
            id: 'u',
            role: MessageRole.user,
            content: const [
              TextPart('Look'),
              ImagePart('https://example.com/a.png'),
              FilePart('file-1'),
            ],
          ),
          ChatMessage(
            id: 'a',
            role: MessageRole.assistant,
            toolCalls: [
              ToolCall(id: 'call', name: 'lookup', arguments: {'id': 42}),
            ],
          ),
          ChatMessage(
            id: 'result',
            role: MessageRole.tool,
            toolCallId: 'call',
            content: const [TextPart('42')],
          ),
        ],
        tools: const [
          ModelTool(
            name: 'lookup',
            description: 'Look up',
            inputSchema: {'type': 'object'},
          ),
        ],
        outputSchema: const {'type': 'object'},
      );
      await openai.OpenAIResponsesModel(
        client: client,
        model: 'fixture',
      ).stream(request, cancellation: CancellationToken()).drain<void>();
    },
  );

  test(
    'Chat Completions accumulates fragmented tool arguments and trailing usage',
    () async {
      final client = fixtureClient(
        [
          chatEvent(delta: {'content': 'Checking'}),
          chatEvent(
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
          chatEvent(
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
          chatEvent(
            usage: {
              'prompt_tokens': 5,
              'completion_tokens': 2,
              'total_tokens': 7,
            },
          ),
        ],
        (request) {
          expect(request.url.path, '/v1/chat/completions');
          final body = jsonDecode(request.body) as Map;
          expect(body['max_completion_tokens'], 16);
          expect(body['stream_options'], {'include_usage': true});
        },
      );
      final events = await openai.OpenAIChatModel(
        client: client,
        model: 'fixture',
      ).stream(modelRequest, cancellation: CancellationToken()).toList();
      expect(events.map((e) => e.runtimeType), [
        TextDelta,
        TokenUsage,
        ToolCallReady,
        ModelFinished,
      ]);
      expect((events[2] as ToolCallReady).call.arguments, {'id': 42});
      expect((events.last as ModelFinished).reason, 'tool_calls');
    },
  );

  test('Chat Completions rejects streams without finish reason', () async {
    final client = fixtureClient([
      chatEvent(delta: {'content': 'partial'}),
    ], (_) {});
    await expectLater(
      openai.OpenAIChatModel(
        client: client,
        model: 'fixture',
      ).stream(modelRequest, cancellation: CancellationToken()).toList(),
      throwsStateError,
    );
  });

  for (final responses in [true, false]) {
    test(
      '${responses ? 'Responses' : 'Chat'} pre-cancellation sends no HTTP request',
      () async {
        var calls = 0;
        final client = fixtureClient([], (_) => calls++);
        final ChatModel model = responses
            ? openai.OpenAIResponsesModel(client: client, model: 'fixture')
            : openai.OpenAIChatModel(client: client, model: 'fixture');
        await expectLater(
          model
              .stream(modelRequest, cancellation: CancellationToken()..cancel())
              .toList(),
          throwsA(isA<RunCancelled>()),
        );
        expect(calls, 0);
      },
    );
  }

  test('typed provider configuration remains available', () async {
    final client = fixtureClient(
      [
        responseEvent('response.completed', {'response': responseJson()}),
      ],
      (request) =>
          expect((jsonDecode(request.body) as Map)['temperature'], 0.2),
    );
    await openai.OpenAIResponsesModel(
      client: client,
      model: 'fixture',
      configure: (request) => request.copyWith(temperature: 0.2),
    ).stream(modelRequest, cancellation: CancellationToken()).drain<void>();
  });
}
