import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart'
    show AnthropicChatModel;
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Map<String, Object?> start() => {
  'type': 'message_start',
  'message': {
    'id': 'm',
    'type': 'message',
    'role': 'assistant',
    'model': 'fixture',
    'content': <Object>[],
    'usage': {
      'input_tokens': 12,
      'output_tokens': 0,
      'cache_read_input_tokens': 4,
    },
  },
};
Map<String, Object?> block(int index, Map<String, Object?> content) => {
  'type': 'content_block_start',
  'index': index,
  'content_block': content,
};
Map<String, Object?> delta(int index, Map<String, Object?> content) => {
  'type': 'content_block_delta',
  'index': index,
  'delta': content,
};
Map<String, Object?> stop(int index) => {
  'type': 'content_block_stop',
  'index': index,
};
Map<String, Object?> finish([String reason = 'tool_use']) => {
  'type': 'message_delta',
  'delta': {'stop_reason': reason, 'stop_sequence': null},
  'usage': {'output_tokens': 8},
};
final done = {'type': 'message_stop'};

api.AnthropicClient fixture(
  List<Map<String, Object?>> events,
  void Function(http.Request) inspect,
) {
  final transport = MockClient((request) async {
    inspect(request);
    return http.Response(
      events
          .map(
            (event) =>
                'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
          )
          .join(),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  });
  final client = api.AnthropicClient.withApiKey(
    'fixture',
    httpClient: transport,
  );
  addTearDown(() {
    client.close();
    transport.close();
  });
  return client;
}

final request = ModelRequest(
  messages: [ChatMessage.user('Hi', id: '1')],
  instructions: 'brief',
  maxOutputTokens: 64,
  tools: [
    const ModelTool(
      name: 'lookup',
      description: 'Look up',
      inputSchema: {'type': 'object', 'properties': {}},
    ),
  ],
);
void main() {
  for (final (part, source) in <(DocumentPart, Map<String, Object?>)>[
    (
      DocumentPart.url(
        'https://example.com/report.pdf',
        filename: 'report.pdf',
      ),
      {'type': 'url', 'url': 'https://example.com/report.pdf'},
    ),
    (
      DocumentPart.bytes(
        utf8.encode('fixture'),
        mimeType: 'application/pdf',
        filename: 'report.pdf',
      ),
      {
        'type': 'base64',
        'media_type': 'application/pdf',
        'data': 'Zml4dHVyZQ==',
      },
    ),
    (
      DocumentPart.bytes(
        utf8.encode('مرحبا'),
        mimeType: 'text/plain',
        filename: 'report.pdf',
      ),
      {'type': 'text', 'media_type': 'text/plain', 'data': 'مرحبا'},
    ),
  ]) {
    test(
      'Messages encodes ${part.runtimeType} document as the native source',
      () async {
        final client = fixture([start(), finish('end_turn'), done], (request) {
          final body = jsonDecode(request.body) as Map;
          final content =
              (((body['messages'] as List).single as Map)['content'] as List)
                      .single
                  as Map;
          expect(content['type'], 'document');
          expect(content['source'], source);
          expect(content['title'], 'report.pdf');
        });
        await AnthropicChatModel(client: client, model: 'fixture')
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
  for (final part in <DocumentPart>[
    DocumentPart.fileId('file', provider: 'anthropic'),
    DocumentPart.bytes([1, 2, 3], mimeType: 'application/zip'),
  ]) {
    test(
      'unsupported native document source fails before dispatch: ${part.runtimeType}',
      () async {
        final client = fixture([], (_) => fail('Must not submit'));
        await expectLater(
          AnthropicChatModel(client: client, model: 'fixture')
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
          throwsUnsupportedError,
        );
      },
    );
  }

  test(
    'streams tools, thinking and usage, and replays the exact blocks',
    () async {
      final events = [
        start(),
        block(0, {'type': 'thinking', 'thinking': '', 'signature': ''}),
        delta(0, {'type': 'thinking_delta', 'thinking': 'reason'}),
        delta(0, {'type': 'signature_delta', 'signature': 'signed'}),
        stop(0),
        block(1, {'type': 'redacted_thinking', 'data': 'secret'}),
        stop(1),
        block(2, {
          'type': 'tool_use',
          'id': 't1',
          'name': 'lookup',
          'input': {},
        }),
        delta(2, {'type': 'input_json_delta', 'partial_json': '{"x":'}),
        delta(2, {'type': 'input_json_delta', 'partial_json': '1}'}),
        stop(2),
        block(3, {
          'type': 'tool_use',
          'id': 't2',
          'name': 'lookup',
          'input': {},
        }),
        delta(3, {'type': 'input_json_delta', 'partial_json': '{}'}),
        stop(3),
        finish(),
        done,
      ];
      var count = 0;
      late List<JsonObject> replay;
      final client = fixture(events, (httpRequest) {
        expect(httpRequest.url.path, '/v1/messages');
        expect(httpRequest.headers['x-api-key'], 'fixture');
        expect(httpRequest.headers['anthropic-version'], isNotEmpty);
        expect(httpRequest.headers['anthropic-beta'], 'fixture-beta');
        final body = jsonDecode(httpRequest.body) as Map;
        expect(body['system'], 'brief');
        expect(body['stream'], true);
        expect(body['temperature'], 0.2);
        if (count++ == 1) {
          final messages = body['messages'] as List;
          expect(messages[1]['content'], replay);
          expect(messages[2]['role'], 'user');
          expect(messages[2]['content'][0]['tool_use_id'], 't1');
        }
      });
      final model = AnthropicChatModel(
        client: client,
        model: 'fixture',
        betas: ['fixture-beta'],
        configure: (r) => r.copyWith(temperature: 0.2),
      );
      final result = await model
          .stream(request, cancellation: CancellationToken())
          .toList();
      expect(
        result.whereType<ToolCallReady>().map((e) => e.call.arguments).toList(),
        [
          {'x': 1},
          <String, Object?>{},
        ],
      );
      expect(result.whereType<ReasoningDelta>().single.text, 'reason');
      expect(result.whereType<TokenUsage>().single.cachedInputTokens, 4);
      expect(result.whereType<TokenUsage>().single.inputTokens, 16);
      expect(result.whereType<ModelFinished>().single.reason, 'tool_calls');
      replay = result
          .whereType<ProviderOutput>()
          .singleWhere((output) => output.provider == 'anthropic.messages')
          .items;
      expect(replay[0]['signature'], 'signed');
      await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage.user('Hi', id: '1'),
                ChatMessage(
                  id: '2',
                  role: MessageRole.assistant,
                  providerData: {'anthropic.messages': replay},
                ),
                ChatMessage(
                  id: '3',
                  role: MessageRole.tool,
                  toolCallId: 't1',
                  content: [const TextPart('ok')],
                ),
              ],
              instructions: 'brief',
            ),
            cancellation: CancellationToken(),
          )
          .toList();
    },
  );
  test('text, malformed streams and runtime-owned configuration', () async {
    final client = fixture([
      start(),
      block(0, {'type': 'text', 'text': ''}),
      delta(0, {'type': 'text_delta', 'text': 'hello'}),
      stop(0),
      finish('end_turn'),
      done,
    ], (_) {});
    final result = await AnthropicChatModel(
      client: client,
      model: 'fixture',
    ).stream(request, cancellation: CancellationToken()).toList();
    expect(result.whereType<TextDelta>().single.text, 'hello');
    final truncated = fixture([start()], (_) {});
    await expectLater(
      AnthropicChatModel(
        client: truncated,
        model: 'fixture',
      ).stream(request, cancellation: CancellationToken()).toList(),
      throwsStateError,
    );
    await expectLater(
      AnthropicChatModel(
        client: client,
        model: 'fixture',
        configure: (r) => r.copyWith(maxTokens: 10),
      ).stream(request, cancellation: CancellationToken()).toList(),
      throwsArgumentError,
    );
    final cancelled = CancellationToken()..cancel();
    await expectLater(
      AnthropicChatModel(
        client: client,
        model: 'fixture',
      ).stream(request, cancellation: cancelled).toList(),
      throwsA(isA<RunCancelled>()),
    );
  });
  test(
    'stream errors and cancellation after a delta fail the invocation',
    () async {
      final errorClient = fixture([
        start(),
        {
          'type': 'error',
          'error': {'type': 'overloaded_error', 'message': 'busy'},
        },
      ], (_) {});
      await expectLater(
        AnthropicChatModel(
          client: errorClient,
          model: 'fixture',
        ).stream(request, cancellation: CancellationToken()).toList(),
        throwsA(anything),
      );
      final client = fixture([
        start(),
        block(0, {'type': 'text', 'text': ''}),
        delta(0, {'type': 'text_delta', 'text': 'hello'}),
        stop(0),
        finish('end_turn'),
        done,
      ], (_) {});
      final token = CancellationToken();
      await expectLater(
        AnthropicChatModel(
          client: client,
          model: 'fixture',
        ).stream(request, cancellation: token).map((event) {
          if (event is TextDelta) token.cancel();
          return event;
        }).toList(),
        throwsA(isA<RunCancelled>()),
      );
    },
  );
  test('rejects unsupported content and incomplete tool JSON', () async {
    final bad = fixture([
      start(),
      block(0, {
        'type': 'tool_use',
        'id': 't',
        'name': 'lookup',
        'input': <String, Object?>{},
      }),
      delta(0, {'type': 'input_json_delta', 'partial_json': '{"x":'}),
      stop(0),
      finish(),
      done,
    ], (_) {});
    final model = AnthropicChatModel(client: bad, model: 'fixture');
    await expectLater(
      model.stream(request, cancellation: CancellationToken()).toList(),
      throwsFormatException,
    );
    await expectLater(
      model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'f',
                  role: MessageRole.user,
                  content: [const FilePart('file-id')],
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsUnsupportedError,
    );
    final unclosed = fixture([
      start(),
      block(0, {'type': 'text', 'text': ''}),
      finish('end_turn'),
      done,
    ], (_) {});
    await expectLater(
      AnthropicChatModel(
        client: unclosed,
        model: 'fixture',
      ).stream(request, cancellation: CancellationToken()).toList(),
      throwsStateError,
    );
  });
  test('structured output is sent and protected', () async {
    final client = fixture([start(), finish('end_turn'), done], (r) {
      final body = jsonDecode(r.body) as Map;
      expect(body['output_config']['format'], {
        'type': 'json_schema',
        'schema': {'type': 'object'},
      });
    });
    final req = ModelRequest(
      messages: [ChatMessage.user('x', id: '1')],
      outputSchema: {'type': 'object'},
    );
    await AnthropicChatModel(
      client: client,
      model: 'fixture',
    ).stream(req, cancellation: CancellationToken()).toList();
    await expectLater(
      AnthropicChatModel(
        client: client,
        model: 'fixture',
        configure: (r) => r.copyWith(outputConfig: const api.OutputConfig()),
      ).stream(req, cancellation: CancellationToken()).toList(),
      throwsArgumentError,
    );
  });
  test('rejects server tools and events after stop', () async {
    final client = fixture([
      start(),
      block(0, {
        'type': 'server_tool_use',
        'id': 's',
        'name': 'web_search',
        'input': <String, Object?>{},
      }),
    ], (_) {});
    await expectLater(
      AnthropicChatModel(
        client: client,
        model: 'fixture',
      ).stream(request, cancellation: CancellationToken()).toList(),
      throwsUnsupportedError,
    );
    final after = fixture([start(), finish('end_turn'), done, done], (_) {});
    await expectLater(
      AnthropicChatModel(
        client: after,
        model: 'fixture',
      ).stream(request, cancellation: CancellationToken()).toList(),
      throwsFormatException,
    );
  });
  test('maps finish reasons and emits initial content', () async {
    for (final entry in {
      'max_tokens': 'length',
      'end_turn': 'stop',
      'stop_sequence': 'stop',
      'tool_use': 'tool_calls',
    }.entries) {
      final client = fixture([
        start(),
        block(0, {'type': 'text', 'text': 'initial'}),
        stop(0),
        finish(entry.key),
        done,
      ], (_) {});
      final result = await AnthropicChatModel(
        client: client,
        model: 'fixture',
      ).stream(request, cancellation: CancellationToken()).toList();
      expect(result.whereType<TextDelta>().single.text, 'initial');
      expect(result.whereType<ModelFinished>().single.reason, entry.value);
    }
    final pause = fixture([start(), finish('pause_turn'), done], (_) {});
    await expectLater(
      AnthropicChatModel(
        client: pause,
        model: 'fixture',
      ).stream(request, cancellation: CancellationToken()).toList(),
      throwsUnsupportedError,
    );
  });
  test(
    'cache breakpoints and strict tool preserve runtime-owned values',
    () async {
      final client = fixture([start(), finish('end_turn'), done], (r) {
        final body = jsonDecode(r.body) as Map;
        expect(body['system'][0]['cache_control']['type'], 'ephemeral');
        expect(
          body['messages'][0]['content'][0]['cache_control']['type'],
          'ephemeral',
        );
        expect(body['tools'][0]['cache_control']['type'], 'ephemeral');
        expect(body['tools'][0]['strict'], true);
      });
      api.MessageCreateRequest decorate(api.MessageCreateRequest r) {
        final data = jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>;
        data['system'] = [
          {
            'type': 'text',
            'text': 'brief',
            'cache_control': {'type': 'ephemeral'},
          },
        ];
        data['messages'][0]['content'][0]['cache_control'] = {
          'type': 'ephemeral',
        };
        data['tools'][0]['cache_control'] = {'type': 'ephemeral'};
        data['tools'][0]['strict'] = true;
        return api.MessageCreateRequest.fromJson(data);
      }

      await AnthropicChatModel(
        client: client,
        model: 'fixture',
        configure: decorate,
      ).stream(request, cancellation: CancellationToken()).toList();
      for (final field in ['messages', 'tools', 'max_tokens']) {
        await expectLater(
          AnthropicChatModel(
            client: client,
            model: 'fixture',
            configure: (r) {
              final data =
                  jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>;
              switch (field) {
                case 'messages':
                  data['messages'][0]['content'][0]['text'] = 'changed';
                case 'tools':
                  data['tools'][0]['input_schema']['properties']['cache_control'] =
                      {'type': 'string'};
                case 'max_tokens':
                  data['max_tokens'] = 1;
              }
              return api.MessageCreateRequest.fromJson(data);
            },
          ).stream(request, cancellation: CancellationToken()).toList(),
          throwsArgumentError,
        );
      }
    },
  );
}
