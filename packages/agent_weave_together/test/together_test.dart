import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_together/agent_weave_together.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late TogetherClient client;
  late Future<void> Function(HttpRequest) handler;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = TogetherClient(
      apiKey: 'secret',
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      headers: {'X-Test': 'yes'},
      query: {'test': 'ok'},
    );
    server.listen((request) => handler(request));
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });
  test(
    'native options snapshot and numeric logprobs; tools, schema and replay',
    () async {
      final stop = ['end'];
      final kwargs = <String, Object?>{
        'nested': <String, Object?>{'a': 1},
      };
      final options = TogetherChatOptions(
        logprobs: 3,
        stop: stop,
        chatTemplateKwargs: kwargs,
        reasoningEnabled: true,
      );
      stop.add('changed');
      (kwargs['nested'] as Map)['a'] = 2;
      handler = (request) async {
        expect(request.uri.queryParameters['test'], 'ok');
        expect(request.headers.value('x-test'), 'yes');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['logprobs'], 3);
        expect(body['stop'], ['end']);
        expect(body['chat_template_kwargs']['nested']['a'], 1);
        expect(body['max_tokens'], 1024);
        expect(body.containsKey('max_completion_tokens'), false);
        expect(body['n'], 1);
        expect(
          body['response_format']['json_schema']['schema']['type'],
          'object',
        );
        expect(body['messages'][0]['reasoning_content'], 'private');
        expect(
          body['messages'][0]['tool_calls'][0]['function']['arguments'],
          '{"x":1}',
        );
        expect(body['messages'][1]['tool_call_id'], 'c1');
        expect(body['messages'][0]['tool_calls'][0]['index'], 0);
        expect(body['tools'][0]['function']['name'], 'lookup');
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        final chunks = [
          'data: {"model":"actual","choices":[{"index":0,"delta":{"reasoning_content":"think","tool_calls":[{"index":0,"id":"c1","function":{"name":"lookup","arguments":"{\\"x\\":"}}]},"finish_reason":null}]}\r\n\r\n',
          'data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"lookup","arguments":"2}"}}]},"finish_reason":"tool_calls"}],\r\ndata: "usage":{"prompt_tokens":3,"completion_tokens":4}}\r\n\r\n',
        ];
        for (final chunk in chunks) {
          for (final byte in utf8.encode(chunk)) {
            request.response.add([byte]);
          }
          await request.response.flush();
        }
        await request.response.close();
      };
      final model = TogetherChatModel(
        client: client,
        model: 'test',
        options: options,
      );
      final events = await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  toolCalls: [
                    ToolCall(id: 'c1', name: 'lookup', arguments: {'x': 1}),
                  ],
                  providerData: {
                    'together.chat': [
                      {'reasoning_content': 'private'},
                    ],
                  },
                ),
                ChatMessage(
                  id: 'b',
                  role: MessageRole.tool,
                  toolCallId: 'c1',
                  content: [const TextPart('done')],
                ),
              ],
              tools: [
                const ModelTool(
                  name: 'lookup',
                  description: 'find',
                  inputSchema: {'type': 'object'},
                ),
              ],
              outputSchema: {'type': 'object'},
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(events.whereType<ToolCallReady>().single.call.arguments, {'x': 2});
      expect(events.whereType<ToolCallReady>().single.call.name, 'lookup');
      expect(events.whereType<ToolCallReady>().single.call.id, 'c1');
      expect(events.whereType<TokenUsage>().single.model, 'actual');
      expect(
        events
            .whereType<ProviderOutput>()
            .single
            .items
            .first['reasoning_content'],
        'think',
      );
    },
  );
  test('bounded text completion preserves the length finish reason', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response.write(
        'data: {"choices":[{"index":0,"delta":{"content":"Partial"},"finish_reason":"length"}]}\n\ndata: [DONE]\n\n',
      );
      await request.response.close();
    };
    final result = await generateText(
      model: TogetherChatModel(client: client, model: 'fixture'),
      prompt: 'Write a long response',
    );
    expect(result.text, 'Partial');
    expect(result.finishReason, 'length');
  });
  test('raw create preserves native data', () async {
    handler = (request) async {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      expect(body['n'], 2);
      expect(body['function_call'], 'auto');
      request.response.write(
        '{"choices":[],"warnings":[{"message":"native"}]}',
      );
      await request.response.close();
    };
    final result = await client.createChat({
      'model': 'x',
      'messages': [],
      'n': 2,
      'function_call': 'auto',
    });
    expect((result['warnings'] as List).single['message'], 'native');
  });
  test('EOF and inline errors fail, HTTP errors redact bodies', () async {
    var step = 0;
    handler = (request) async {
      await request.drain<void>();
      step++;
      if (step == 1) {
        request.response.write('data: {"choices":[]}\n\n');
      }
      if (step == 2) {
        request.response.write('data: {"error":{"message":"secret"}}\n\n');
      }
      if (step == 3) {
        request.response.statusCode = 401;
        request.response.write('secret');
      }
      await request.response.close();
    };
    for (var i = 0; i < 3; i++) {
      try {
        await client.streamChat({'model': 'x'}).toList();
        fail('expected failure');
      } on TogetherException catch (e) {
        expect(e.toString(), isNot(contains('secret')));
      }
    }
  });
  test(
    'HTTP and inline errors retain private immutable diagnostic details',
    () async {
      var mode = 0;
      handler = (request) async {
        await request.drain<void>();
        request.response.headers.set('x-request-id', 'request-123');
        if (mode == 0) {
          request.response.statusCode = 400;
          request.response.write(
            '{"error":{"message":"secret diagnostic","code":"bad_model"}}',
          );
        } else {
          request.response.write(
            'data: {"error":{"message":"secret diagnostic","code":"bad_model"}}\n\n',
          );
        }
        await request.response.close();
      };
      for (mode = 0; mode < 2; mode++) {
        try {
          await generateText(
            model: TogetherChatModel(client: client, model: 'bad-model'),
            prompt: 'Hello',
          );
          fail('must fail');
        } on AgentRunException catch (error) {
          expect(error.code, 'MODEL_FAILED');
          final cause = error.cause as TogetherException;
          expect(cause.requestId, 'request-123');
          expect(cause.details?['error'], {
            'message': 'secret diagnostic',
            'code': 'bad_model',
          });
          expect(
            () => (cause.details!['error'] as Map)['code'] = 'changed',
            throwsUnsupportedError,
          );
          expect(cause.toString(), isNot(contains('secret diagnostic')));
          expect(error.toString(), isNot(contains('secret diagnostic')));
        }
      }
    },
  );
  test('oversized HTTP error bodies are not retained as diagnostics', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response.statusCode = 400;
      request.response.write(jsonEncode({'error': 'x' * (65 * 1024)}));
      await request.response.close();
    };
    await expectLater(
      client.createChat({'model': 'x'}),
      throwsA(
        isA<TogetherException>()
            .having((error) => error.details, 'details', isNull)
            .having((error) => error.statusCode, 'status', 400),
      ),
    );
  });
  test('cancellation aborts while waiting for response headers', () async {
    final started = Completer<void>();
    handler = (request) async {
      await request.drain<void>();
      started.complete();
    };
    final token = CancellationToken();
    final result = client.createChat({'model': 'x'}, cancellation: token);
    await started.future;
    token.cancel();
    await expectLater(result, throwsA(isA<RunCancelled>()));
  });
  test('abort before send and while receiving body', () async {
    final token = CancellationToken()..cancel();
    await expectLater(
      client.streamChat({}, cancellation: token).toList(),
      throwsA(isA<RunCancelled>()),
    );
    final started = Completer<void>();
    handler = (request) async {
      await request.drain<void>();
      request.response.write('data: {"choices":[]}\n\n');
      await request.response.flush();
      started.complete();
    };
    final active = CancellationToken();
    final future = client.streamChat({}, cancellation: active).toList();
    await started.future;
    active.cancel();
    await expectLater(future, throwsA(isA<RunCancelled>()));
  });
  test(
    'cancelling a native stream aborts a pending request without closing the client',
    () async {
      final started = Completer<void>();
      handler = (request) async {
        await request.drain<void>();
        started.complete();
      };
      final subscription = client.streamChat({'model': 'x'}).listen((_) {});
      await started.future;
      await subscription.cancel().timeout(const Duration(seconds: 1));
      handler = (request) async {
        await request.drain<void>();
        request.response.write('{"choices":[]}');
        await request.response.close();
      };
      expect(await client.createChat({'model': 'x'}), {'choices': <Object?>[]});
    },
  );
  test(
    'cancelling chat model while awaiting headers keeps parent active',
    () async {
      final started = Completer<void>();
      handler = (request) async {
        await request.drain<void>();
        started.complete();
      };
      final parent = CancellationToken();
      final subscription = TogetherChatModel(client: client, model: 'x')
          .stream(
            ModelRequest(messages: [ChatMessage.user('hello', id: 'u')]),
            cancellation: parent,
          )
          .listen(null);
      await started.future.timeout(const Duration(seconds: 1));
      await subscription.cancel().timeout(const Duration(seconds: 1));
      expect(parent.isCancelled, isFalse);
    },
  );

  test('request timeout aborts a stalled response body', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response.write('data: {"choices":[]}\n\n');
      await request.response.flush();
    };
    final shortClient = TogetherClient(
      apiKey: 'x',
      baseUrl: 'http://127.0.0.1:${server.port}',
      requestTimeout: const Duration(milliseconds: 80),
    );
    try {
      await expectLater(
        shortClient.streamChat({}).toList(),
        throwsA(
          isA<TogetherException>().having(
            (e) => e.message,
            'message',
            'Request timed out',
          ),
        ),
      );
    } finally {
      shortClient.close();
    }
  });
  test('multiple native choices must finish before EOF', () async {
    var complete = false;
    handler = (request) async {
      await request.drain<void>();
      request.response.write(
        'data: {"choices":[{"index":0,"finish_reason":"stop"}]}\n\n',
      );
      if (complete) {
        request.response.write(
          'data: {"choices":[{"index":1,"finish_reason":"stop"}]}\n\n',
        );
      }
      await request.response.close();
    };
    await expectLater(
      client.streamChat({'n': 2}).toList(),
      throwsA(isA<TogetherException>()),
    );
    complete = true;
    expect(await client.streamChat({'n': 2}).toList(), hasLength(2));
  });
  test('option JSON rejects invalid values and snapshots nested lists', () {
    final input = <Object?>[
      {'v': 1},
    ];
    final option = TogetherChatOptions(
      chatTemplateKwargs: input,
      toolChoice: TogetherToolChoice.function('find'),
    );
    (input.first as Map)['v'] = 2;
    expect((option.toJson()['chat_template_kwargs'] as List).first['v'], 1);
    expect((option.toJson()['tool_choice'] as Map)['function']['name'], 'find');
    final choice = TogetherToolChoice.function('find');
    expect(
      () => ((choice.toJson() as Map)['function'] as Map)['name'] = 'changed',
      throwsUnsupportedError,
    );
    final enums = TogetherChatOptions(
      compliance: TogetherCompliance.hipaa,
      contextLengthExceededBehavior: TogetherContextLengthBehavior.error,
      reasoningEffort: TogetherReasoningEffort.high,
    ).toJson();
    expect(
      [
        enums['compliance'],
        enums['context_length_exceeded_behavior'],
        enums['reasoning_effort'],
      ],
      ['hipaa', 'error', 'high'],
    );
    expect(
      () => TogetherChatOptions(chatTemplateKwargs: Object()),
      throwsArgumentError,
    );
    final cycle = <Object?>[];
    cycle.add(cycle);
    expect(
      () => TogetherChatOptions(chatTemplateKwargs: cycle),
      throwsArgumentError,
    );
  });
  for (final choice in [TogetherToolChoice.none, TogetherToolChoice.auto]) {
    test('text-only requests accept tool choice ${choice.toJson()}', () async {
      handler = (request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['tool_choice'], choice.toJson());
        expect(body.containsKey('tools'), false);
        request.response.write(
          'data: {"choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n',
        );
        await request.response.close();
      };
      final result = await generateText(
        model: TogetherChatModel(
          client: client,
          model: 'x',
          options: TogetherChatOptions(toolChoice: choice),
        ),
        prompt: 'Hello',
      );
      expect(result.text, 'Hello');
    });
  }
  test(
    'required and named tool selection validate registered tools before dispatch',
    () async {
      handler = (_) async =>
          fail('must not dispatch an invalid tool selection');
      for (final choice in [
        TogetherToolChoice.required,
        TogetherToolChoice.function('unknown'),
      ]) {
        await expectLater(
          TogetherChatModel(
                client: client,
                model: 'x',
                options: TogetherChatOptions(toolChoice: choice),
              )
              .stream(
                ModelRequest(messages: [ChatMessage.user('Hello', id: 'u')]),
                cancellation: CancellationToken(),
              )
              .toList(),
          throwsArgumentError,
        );
      }
    },
  );
  test('invalid options and unsupported audio fail', () async {
    expect(() => TogetherChatOptions(logprobs: 21), throwsArgumentError);
    expect(
      () => TogetherClient(apiKey: 'x', headers: {'authorization': 'bad'}),
      throwsArgumentError,
    );
    final model = TogetherChatModel(client: client, model: 'x');
    await expectLater(
      model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'x',
                  role: MessageRole.user,
                  content: [const AudioPart(data: 'x', format: 'mp3')],
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsUnsupportedError,
    );
  });
}
