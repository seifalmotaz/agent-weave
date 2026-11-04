import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_cloudflare/agent_weave_cloudflare.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'cancelling native chat while awaiting headers keeps parent active',
    () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final client = CloudflareClient.withApiToken(
        accountId: 'abc',
        apiToken: 'secret',
        httpClient: MockClient((_) {
          started.complete();
          return response.future;
        }),
      );
      final parent = CancellationToken();
      final subscription =
          CloudflareChatModel(client: client, model: '@cf/model')
              .stream(
                ModelRequest(messages: [ChatMessage.user('hello', id: 'u')]),
                cancellation: parent,
              )
              .listen(null);
      await started.future.timeout(const Duration(seconds: 1));
      await subscription.cancel().timeout(const Duration(seconds: 1));
      expect(parent.isCancelled, isFalse);
      response.complete(http.Response('{}', 200));
    },
  );

  test(
    'raw stream cancellation after headers releases only that call',
    () async {
      final body = StreamController<List<int>>();
      final received = Completer<void>();
      final client = CloudflareClient.withApiToken(
        accountId: 'abc',
        apiToken: 'fixture',
        httpClient: MockClient.streaming((request, data) async {
          await data.drain<void>();
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      final parent = CancellationToken();
      final subscription = client
          .stream('@cf/model', {}, cancellation: parent)
          .listen((_) {
            received.complete();
          });
      body.add(utf8.encode('data: {"response":"hello"}\n\n'));
      await received.future.timeout(const Duration(seconds: 1));
      await subscription.cancel().timeout(const Duration(seconds: 1));
      expect(parent.isCancelled, false);
      client.close();
      await body.close();
    },
  );
  test(
    'credential resolver exceptions are private for JSON and streams',
    () async {
      final client = CloudflareClient(
        accountId: 'abc',
        tokenResolver: () => throw StateError('resolver-private-token'),
      );
      for (final call in [
        () => client.runJson('@cf/model', {}),
        () => client.stream('@cf/model', {}).toList(),
      ]) {
        await expectLater(
          call(),
          throwsA(
            isA<CloudflareException>().having(
              (e) => e.toString(),
              'public message',
              isNot(contains('resolver-private-token')),
            ),
          ),
        );
      }
      client.close();
    },
  );
  test(
    'diagnostics redact escaped credentials and snapshot error data',
    () async {
      const secret = 'fixture"token';
      final transport = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'errors': [
              {'message': '$secret ${jsonEncode(secret)}'},
            ],
          }),
          200,
          headers: {'cf-ray': secret},
        ),
      );
      final client = CloudflareClient.withApiToken(
        accountId: 'abc',
        apiToken: secret,
        httpClient: transport,
      );
      try {
        await client.runJson('@cf/model', {});
        fail('expected failure');
      } on CloudflareException catch (error) {
        expect(jsonEncode(error.details), isNot(contains('fixture')));
        expect(error.responseHeaders.values.join(), isNot(contains('fixture')));
        expect(error.requestId, '[REDACTED]');
        expect(() => error.details!['new'] = true, throwsUnsupportedError);
      } finally {
        client.close();
        transport.close();
      }
    },
  );

  test(
    'client Gateway defaults reach native and compatible inference',
    () async {
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        return http.Response('{"success":true,"result":{}}', 200);
      });
      final client = CloudflareClient.withApiToken(
        accountId: 'abc',
        apiToken: 'fixture',
        httpClient: transport,
        gateway: CloudflareGatewayOptions(
          gatewayId: 'default-gateway',
          skipCache: true,
        ),
      );
      await client.runJson('@cf/model', {'prompt': 'hello'});
      await CloudflareGatewayClient(client: client).runJson('@cf/model', {});
      await CloudflareGatewayClient(client: client).runJson(
        '@cf/model',
        {},
        gateway: CloudflareGatewayOptions(cacheTtl: 60),
      );
      expect(requests.last.headers['cf-aig-cache-ttl'], '60');
      await CloudflareCompatibleClient(
        client: client,
      ).createChat({'model': '@cf/model'});
      await CloudflareCompatibleClient(
        client: client,
        gateway: CloudflareGatewayOptions(gatewayId: 'request-gateway'),
      ).createResponse({'model': '@cf/model'});
      expect(requests.map((request) => request.headers['cf-aig-gateway-id']), [
        'default-gateway',
        'default-gateway',
        'default-gateway',
        'default-gateway',
        'request-gateway',
      ]);
      expect(
        requests.every(
          (request) => request.headers['cf-aig-skip-cache'] == 'true',
        ),
        true,
      );
      expect(
        requests.every(
          (request) => request.headers['authorization'] == 'Bearer fixture',
        ),
        true,
      );
      client.close();
      transport.close();
    },
  );

  test('native, gateway, schema and binary preserve wire data', () async {
    final requests = <http.Request>[];
    final transport = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/schema')) {
        return http.Response('{"success":true,"result":{"input":{}}}', 200);
      }
      if (request.url.path.endsWith('/whisper')) {
        return http.Response('{"success":true,"result":{"text":"hello"}}', 200);
      }
      return http.Response(
        '{"success":true,"result":{"data":[[1]],"shape":[1,1],"pooling":"cls","unknown":true}}',
        200,
        headers: {'cf-aig-cache-status': 'HIT'},
      );
    });
    final client = CloudflareClient.withApiToken(
      accountId: 'abc',
      apiToken: 'secret',
      httpClient: transport,
    );
    final embedding = await CloudflareEmbeddingModel(client: client).embed(
      CloudflareEmbeddingRequest(
        text: ['a'],
        pooling: CloudflarePooling.cls,
        extra: {'future': 1},
      ),
    );
    expect(embedding.response.json!['result'], containsPair('shape', [1, 1]));
    expect(embedding.vectors, [
      [1.0],
    ]);
    expect(embedding.shape, [1, 1]);
    expect(embedding.pooling, 'cls');
    expect(embedding.result['unknown'], true);
    expect(
      requests.first.url.path,
      '/client/v4/accounts/abc/ai/run/@cf/baai/bge-base-en-v1.5',
    );
    expect(requests.first.headers['authorization'], 'Bearer secret');
    expect(jsonDecode(requests.first.body), {
      'text': ['a'],
      'pooling': 'cls',
      'future': 1,
    });
    final gateway = await CloudflareGatewayClient(client: client).runJson(
      '@cf/model',
      {'prompt': 'x'},
      gateway: CloudflareGatewayOptions(gatewayId: 'gw', skipCache: true),
    );
    expect(gateway.cacheStatus, 'HIT');
    expect(requests.last.url.path, '/client/v4/accounts/abc/ai/run');
    expect(jsonDecode(requests.last.body), {
      'model': '@cf/model',
      'input': {'prompt': 'x'},
    });
    expect(requests.last.headers['cf-aig-gateway-id'], 'gw');
    await client.getModelSchema('@cf/a b');
    expect(requests.last.method, 'GET');
    expect(requests.last.url.queryParameters['model'], '@cf/a b');
    final audio = await CloudflareTranscriptionModel(
      client: client,
    ).transcribe(CloudflareAudioInput.bytes([3, 4], contentType: 'audio/wav'));
    expect(audio.text, 'hello');
    expect(requests.last.bodyBytes, [3, 4]);
    expect(requests.last.headers['content-type'], 'audio/wav');
    client.close();
    transport.close();
  });
  test('envelope failure redacts current credential', () async {
    final transport = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'success': false,
          'errors': [
            {'message': 'secret'},
          ],
        }),
        200,
      ),
    );
    final client = CloudflareClient.withApiToken(
      accountId: 'abc',
      apiToken: 'secret',
      httpClient: transport,
    );
    try {
      await client.runJson('@cf/model', {});
      fail('expected error');
    } on CloudflareException catch (e) {
      expect(e.details.toString(), isNot(contains('secret')));
      expect(e.toString(), isNot(contains('secret')));
    }
    client.close();
    transport.close();
  });
  test(
    'native tool continuation follows documented assistant and tool messages',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final transport = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'success': true,
            'result': bodies.length == 1
                ? {
                    'tool_calls': [
                      {
                        'name': 'lookup',
                        'arguments': {'name': 'cf'},
                      },
                    ],
                  }
                : {'response': 'done'},
          }),
          200,
        );
      });
      final client = CloudflareClient.withApiToken(
        accountId: 'abc',
        apiToken: 'secret',
        httpClient: transport,
      );
      final model = CloudflareChatModel(
        client: client,
        model: '@hf/nousresearch/hermes-2-pro-mistral-7b',
      );
      final events = await model
          .stream(
            ModelRequest(
              messages: [ChatMessage.user('find', id: 'u')],
              tools: [
                const ModelTool(
                  name: 'lookup',
                  description: 'Find',
                  inputSchema: {'type': 'object'},
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      final call = events.whereType<ToolCallReady>().single.call;
      await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage.user('find', id: 'u'),
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  toolCalls: [call],
                ),
                ChatMessage(
                  id: 't',
                  role: MessageRole.tool,
                  toolCallId: call.id,
                  content: [const TextPart('{"ok":true}')],
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      final messages = bodies.last['messages'] as List;
      expect(jsonDecode(messages[1]['content'] as String), {
        'name': 'lookup',
        'arguments': {'name': 'cf'},
      });
      expect(messages[2], {'role': 'tool', 'content': '{"ok":true}'});
      client.close();
      transport.close();
    },
  );
  test('late credentials respect cancellation', () async {
    final pending = Completer<String>();
    var sent = false;
    final transport = MockClient((request) async {
      sent = true;
      return http.Response('{}', 200);
    });
    final token = CancellationToken();
    final client = CloudflareClient(
      accountId: 'abc',
      tokenResolver: () => pending.future,
      httpClient: transport,
    );
    final result = client.runJson('@cf/model', {}, cancellation: token);
    token.cancel();
    await expectLater(result, throwsA(isA<RunCancelled>()));
    pending.complete('secret');
    await Future<void>.delayed(Duration.zero);
    expect(sent, false);
    client.close();
    transport.close();
  });
  test(
    'rotating tokens remain request scoped and image JSON is retained',
    () async {
      var next = 0;
      final transport = MockClient((request) async {
        final token = request.headers['authorization']!;
        await Future<void>.delayed(Duration.zero);
        return http.Response(
          jsonEncode({
            'success': false,
            'errors': [
              {'message': token},
            ],
          }),
          200,
        );
      });
      final client = CloudflareClient(
        accountId: 'abc',
        tokenResolver: () => 'token-${++next}',
        httpClient: transport,
      );
      final errors = await Future.wait(
        List.generate(2, (_) async {
          try {
            await CloudflareImageModel(
              client: client,
            ).generate({'prompt': 'cat'});
            fail('expected failure');
          } on CloudflareException catch (error) {
            return error;
          }
        }),
      );
      for (final error in errors) {
        expect(error.details.toString(), isNot(contains('token-')));
      }
      client.close();
      transport.close();
    },
  );
  test(
    'compatible codecs use distinct paths and preserve runtime fields',
    () async {
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        final event = request.url.path.endsWith('/responses')
            ? {
                'type': 'response.completed',
                'sequence_number': 0,
                'response': {
                  'id': 'r',
                  'object': 'response',
                  'created_at': 0,
                  'status': 'completed',
                  'model': 'm',
                  'output': <Object?>[],
                },
              }
            : {
                'id': 'c',
                'object': 'chat.completion.chunk',
                'created': 0,
                'model': 'm',
                'choices': [
                  {
                    'index': 0,
                    'delta': <String, Object?>{},
                    'finish_reason': 'stop',
                  },
                ],
              };
        return http.Response(
          'data: ${jsonEncode(event)}\n\ndata: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final native = CloudflareClient.withApiToken(
        accountId: 'abc',
        apiToken: 'secret',
        httpClient: transport,
      );
      final client = CloudflareCompatibleClient(
        client: native,
        gateway: CloudflareGatewayOptions(gatewayId: 'gw'),
      );
      final request = ModelRequest(
        messages: [ChatMessage.user('hello', id: 'u')],
        maxOutputTokens: 123,
      );
      await CloudflareCompatibleChatModel(
        client: client,
        model: 'm',
        tokenField: CloudflareChatTokenField.maxTokens,
        options: {'temperature': 0.5},
      ).stream(request, cancellation: CancellationToken()).toList();
      expect(
        requests.last.url.path,
        '/client/v4/accounts/abc/ai/v1/chat/completions',
      );
      final chat = jsonDecode(requests.last.body) as Map;
      expect(chat['max_tokens'], 123);
      expect(chat.containsKey('max_completion_tokens'), false);
      expect(chat['temperature'], 0.5);
      expect(requests.last.headers['cf-aig-gateway-id'], 'gw');
      await CloudflareCompatibleResponsesModel(
        client: client,
        model: 'm',
      ).stream(request, cancellation: CancellationToken()).toList();
      expect(requests.last.url.path, '/client/v4/accounts/abc/ai/v1/responses');
      expect(
        () => CloudflareCompatibleChatModel(
          client: client,
          model: 'm',
          options: {'messages': []},
        ),
        throwsArgumentError,
      );
      native.close();
      transport.close();
    },
  );
  test(
    'native streaming, JSON audio and image bytes retain wire values',
    () async {
      final requests = <http.Request>[];
      final transport = MockClient((request) async {
        requests.add(request);
        if ((jsonDecode(request.body) as Map)['stream'] == true) {
          return http.Response(
            'data: {"response":"hi"}\n\ndata: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (request.url.path.endsWith('/whisper')) {
          return http.Response(
            '{"success":true,"result":{"text":"hello","word_count":1,"vtt":"WEBVTT"}}',
            200,
          );
        }
        return http.Response.bytes(
          [137, 80, 78, 71],
          200,
          headers: {'content-type': 'image/png'},
        );
      });
      final client = CloudflareClient.withApiToken(
        accountId: 'abc',
        apiToken: 'secret',
        httpClient: transport,
      );
      final events = await client.stream('@cf/a/b', {'prompt': 'hi'}).toList();
      expect(events.length, 2);
      expect(jsonDecode(requests.last.body), {'prompt': 'hi', 'stream': true});
      final transcript = await CloudflareTranscriptionModel(client: client)
          .transcribe(
            CloudflareAudioInput.json({
              'audio': [1, 2],
            }),
          );
      expect(transcript.vtt, 'WEBVTT');
      expect(jsonDecode(requests.last.body), {
        'audio': [1, 2],
      });
      final image = await CloudflareImageModel(
        client: client,
      ).generate({'prompt': 'cat', 'steps': 4});
      expect(image.imageBytes, [137, 80, 78, 71]);
      expect(image.response.json, isNull);
      expect(image.contentType, 'image/png');
      client.close();
      transport.close();
    },
  );
  test(
    'request data is snapshotted before async credentials resolve',
    () async {
      final credential = Completer<String>();
      Map<String, dynamic>? sent;
      final transport = MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"success":true,"result":{}}', 200);
      });
      final client = CloudflareClient(
        accountId: 'abc',
        tokenResolver: () => credential.future,
        httpClient: transport,
      );
      final input = <String, Object?>{
        'nested': {'value': 1},
      };
      final future = client.runJson('@cf/test', input);
      (input['nested'] as Map)['value'] = 2;
      credential.complete('secret');
      await future;
      expect(sent, {
        'nested': {'value': 1},
      });
      client.close();
      transport.close();
    },
  );
  test(
    'approval pauses and resumes with the exact native selected call',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final transport = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        final result = bodies.length == 1
            ? {
                'tool_calls': [
                  {
                    'name': 'lookup',
                    'arguments': {'name': 'cf'},
                    'extra': 'kept',
                  },
                ],
              }
            : {'response': 'done'};
        return http.Response(
          jsonEncode({'success': true, 'result': result}),
          200,
        );
      });
      final client = CloudflareClient.withApiToken(
        accountId: 'abc',
        apiToken: 'secret',
        httpClient: transport,
      );
      var calls = 0;
      final agent = AiAgent<void>(
        model: CloudflareChatModel(
          client: client,
          model: '@hf/nousresearch/hermes-2-pro-mistral-7b',
        ),
        tools: [
          Tool<String, String, void>(
            name: 'lookup',
            description: 'Look up',
            inputSchema: const {
              'type': 'object',
              'properties': {
                'name': {'type': 'string'},
              },
              'required': ['name'],
            },
            needsApproval: true,
            decode: (input) => input['name'] as String,
            encode: (value) => value,
            execute: (value, context) {
              calls++;
              return 'found $value';
            },
          ),
        ],
      );
      final paused = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('find', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      );
      expect(paused.status, RunStatus.interrupted);
      expect(calls, 0);
      final done = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'next',
          parentRunId: paused.runId,
          resume: [paused.interrupts.single.approve()],
        ),
        ownerId: 'o',
        context: null,
      );
      expect(done.text, 'done');
      expect(calls, 1);
      final messages = bodies.last['messages'] as List;
      expect(jsonDecode(messages[1]['content'] as String), {
        'name': 'lookup',
        'arguments': {'name': 'cf'},
        'extra': 'kept',
      });
      expect(messages[2]['role'], 'tool');
      client.close();
      transport.close();
    },
  );
  test('native request guards and immutable diagnostics', () {
    final client = CloudflareClient.withApiToken(
      accountId: 'abc',
      apiToken: 'secret',
    );
    for (final key in [
      'prompt',
      'raw',
      'chat_template',
      'template',
      'max_completion_tokens',
    ]) {
      expect(
        () => CloudflareChatModel(
          client: client,
          model: 'm',
          options: {key: 'x'},
        ),
        throwsArgumentError,
      );
    }
    expect(() => CloudflareEmbeddingRequest(text: ['  ']), throwsArgumentError);
    final original = <String, Object?>{
      'nested': <Object?>[1],
    };
    final error = CloudflareException('failed', details: original);
    (original['nested'] as List).add(2);
    expect(error.details!['nested'], [1]);
    expect(
      () => (error.details!['nested'] as List).add(3),
      throwsUnsupportedError,
    );
    client.close();
  });
  test(
    'Flux image decoding, unknown JSON and malformed embedding shape',
    () async {
      var mode = 'flux';
      final transport = MockClient((request) async {
        final result = switch (mode) {
          'flux' => {
            'image': base64Encode([1, 2, 3]),
            'unknown': true,
          },
          'embedding' => {
            'data': [
              [1, 2],
            ],
            'shape': [1, 3],
          },
          _ => {'future_image': 'abc'},
        };
        return http.Response(
          jsonEncode({'success': true, 'result': result}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = CloudflareClient.withApiToken(
        accountId: 'abc',
        apiToken: 'secret',
        httpClient: transport,
      );
      final image = await CloudflareImageModel(
        client: client,
      ).generate({'prompt': 'x'});
      expect(image.imageBytes, [1, 2, 3]);
      expect(image.contentType, 'image/jpeg');
      expect((image.response.json!['result'] as Map)['unknown'], true);
      expect(() => image.imageBytes[0] = 3, throwsUnsupportedError);
      expect(() => image.response.bytes[0] = 3, throwsUnsupportedError);
      mode = 'unknown';
      await expectLater(
        CloudflareImageModel(client: client).generate({'prompt': 'x'}),
        throwsUnsupportedError,
      );
      mode = 'embedding';
      await expectLater(
        CloudflareEmbeddingModel(
          client: client,
        ).embed(CloudflareEmbeddingRequest(text: ['a'])),
        throwsA(isA<CloudflareException>()),
      );
      client.close();
      transport.close();
    },
  );
}
