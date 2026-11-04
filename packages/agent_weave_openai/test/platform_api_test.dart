import 'dart:convert';
import 'package:agent_weave/agent_weave.dart'
    show CancellationToken, RunCancelled;
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'raw JSON preserves non-object data and request-specific options',
    () async {
      final client = api.OpenAIClient(
        config: const api.OpenAIConfig(
          authProvider: api.ApiKeyProvider('fixture-key'),
        ),
        httpClient: MockClient((request) async {
          expect(request.method, 'PUT');
          expect(request.headers['OpenAI-Beta'], 'fixture=v1');
          expect(request.headers['Authorization'], 'Bearer fixture-key');
          expect(request.headers['Idempotency-Key'], 'operation-1');
          expect(request.url.queryParametersAll['include[]'], ['a', 'b']);
          expect(jsonDecode(request.body), [
            {'new_field': 42},
          ]);
          return http.Response(
            '[1,{"future_field":true}]',
            200,
            headers: {'x-request-id': 'req-fixture'},
          );
        }),
      );
      addTearDown(client.close);
      final raw = await api.OpenAIPlatformApi(client).requestJson(
        '/future-resource',
        method: api.OpenAIHttpMethod.put,
        body: [
          {'new_field': 42},
        ],
        headers: {'OpenAI-Beta': 'fixture=v1'},
        idempotencyKey: 'operation-1',
        repeatedQuery: {
          'include[]': ['a', 'b'],
        },
      );
      expect(raw, [
        1,
        {'future_field': true},
      ]);
    },
  );
  test('raw response access retains request IDs and binary content', () async {
    final client = api.OpenAIClient(
      httpClient: MockClient((request) async {
        expect(request.headers['Accept'], 'application/octet-stream');
        expect(request.url.queryParametersAll['include[]'], [
          'content',
          'metadata',
        ]);
        return http.Response.bytes(
          [0, 255, 128],
          200,
          headers: {'x-request-id': 'req-fixture'},
        );
      }),
    );
    addTearDown(client.close);
    final platform = api.OpenAIPlatformApi(client);
    final response = await platform.send(
      '/files/id/content',
      headers: {'Accept': 'application/octet-stream'},
      repeatedQuery: {
        'include[]': ['content', 'metadata'],
      },
    );
    expect(response.headers['x-request-id'], 'req-fixture');
    expect(response.bodyBytes, [0, 255, 128]);
    expect(
      await platform.download(
        '/files/id/content',
        headers: {'Accept': 'application/octet-stream'},
        repeatedQuery: {
          'include[]': ['content', 'metadata'],
        },
      ),
      [0, 255, 128],
    );
  });
  for (final header in [
    'Authorization',
    'aUtHoRiZaTiOn',
    'Proxy-Authorization',
    'Host',
    'Cookie',
    'Content-Length',
    'Transfer-Encoding',
  ]) {
    test('request headers cannot override $header', () async {
      final client = api.OpenAIClient(
        httpClient: MockClient((_) async => fail('Must not submit')),
      );
      addTearDown(client.close);
      await expectLater(
        api.OpenAIPlatformApi(
          client,
        ).send('/models', headers: {header: 'invalid'}),
        throwsArgumentError,
      );
    });
  }
  for (final payload in ['null', '[1,2]', 'true', '42', '"value"']) {
    test('generic JSON retains $payload', () async {
      final client = api.OpenAIClient(
        httpClient: MockClient((_) async => http.Response(payload, 200)),
      );
      addTearDown(client.close);
      expect(
        await api.OpenAIPlatformApi(client).requestJson('/fixture'),
        jsonDecode(payload),
      );
      if (payload != 'null') {
        await expectLater(
          api.OpenAIPlatformApi(client).request('/fixture'),
          throwsFormatException,
        );
      }
    });
  }
  test('pre-cancellation stops raw requests before transport', () async {
    final client = api.OpenAIClient(
      httpClient: MockClient((_) async => fail('Must not submit')),
    );
    addTearDown(client.close);
    await expectLater(
      api.OpenAIPlatformApi(
        client,
      ).send('/models', cancellation: CancellationToken()..cancel()),
      throwsA(isA<RunCancelled>()),
    );
  });

  test(
    'additional platform operations use the configured credentials and repeated queries',
    () async {
      final client = api.OpenAIClient(
        config: const api.OpenAIConfig(
          authProvider: api.ApiKeyProvider('fixture-key'),
        ),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/organization/projects');
          expect(request.url.queryParametersAll['include[]'], ['a', 'b']);
          expect(request.headers['authorization'], 'Bearer fixture-key');
          return http.Response('{"data":[],"has_more":false}', 200);
        }),
      );
      addTearDown(client.close);
      final result = await api.OpenAIPlatformApi(client).request(
        '/organization/projects',
        repeatedQuery: {
          'include[]': ['a', 'b'],
        },
      );
      expect(result['data'], isEmpty);
    },
  );
  for (final path in [
    'https://evil.example/api',
    '//evil.example/api',
    '/a/../b',
    '/a?key=value',
    '/a#fragment',
  ]) {
    test('rejects unsafe API path $path without dispatch', () async {
      final client = api.OpenAIClient(
        httpClient: MockClient((_) async => fail('Must not submit')),
      );
      addTearDown(client.close);
      await expectLater(
        api.OpenAIPlatformApi(client).request(path),
        throwsArgumentError,
      );
    });
  }
  test(
    'mutations are not automatically retried after provider failure',
    () async {
      var calls = 0;
      final client = api.OpenAIClient(
        httpClient: MockClient((_) async {
          calls++;
          return http.Response(
            '{"error":{"message":"Unavailable","type":"server_error"}}',
            503,
          );
        }),
      );
      addTearDown(client.close);
      await expectLater(
        api.OpenAIPlatformApi(client).request(
          '/organization/projects',
          method: api.OpenAIHttpMethod.post,
          body: {'name': 'Example'},
        ),
        throwsA(isA<Exception>()),
      );
      expect(calls, 1);
    },
  );
}
