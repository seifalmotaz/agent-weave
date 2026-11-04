import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:agent_weave_vercel_gateway/agent_weave_vercel_gateway.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native requests preserve extensions and rotate isolated credentials',
    () async {
      final seen = <Map<String, Object?>>[];
      final headers = <String?>[];
      final transport = JsonHttpClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((r) async {
          seen.add(jsonDecode(r.body) as Map<String, Object?>);
          headers.add(r.headers['authorization']);
          expect(r.url.path, anyOf('/v1/chat/completions', '/v1/responses'));
          return http.Response(
            '{"id":"ok","unknown":42}',
            200,
            headers: {'x-fixture': 'yes'},
          );
        }),
      );
      var counter = 0;
      final client = GatewayClient.withTransport(
        transport: transport,
        credentialResolver: () {
          counter++;
          return GatewayCredentials(
            token: 'bearer-$counter',
            byok: {
              'bedrock': [
                {
                  'accessKeyId': 'access-$counter',
                  'secretAccessKey': 'secret-$counter',
                },
              ],
            },
          );
        },
      );
      final options = GatewayOptions(
        models: ['fallback'],
        order: ['one'],
        only: ['one'],
      );
      final results = await Future.wait([
        client.createChat({
          'model': 'm',
          'messages': [],
          'custom': 1,
          'providerOptions': {
            'anthropic': {'thinking': true},
          },
        }, options: options),
        client.createResponse({
          'model': 'm',
          'input': 'hello',
        }, options: options),
      ]);
      expect(headers, ['Bearer bearer-1', 'Bearer bearer-2']);
      expect(results.first.data['unknown'], 42);
      expect(results.first.headers['x-fixture'], 'yes');
      expect(seen.first['custom'], 1);
      expect((seen.first['providerOptions'] as Map)['anthropic'], {
        'thinking': true,
      });
      for (var i = 0; i < 2; i++) {
        final gateway = ((seen[i]['providerOptions'] as Map)['gateway'] as Map);
        expect(gateway['models'], ['fallback']);
        expect(gateway['order'], ['one']);
        expect(gateway['only'], ['one']);
        expect(
          gateway['byok']['bedrock'][0]['secretAccessKey'],
          'secret-${i + 1}',
        );
      }
      expect(jsonEncode(options.toJson()), isNot(contains('secret')));
      expect(
        GatewayCredentials(
          token: 's',
          byok: {
            'x': [
              {'apiKey': 's'},
            ],
          },
        ).toString(),
        equals('GatewayCredentials(redacted)'),
      );
      expect(
        () => client.createChat({
          'providerOptions': {
            'gateway': {'byok': 'secret'},
          },
        }),
        throwsArgumentError,
      );
    },
  );

  test(
    'models send public endpoint JSON and keep BYOK out of events',
    () async {
      final bodies = <Map<String, Object?>>[];
      final transport = JsonHttpClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((r) async {
          bodies.add(jsonDecode(r.body) as Map<String, Object?>);
          final response = r.url.path.endsWith('/responses');
          final event = response
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
        }),
      );
      final client = GatewayClient.withTransport(
        transport: transport,
        credentialResolver: () => GatewayCredentials(
          token: 'bearer',
          byok: {
            'openai': [
              {'apiKey': 'fixture-secret'},
            ],
          },
        ),
      );
      final request = ModelRequest(
        messages: [ChatMessage.user('hello', id: 'u')],
      );
      for (final model in [
        GatewayChatModel(client: client, model: 'm'),
        GatewayResponsesModel(client: client, model: 'm'),
      ]) {
        final events = await model
            .stream(request, cancellation: CancellationToken())
            .toList();
        expect(events.toString(), isNot(contains('fixture-secret')));
      }
      expect(bodies[0]['messages'], isA<List<Object?>>());
      expect(bodies[1]['input'], isA<List<Object?>>());
      expect(bodies[0]['stream'], true);
    },
  );

  test('HTTP and named SSE errors retain redacted private diagnostics', () async {
    const token = 'gateway-token-very-private';
    const secret = 'provider-"secret"-private';
    final echoed = jsonEncode({'token': token, 'provider': secret});
    final errorJson = {
      'error': {
        'code': 'invalid_model',
        'echo': echoed,
        'nested': [secret],
      },
    };
    for (final streaming in [false, true]) {
      final client = GatewayClient(
        baseUrl: 'https://example.test',
        credentialResolver: () => GatewayCredentials(
          token: token,
          byok: {
            'openai': [
              {'apiKey': secret},
            ],
          },
        ),
        httpClient: MockClient(
          (_) async => http.Response(
            streaming
                ? 'event: error\ndata: ${jsonEncode(errorJson)}\n\n'
                : jsonEncode(errorJson),
            streaming ? 200 : 400,
            headers: {
              'x-request-id': 'req-123',
              'x-diagnostic': 'Bearer $token $secret',
            },
          ),
        ),
      );
      try {
        if (streaming) {
          await client.streamChat({'model': 'm'}).toList();
        } else {
          await client.createChat({'model': 'm'});
        }
        fail('Expected an error');
      } on JsonHttpException catch (error) {
        expect(error.statusCode, streaming ? null : 400);
        expect(error.requestId, 'req-123');
        expect(jsonEncode(error.details), contains('invalid_model'));
        final serialized =
            '${error.toString()} ${jsonEncode(error.details)} ${jsonEncode(error.responseHeaders)}';
        expect(serialized, isNot(contains(token)));
        expect(serialized, isNot(contains(secret)));
        expect(
          serialized,
          isNot(
            contains(
              jsonEncode(secret).substring(1, jsonEncode(secret).length - 1),
            ),
          ),
        );
      }
      client.close();
    }
  });

  test(
    'subscription cancellation does not wait for response headers',
    () async {
      final started = Completer<void>();
      final headers = Completer<http.Response>();
      final client = GatewayClient.withApiKey(
        apiKey: 'key',
        baseUrl: 'https://example.test',
        httpClient: MockClient((_) {
          started.complete();
          return headers.future;
        }),
      );
      final subscription = client
          .streamChat({'model': 'm', 'messages': []})
          .listen((_) {});
      await started.future;
      await subscription.cancel().timeout(const Duration(seconds: 1));
      headers.complete(http.Response('', 200));
      client.close();
    },
  );

  test(
    'truncated and error SSE fail; cancellation interrupts credential wait',
    () async {
      for (final payload in [
        'data: {"error":{"message":"private"}}\n\n',
        'data: {"choices":[]}\n\n',
        'data: {broken}\n\n',
      ]) {
        final transport = JsonHttpClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient((_) async => http.Response(payload, 200)),
        );
        final client = GatewayClient.withTransport(
          transport: transport,
          credentialResolver: () => GatewayCredentials(token: 'token'),
        );
        await expectLater(
          client.streamChat({'model': 'm', 'messages': []}).toList(),
          throwsA(isA<JsonHttpException>()),
        );
      }
      final waiting = Completer<GatewayCredentials>();
      final client = GatewayClient.withTransport(
        transport: JsonHttpClient(
          baseUrl: 'https://example.test',
          httpClient: MockClient((_) async => throw StateError('unexpected')),
        ),
        credentialResolver: () => waiting.future,
      );
      final cancellation = CancellationToken();
      final result = client.createChat({
        'model': 'm',
      }, cancellation: cancellation);
      cancellation.cancel();
      await expectLater(result, throwsA(isA<RunCancelled>()));
    },
  );
  test(
    'typed options snapshot native extensions and reject reserved or credential keys',
    () {
      final extra = <String, Object?>{
        'futureFlag': <String, Object?>{'enabled': true},
      };
      final options = GatewayOptions(
        extra: extra,
        caching: GatewayCaching.auto,
        sort: GatewayProviderSort.cost,
        serviceTier: GatewayServiceTier.flex,
      );
      (extra['futureFlag'] as Map)['enabled'] = false;
      expect((options.toJson()['futureFlag'] as Map)['enabled'], true);
      expect(options.toJson()['caching'], 'auto');
      expect(options.toJson()['sort'], 'cost');
      expect(options.toJson()['serviceTier'], 'flex');
      for (final key in [
        'models',
        'byok',
        'experimental_streamingImageDecoding',
        'apiKey',
      ]) {
        expect(
          () => GatewayOptions(extra: {key: 'forbidden'}),
          throwsArgumentError,
        );
      }
      expect(() => options.extra['changed'] = true, throwsUnsupportedError);
    },
  );
  test(
    'nonstream methods reject streaming before credential resolution or dispatch',
    () async {
      final transport = JsonHttpClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((_) async => fail('must not dispatch')),
      );
      final client = GatewayClient.withTransport(
        transport: transport,
        credentialResolver: () => fail('must not resolve credentials'),
      );
      try {
        await expectLater(
          client.createChat({'stream': true}),
          throwsArgumentError,
        );
        await expectLater(
          client.createResponse({'stream': true}),
          throwsArgumentError,
        );
      } finally {
        client.close();
        transport.close();
      }
    },
  );
}
