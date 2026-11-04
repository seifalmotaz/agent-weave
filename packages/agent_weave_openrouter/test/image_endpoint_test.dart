import 'dart:async';
import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('buffered fallback HTTP 200 error preserves safe diagnostics', () async {
    final client = OpenRouterClient.withApiKey(
      apiKey: 'private-key',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"error":{"code":429,"message":"private-key"}}',
          200,
          headers: {
            'content-type': 'application/json',
            'x-request-id': 'req-1',
          },
        ),
      ),
    );
    addTearDown(client.close);
    await expectLater(
      OpenRouterImageModel(
        client: client,
      ).stream(OpenRouterImageRequest(model: 'm', prompt: 'p')).toList(),
      throwsA(
        isA<JsonHttpException>()
            .having((e) => e.statusCode, 'status', 200)
            .having((e) => e.requestId, 'request id', 'req-1')
            .having(
              (e) => e.details.toString(),
              'details',
              isNot(contains('private-key')),
            ),
      ),
    );
  });
  test('cancel during credential resolution prevents image dispatch', () async {
    final pending = Completer<String>();
    final entered = Completer<void>();
    var requests = 0;
    final client = OpenRouterClient(
      credentialResolver: () {
        entered.complete();
        return pending.future;
      },
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    final token = CancellationToken();
    final future = OpenRouterImageModel(client: client)
        .stream(
          OpenRouterImageRequest(model: 'm', prompt: 'p'),
          cancellation: token,
        )
        .toList();
    await entered.future;
    token.cancel();
    await expectLater(future, throwsA(isA<RunCancelled>()));
    pending.complete('key');
    expect(requests, 0);
  });
  test('multiple images can interleave completions and partials', () async {
    final client = OpenRouterClient.withApiKey(
      apiKey: 'key',
      httpClient: MockClient(
        (_) async => http.Response(
          'data: {"type":"image_generation.completed","created":1,"b64_json":"eA=="}\n\n'
          'data: {"type":"image_generation.partial_image","partial_image_index":0,"b64_json":"eA=="}\n\n'
          'data: {"type":"image_generation.completed","created":1,"b64_json":"eA=="}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      ),
    );
    addTearDown(client.close);
    final events = await OpenRouterImageModel(
      client: client,
    ).stream(OpenRouterImageRequest(model: 'm', prompt: 'p', n: 2)).toList();
    expect(events.map((e) => e.runtimeType), [
      OpenRouterImageCompleted,
      OpenRouterImagePartial,
      OpenRouterImageCompleted,
    ]);
  });
  test(
    'stream error event retains provider code and redacts credential',
    () async {
      final client = OpenRouterClient.withApiKey(
        apiKey: 'private-key',
        httpClient: MockClient(
          (_) async => http.Response(
            'data: {"data":{"type":"error","error":{"code":"bad","message":"private-key"}}}\n\ndata: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          ),
        ),
      );
      addTearDown(client.close);
      final events = await OpenRouterImageModel(
        client: client,
      ).stream(OpenRouterImageRequest(model: 'm', prompt: 'p')).toList();
      expect((events.single as OpenRouterImageError).error, {
        'code': 'bad',
        'message': '[REDACTED]',
      });
    },
  );
  test('streamed images retain ordered partial, text and completed events', () async {
    final seen = <Map<String, dynamic>>[];
    final client = OpenRouterClient.withApiKey(
      apiKey: 'key',
      httpClient: MockClient((request) async {
        seen.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          [
            'data: {"type":"image_generation.partial_image","partial_image_index":0,"b64_json":"eA=="}\n\n',
            'data: {"data":{"type":"image_generation.text_chunk","text":"<svg>","phase":"draft"}}\n\n',
            'data: {"data":{"type":"image_generation.text_chunk","text":"<svg/>","phase":"content"}}\n\n',
            'data: {"data":{"type":"image_generation.completed","created":2,"b64_json":"eA==","media_type":"image/svg+xml"}}\n\n',
            'data: [DONE]\n\n',
          ].join(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }),
    );
    addTearDown(client.close);
    final events = await OpenRouterImageModel(
      client: client,
    ).stream(OpenRouterImageRequest(model: 'm', prompt: 'p')).toList();
    expect(seen.single['stream'], true);
    expect(events.map((e) => e.runtimeType), [
      OpenRouterImagePartial,
      OpenRouterImageText,
      OpenRouterImageText,
      OpenRouterImageCompleted,
    ]);
    expect((events[1] as OpenRouterImageText).phase, 'draft');
    expect(
      (events.last as OpenRouterImageCompleted).image.mediaType,
      'image/svg+xml',
    );
  });
  test('streaming JSON fallback uses one request', () async {
    var requests = 0;
    final client = OpenRouterClient.withApiKey(
      apiKey: 'key',
      httpClient: MockClient((request) async {
        requests++;
        return http.Response(
          '{"created":1,"data":[{"b64_json":"eA=="}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.close);
    final events = await OpenRouterImageModel(
      client: client,
    ).stream(OpenRouterImageRequest(model: 'm', prompt: 'p')).toList();
    expect(requests, 1);
    expect(
      (events.single as OpenRouterImageBuffered).response.data.single.bytes,
      [120],
    );
  });
  test(
    'missing terminal sentinel and events after an error are rejected',
    () async {
      for (final body in [
        'data: {"data":{"type":"image_generation.completed","created":2,"b64_json":"eA=="}}\n\n',
        'data: {"type":"error","error":{"message":"failed"}}\n\ndata: {"data":{"type":"image_generation.partial_image","partial_image_index":0,"b64_json":"eA=="}}\n\ndata: [DONE]\n\n',
      ]) {
        final client = OpenRouterClient.withApiKey(
          apiKey: 'key',
          httpClient: MockClient(
            (_) async => http.Response(
              body,
              200,
              headers: {'content-type': 'text/event-stream'},
            ),
          ),
        );
        await expectLater(
          OpenRouterImageModel(
            client: client,
          ).stream(OpenRouterImageRequest(model: 'm', prompt: 'p')).toList(),
          throwsA(anything),
        );
        client.close();
      }
    },
  );
  test(
    'typed generation sends options and returns bytes without invented MIME',
    () async {
      final client = OpenRouterClient.withApiKey(
        apiKey: 'key',
        httpClient: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['seed'], 42);
          expect(body['provider'], {
            'only': ['provider'],
          });
          expect(body['input_references'], [
            {
              'type': 'image_url',
              'image_url': {'url': 'https://example.test/image.png'},
            },
          ]);
          return http.Response(
            '{"created":1,"data":[{"b64_json":"eA=="}]}',
            200,
          );
        }),
      );
      addTearDown(client.close);
      final model = OpenRouterImageModel(client: client);
      final response = await model.generate(
        OpenRouterImageRequest(
          model: 'author/model',
          prompt: 'hello',
          seed: 42,
          provider: OpenRouterImageProviderPreferences(only: ['provider']),
          inputReferences: [
            {
              'type': 'image_url',
              'image_url': {'url': 'https://example.test/image.png'},
            },
          ],
        ),
      );
      expect(response.data.single.bytes, [120]);
      expect(response.data.single.mediaType, isNull);
    },
  );
  test('dedicated images sends native body and preserves response', () async {
    final requests = <http.Request>[];
    final client = OpenRouterClient.withApiKey(
      apiKey: 'key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'created': 1,
            'data': [
              {'b64_json': 'eA=='},
            ],
            'future': true,
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);
    final result = await client.createImages({
      'model': 'image',
      'prompt': 'hello',
      'seed': 7,
      'future': {'x': 1},
    });
    expect(requests.single.url.path, '/api/v1/images');
    expect(requests.single.headers['authorization'], 'Bearer key');
    expect(jsonDecode(requests.single.body), {
      'model': 'image',
      'prompt': 'hello',
      'seed': 7,
      'future': {'x': 1},
    });
    expect(result.data['future'], true);
  });
  test(
    'discovery uses fixed origin and rejects unsafe path segments',
    () async {
      final urls = <Uri>[];
      final client = OpenRouterClient.withApiKey(
        apiKey: 'key',
        httpClient: MockClient((request) async {
          urls.add(request.url);
          expect(request.method, 'GET');
          return http.Response('{"data":[]}', 200);
        }),
      );
      addTearDown(client.close);
      await client.listImageModels();
      await client.listImageModelEndpoints('author', 'model name');
      expect(urls.map((u) => u.path), [
        '/api/v1/images/models',
        '/api/v1/images/models/author/model%20name/endpoints',
      ]);
      expect(
        () => client.listImageModelEndpoints('..', 'model'),
        throwsArgumentError,
      );
      expect(
        () => client.listImageModelEndpoints('https://attacker', 'model'),
        throwsArgumentError,
      );
      expect(urls.length, 2);
    },
  );
}
