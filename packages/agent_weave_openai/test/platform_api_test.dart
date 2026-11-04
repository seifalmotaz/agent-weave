import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
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
