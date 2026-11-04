import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:test/test.dart';
import 'chat_models_test.dart' as fixture;

final annotations = <JsonObject>[
  {
    'type': 'file_citation',
    'file_id': 'f1',
    'filename': 'one.pdf',
    'index': 2,
    'secret': 'private',
  },
  {
    'type': 'url_citation',
    'url': 'https://example.com',
    'title': 'site',
    'start_index': 1,
    'end_index': 9,
  },
  {
    'type': 'container_file_citation',
    'container_id': 'c',
    'file_id': 'f2',
    'filename': 'two.pdf',
    'start_index': 0,
    'end_index': 0,
  },
  {'type': 'file_path', 'file_id': 'f3', 'index': 999},
];
JsonObject msg(List<Object?> anns, {String text = '😀x', String id = 'm'}) => {
  'type': 'message',
  'id': id,
  'role': 'assistant',
  'content': [
    {'type': 'output_text', 'text': text, 'annotations': anns},
  ],
};
JsonObject terminal(List<JsonObject> output) => {
  'type': 'response.completed',
  'response': {'status': 'completed', 'model': 'x', 'output': output},
};
JsonObject added(int index, Object? a) => {
  'type': 'response.output_text.annotation.added',
  'output_index': 0,
  'content_index': 0,
  'annotation_index': index,
  'item_id': 'm',
  'annotation': a,
};
api.ResponsesProtocolModel model(
  List<JsonObject> events, {
  String provider = 'openai.responses',
}) => api.ResponsesProtocolModel.native(
  model: 'x',
  providerDataKey: provider,
  transport: (_, _) => Stream.fromIterable(events),
);
final request = ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]);
void main() {
  test('all variants reconcile echoes and preserve private metadata', () async {
    final output = msg(annotations);
    final events = [
      {
        'type': 'response.output_item.added',
        'output_index': 0,
        'item': {'type': 'message', 'id': 'm', 'content': <Object>[]},
      },
      {
        'type': 'response.content_part.added',
        'output_index': 0,
        'content_index': 0,
        'item_id': 'm',
        'part': {'type': 'output_text', 'text': '', 'annotations': <Object>[]},
      },
      {'type': 'response.output_text.delta', 'delta': '😀x'},
      for (var i = 0; i < annotations.length; i++) added(i, annotations[i]),
      added(0, null),
      {
        'type': 'response.content_part.done',
        'output_index': 0,
        'content_index': 0,
        'item_id': 'm',
        'part': (output['content'] as List).single,
      },
      {'type': 'response.output_item.done', 'output_index': 0, 'item': output},
      terminal([output]),
    ];
    final result = await model(
      events,
    ).stream(request, cancellation: CancellationToken()).toList();
    final refs = result
        .whereType<ReferenceReady>()
        .map((v) => v.reference)
        .toList();
    expect(refs.length, 4);
    expect(refs.map((r) => [r.partStart, r.partEnd]), everyElement([0, 3]));
    expect(refs.map((r) => r.position.runtimeType), [
      ProviderTextPosition,
      ProviderTextRange,
      ProviderTextRange,
      FileListPosition,
    ]);
    expect(refs[2].position.toJson(), {
      'type': 'text_range',
      'start': 0,
      'end': 0,
    });
    expect(refs[3].position.toJson(), {'type': 'file_list', 'index': 999});
    expect((refs[3].source as FileCitationSource).filename, isNull);
    expect(refs.first.toJson().toString(), isNot(contains('private')));
    expect(result.whereType<ProviderOutput>().first.items.single, output);
  });
  test(
    'multiple parts and refusal offsets, empty parts and terminal-only',
    () async {
      final output = <JsonObject>[
        {
          'type': 'message',
          'id': 'm',
          'role': 'assistant',
          'content': [
            {'type': 'refusal', 'refusal': 'N😀'},
            {
              'type': 'output_text',
              'text': '',
              'annotations': [annotations[3]],
            },
            {
              'type': 'output_text',
              'text': 'ab',
              'annotations': [annotations[0]],
            },
          ],
        },
        msg([annotations[1]], id: 'm2', text: 'z'),
      ];
      final result = await model([
        terminal(output),
      ]).stream(request, cancellation: CancellationToken()).toList();
      expect(
        result.whereType<ReferenceReady>().map(
          (r) => [r.reference.partStart, r.reference.partEnd],
        ),
        [
          [3, 3],
          [3, 5],
          [5, 6],
        ],
      );
      expect(result.whereType<TextDelta>().single.text, 'N😀abz');
    },
  );
  test(
    'rejects conflicting, missing, unknown and mismatched records',
    () async {
      final invalid = <List<JsonObject>>[
        [
          added(0, {...annotations[0], 'file_id': 'different'}),
          terminal([msg(annotations)]),
        ],
        [
          added(7, annotations[0]),
          terminal([msg(annotations)]),
        ],
        [
          terminal([
            msg([
              {'type': 'new', 'secret': 'x'},
            ]),
          ]),
        ],
        [
          terminal([
            msg([null]),
          ]),
        ],
        [
          {'type': 'response.output_text.delta', 'delta': 'different'},
          terminal([msg(annotations)]),
        ],
        [
          {
            'type': 'response.content_part.done',
            'output_index': 0,
            'content_index': 0,
            'item_id': 'm',
            'part': {
              'type': 'output_text',
              'text': 'different',
              'annotations': annotations,
            },
          },
          terminal([msg(annotations)]),
        ],
      ];
      for (final events in invalid) {
        final seen = <ModelEvent>[];
        await expectLater(
          model(events).stream(request, cancellation: CancellationToken()).map((
            x,
          ) {
            seen.add(x);
            return x;
          }).toList(),
          throwsA(anything),
        );
        expect(seen.whereType<ReferenceReady>(), isEmpty);
      }
    },
  );
  test('EOF and cancellation never publish references or tool calls', () async {
    final tool = {
      'type': 'function_call',
      'id': 'item',
      'call_id': 'call',
      'name': 'tool',
      'arguments': '{}',
    };
    final events = [
      added(0, annotations[0]),
      {'type': 'response.output_item.done', 'item': tool},
    ];
    final seen = <ModelEvent>[];
    await expectLater(
      model(events).stream(request, cancellation: CancellationToken()).map((e) {
        seen.add(e);
        return e;
      }).toList(),
      throwsStateError,
    );
    expect(seen.whereType<ReferenceReady>(), isEmpty);
    expect(seen.whereType<ToolCallReady>(), isEmpty);
    final cancelled = CancellationToken()..cancel();
    await expectLater(
      model([
        terminal([msg(annotations)]),
      ]).stream(request, cancellation: cancelled).toList(),
      throwsA(isA<RunCancelled>()),
    );
  });
  test('compatible provider does not reinterpret OpenAI annotations', () async {
    final result = await model(
      [
        terminal([
          msg([
            {'type': 'unknown'},
          ]),
        ]),
      ],
      provider: 'other.responses',
    ).stream(request, cancellation: CancellationToken()).toList();
    expect(result.whereType<ReferenceReady>(), isEmpty);
  });
  test(
    'native SDK stream preserves annotation event and private replay',
    () async {
      final output = msg(annotations, text: 'text');
      var calls = 0;
      final client = fixture.fixtureClient(
        [
          added(0, annotations[0]),
          terminal([output]),
        ],
        (request) {
          if (calls++ == 1) {
            expect(request.body, contains('private'));
          }
        },
      );
      final instance = api.OpenAIResponsesModel(client: client, model: 'x');
      final result = await instance
          .stream(request, cancellation: CancellationToken())
          .toList();
      final replay = result.whereType<ProviderOutput>().first.items;
      expect(result.whereType<ReferenceReady>().length, 4);
      await instance
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  providerData: {'openai.responses': replay},
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(calls, 2);
    },
  );
  test(
    'buffered Chat emits URL refs and preserves raw message without replaying it',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final transport = MockClient((r) async {
        bodies.add(jsonDecode(r.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'id': 'x',
            'model': 'fixture',
            'choices': [
              {
                'index': 0,
                'finish_reason': 'stop',
                'message': {
                  'role': 'assistant',
                  'content': 'hello',
                  'annotations': [
                    {
                      'type': 'url_citation',
                      'url_citation': {
                        'url': 'https://example.com',
                        'title': 'Site',
                        'start_index': 0,
                        'end_index': 3,
                        'secret': 'hidden',
                      },
                    },
                  ],
                },
              },
            ],
            'usage': {'prompt_tokens': 2, 'completion_tokens': 3},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = api.OpenAIClient(
        config: const api.OpenAIConfig(
          authProvider: api.ApiKeyProvider('key'),
          retryPolicy: api.RetryPolicy(maxRetries: 0),
        ),
        httpClient: transport,
        streamClientFactory: () => transport,
      );
      addTearDown(() {
        client.close();
        transport.close();
      });
      final instance = api.OpenAIChatModel(
        client: client,
        model: 'fixture',
        streamText: false,
      );
      final req = ModelRequest(
        messages: [ChatMessage.user('Hi', id: 'u')],
        tools: [
          const ModelTool(
            name: 'tool',
            description: 'tool',
            inputSchema: {'type': 'object', 'properties': <String, Object?>{}},
          ),
        ],
        outputSchema: {'type': 'object'},
      );
      final result = await instance
          .stream(req, cancellation: CancellationToken())
          .toList();
      expect(bodies.first['stream'], false);
      expect(bodies.first.containsKey('stream_options'), false);
      expect(bodies.first['tools'], isNotEmpty);
      expect(bodies.first['response_format'], isNotNull);
      final ref = result.whereType<ReferenceReady>().single.reference;
      expect([ref.partStart, ref.partEnd], [0, 5]);
      expect(ref.position.toJson(), {
        'type': 'text_range',
        'start': 0,
        'end': 3,
      });
      expect(ref.toJson().toString(), isNot(contains('hidden')));
      final replay = result.whereType<ProviderOutput>().single;
      expect(replay.items.single.toString(), contains('hidden'));
      await instance
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  content: [const TextPart('hello')],
                  providerData: {replay.provider: replay.items},
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(bodies.last.toString(), isNot(contains('hidden')));
    },
  );
  test(
    'buffered Chat rejects malformed refs before emitting tool call',
    () async {
      final transport = MockClient(
        (r) async => http.Response(
          jsonEncode({
            'model': 'fixture',
            'choices': [
              {
                'index': 0,
                'finish_reason': 'tool_calls',
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 't',
                      'type': 'function',
                      'function': {'name': 'tool', 'arguments': '{}'},
                    },
                  ],
                  'annotations': [
                    {
                      'type': 'url_citation',
                      'url_citation': {
                        'url': 'javascript:bad',
                        'title': 'bad',
                        'start_index': 0,
                        'end_index': 1,
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
        ),
      );
      final client = api.OpenAIClient(
        config: const api.OpenAIConfig(
          authProvider: api.ApiKeyProvider('key'),
          retryPolicy: api.RetryPolicy(maxRetries: 0),
        ),
        httpClient: transport,
        streamClientFactory: () => transport,
      );
      addTearDown(() {
        client.close();
        transport.close();
      });
      final seen = <ModelEvent>[];
      await expectLater(
        api.OpenAIChatModel(
          client: client,
          model: 'x',
          streamText: false,
        ).stream(request, cancellation: CancellationToken()).map((e) {
          seen.add(e);
          return e;
        }).toList(),
        throwsFormatException,
      );
      expect(seen.whereType<ToolCallReady>(), isEmpty);
    },
  );
  test(
    'streaming Chat rejects annotation deltas and HTTP 200 error bodies',
    () async {
      for (final event in [
        {
          'choices': [
            {
              'index': 0,
              'delta': {'annotations': <Object>[]},
              'finish_reason': null,
            },
          ],
        },
        {
          'error': {'message': 'failed'},
        },
      ]) {
        final client = fixture.fixtureClient([event], (_) {});
        await expectLater(
          api.OpenAIChatModel(
            client: client,
            model: 'x',
          ).stream(request, cancellation: CancellationToken()).toList(),
          throwsA(anything),
        );
      }
    },
  );
  test(
    'cancelling a buffered Chat request leaves its sibling running',
    () async {
      final started = Completer<void>();
      var calls = 0;
      final transport = MockClient.streaming((request, body) async {
        await body.toBytes();
        if (calls++ == 0) {
          started.complete();
          await (request as http.Abortable).abortTrigger;
          throw http.RequestAbortedException(request.url);
        }
        final response = jsonEncode({
          'model': 'x',
          'choices': [
            {
              'index': 0,
              'finish_reason': 'stop',
              'message': {'role': 'assistant', 'content': 'ok'},
            },
          ],
        });
        return http.StreamedResponse(
          Stream.value(utf8.encode(response)),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = api.OpenAIClient(
        config: const api.OpenAIConfig(
          authProvider: api.ApiKeyProvider('key'),
          retryPolicy: api.RetryPolicy(maxRetries: 0),
        ),
        httpClient: transport,
        streamClientFactory: () => transport,
      );
      addTearDown(() {
        client.close();
        transport.close();
      });
      final instance = api.OpenAIChatModel(
        client: client,
        model: 'x',
        streamText: false,
      );
      final cancelled = CancellationToken();
      final pending = instance
          .stream(request, cancellation: cancelled)
          .toList();
      final failure = expectLater(pending, throwsA(isA<RunCancelled>()));
      await started.future;
      final sibling = instance
          .stream(request, cancellation: CancellationToken())
          .toList();
      cancelled.cancel();
      await failure;
      expect((await sibling).whereType<TextDelta>().single.text, 'ok');
    },
  );
  test(
    'buffered Chat validates text and rejects audio without annotations',
    () async {
      for (final message in <Map<String, Object?>>[
        {
          'role': 'assistant',
          'content': {'bad': 'content'},
        },
        {
          'role': 'assistant',
          'content': 'text',
          'refusal': ['bad'],
        },
        {
          'role': 'assistant',
          'content': 'text',
          'audio': {'id': 'a'},
        },
      ]) {
        final transport = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'model': 'x',
              'choices': [
                {'index': 0, 'finish_reason': 'stop', 'message': message},
              ],
            }),
            200,
          ),
        );
        final client = api.OpenAIClient(
          config: const api.OpenAIConfig(
            authProvider: api.ApiKeyProvider('key'),
            retryPolicy: api.RetryPolicy(maxRetries: 0),
          ),
          httpClient: transport,
          streamClientFactory: () => transport,
        );
        final seen = <ModelEvent>[];
        await expectLater(
          api.OpenAIChatModel(
            client: client,
            model: 'x',
            streamText: false,
          ).stream(request, cancellation: CancellationToken()).map((event) {
            seen.add(event);
            return event;
          }).toList(),
          throwsA(anything),
        );
        expect(seen.whereType<ModelFinished>(), isEmpty);
        client.close();
        transport.close();
      }
    },
  );
  test(
    'streaming Chat permits empty annotations and rejects invalid values',
    () async {
      for (final annotations in <Object>[
        <Object>[],
        'bad',
        [
          <String, Object?>{'type': 'url_citation'},
        ],
      ]) {
        final client = fixture.fixtureClient([
          {
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'ok', 'annotations': annotations},
                'finish_reason': 'stop',
              },
            ],
          },
        ], (_) {});
        final result = api.OpenAIChatModel(
          client: client,
          model: 'x',
        ).stream(request, cancellation: CancellationToken()).toList();
        if (annotations is List && annotations.isEmpty) {
          expect((await result).whereType<TextDelta>().single.text, 'ok');
        } else {
          await expectLater(result, throwsUnsupportedError);
        }
      }
    },
  );
  test('Chat nested discriminator cannot fabricate a file reference', () async {
    final transport = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'model': 'x',
          'choices': [
            {
              'index': 0,
              'finish_reason': 'stop',
              'message': {
                'role': 'assistant',
                'content': 'ok',
                'annotations': [
                  {
                    'type': 'url_citation',
                    'url_citation': {
                      'type': 'file_citation',
                      'file_id': 'fake',
                      'filename': 'fake',
                      'index': 0,
                      'url': 'https://example.com',
                      'title': 'site',
                      'start_index': 0,
                      'end_index': 1,
                    },
                  },
                ],
              },
            },
          ],
        }),
        200,
      ),
    );
    final client = api.OpenAIClient(
      config: const api.OpenAIConfig(
        authProvider: api.ApiKeyProvider('key'),
        retryPolicy: api.RetryPolicy(maxRetries: 0),
      ),
      httpClient: transport,
      streamClientFactory: () => transport,
    );
    addTearDown(() {
      client.close();
      transport.close();
    });
    final result = await api.OpenAIChatModel(
      client: client,
      model: 'x',
      streamText: false,
    ).stream(request, cancellation: CancellationToken()).toList();
    expect(
      result.whereType<ReferenceReady>().single.reference.source,
      isA<UrlCitationSource>(),
    );
    expect(
      result.whereType<ProviderOutput>().single.items.single.toString(),
      contains('fake'),
    );
  });
  test(
    'native Responses rejects unknown message content before tools',
    () async {
      final output = <JsonObject>[
        {
          'type': 'message',
          'id': 'm',
          'content': [
            {'type': 'future_part', 'text': 'hidden'},
          ],
        },
        {
          'type': 'function_call',
          'id': 'item',
          'call_id': 'call',
          'name': 'tool',
          'arguments': '{}',
        },
      ];
      final seen = <ModelEvent>[];
      await expectLater(
        model([
          terminal(output),
        ]).stream(request, cancellation: CancellationToken()).map((e) {
          seen.add(e);
          return e;
        }).toList(),
        throwsUnsupportedError,
      );
      expect(seen.whereType<ToolCallReady>(), isEmpty);
      expect(seen.whereType<ReferenceReady>(), isEmpty);
      final compatible = await model(
        [terminal(output.take(1).toList())],
        provider: 'other.responses',
      ).stream(request, cancellation: CancellationToken()).toList();
      expect(compatible.whereType<ModelFinished>(), hasLength(1));
    },
  );
  test(
    'native Chat stream gates tool calls on a consistent final reason',
    () async {
      final toolDelta = {
        'choices': [
          {
            'index': 0,
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 't',
                  'type': 'function',
                  'function': {'name': 'tool', 'arguments': '{}'},
                },
              ],
            },
            'finish_reason': null,
          },
        ],
      };
      JsonObject finish(String reason) => {
        'choices': [
          {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': reason},
        ],
      };
      for (final reason in ['unknown', 'content_filter', 'stop', 'length']) {
        final client = fixture.fixtureClient([
          toolDelta,
          finish(reason),
        ], (_) {});
        final seen = <ModelEvent>[];
        await expectLater(
          api.OpenAIChatModel(
            client: client,
            model: 'x',
          ).stream(request, cancellation: CancellationToken()).map((e) {
            seen.add(e);
            return e;
          }).toList(),
          throwsA(anything),
        );
        expect(seen.whereType<ToolCallReady>(), isEmpty);
      }
      final valid = fixture.fixtureClient([
        toolDelta,
        finish('tool_calls'),
        {
          'choices': <Object>[],
          'usage': {'prompt_tokens': 1, 'completion_tokens': 1},
        },
      ], (_) {});
      final result = await api.OpenAIChatModel(
        client: valid,
        model: 'x',
      ).stream(request, cancellation: CancellationToken()).toList();
      expect(result.whereType<ToolCallReady>(), hasLength(1));
      final late = fixture.fixtureClient([finish('stop'), toolDelta], (_) {});
      await expectLater(
        api.OpenAIChatModel(
          client: late,
          model: 'x',
        ).stream(request, cancellation: CancellationToken()).toList(),
        throwsFormatException,
      );
      final absent = fixture.fixtureClient([finish('tool_calls')], (_) {});
      await expectLater(
        api.OpenAIChatModel(
          client: absent,
          model: 'x',
        ).stream(request, cancellation: CancellationToken()).toList(),
        throwsFormatException,
      );
    },
  );
  test('loopback Chat stream rejects a filtered tool call', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      for (final event in [
        {
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 't',
                    'type': 'function',
                    'function': {'name': 'tool', 'arguments': '{}'},
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
              'delta': <String, Object?>{},
              'finish_reason': 'content_filter',
            },
          ],
        },
      ]) {
        request.response.write('data: ${jsonEncode(event)}\n\n');
      }
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
    final client = api.OpenAIClient(
      config: api.OpenAIConfig(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        authProvider: const api.ApiKeyProvider('local'),
        retryPolicy: const api.RetryPolicy(maxRetries: 0),
      ),
    );
    addTearDown(client.close);
    final seen = <ModelEvent>[];
    await expectLater(
      api.OpenAIChatModel(
        client: client,
        model: 'x',
      ).stream(request, cancellation: CancellationToken()).map((e) {
        seen.add(e);
        return e;
      }).toList(),
      throwsFormatException,
    );
    expect(seen.whereType<ToolCallReady>(), isEmpty);
  });
  test(
    'nullable annotation placeholder without terminal annotation emits no reference',
    () async {
      final result = await model([
        added(0, null),
        terminal([msg(<Object?>[])]),
      ]).stream(request, cancellation: CancellationToken()).toList();
      expect(result.whereType<ReferenceReady>(), isEmpty);
      expect(result.whereType<ModelFinished>(), hasLength(1));
      final invalid = {...added(0, null), 'item_id': 'other'};
      await expectLater(
        model([
          invalid,
          terminal([msg(<Object?>[])]),
        ]).stream(request, cancellation: CancellationToken()).toList(),
        throwsFormatException,
      );
    },
  );
}
