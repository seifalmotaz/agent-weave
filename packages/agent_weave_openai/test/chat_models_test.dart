import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> responseJson() => {
  'id': 'response',
  'object': 'response',
  'created_at': 0,
  'status': 'completed',
  'model': 'fixture',
  'output': <Object>[],
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
      responseEvent('response.completed', {'response': responseJson()}),
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
