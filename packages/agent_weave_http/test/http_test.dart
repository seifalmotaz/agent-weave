import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late HttpServer server;
  late JsonHttpClient client;
  late Future<void> Function(HttpRequest) handler;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = JsonHttpClient(baseUrl: 'http://127.0.0.1:${server.port}/v1');
    server.listen((request) => handler(request));
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });
  JsonHttpRequest prepare() => JsonHttpRequest(
    body: {'prompt': 'hello'},
    headers: {'Authorization': 'Bearer fixture'},
  );

  test(
    'GET and HEAD preserve query, status and headers with no body',
    () async {
      for (final method in [HttpMethod.get, HttpMethod.head]) {
        handler = (request) async {
          expect(request.method, method.name.toUpperCase());
          expect(request.uri.path, '/v1/models/schema');
          expect(request.uri.queryParametersAll['model'], ['@cf/a/b', 'a b']);
          expect(await request.toList(), isEmpty);
          expect(request.headers.value('authorization'), 'Bearer fixture');
          request.response.statusCode = 202;
          request.response.headers.set('x-request-id', 'schema-request');
          if (method == HttpMethod.get) request.response.write('{"result":{}}');
          await request.response.close();
        };
        final response = await client.send(
          '/models/schema',
          method: method,
          prepare: () =>
              EmptyHttpRequest(headers: {'Authorization': 'Bearer fixture'}),
          query: {
            'model': ['@cf/a/b', 'a b'],
          },
        );
        expect(response.statusCode, 202);
        expect(response.headers['x-request-id'], 'schema-request');
        expect(response.body, method == HttpMethod.get ? '{"result":{}}' : '');
      }
    },
  );
  test(
    'binary PATCH sends immutable exact bytes and retains binary output',
    () async {
      final original = [0, 128, 255];
      final payload = BinaryHttpRequest(
        bytes: original,
        contentType: 'audio/wav',
      );
      original[0] = 10;
      expect(() => payload.bytes[0] = 10, throwsUnsupportedError);
      handler = (request) async {
        expect(request.method, 'PATCH');
        expect(request.headers.contentType.toString(), 'audio/wav');
        expect(
          await request.fold<List<int>>(
            [],
            (bytes, chunk) => bytes..addAll(chunk),
          ),
          [0, 128, 255],
        );
        request.response.headers.contentType = ContentType.binary;
        request.response.add([255, 0, 128]);
        await request.response.close();
      };
      final response = await client.send(
        '/audio',
        method: HttpMethod.patch,
        prepare: () => payload,
      );
      expect(response.bodyBytes, [255, 0, 128]);
    },
  );
  test(
    'invalid byte, MIME and GET/HEAD body variants never dispatch',
    () async {
      handler = (_) async => fail('must not send');
      for (final bytes in [
        [-1],
        [256],
      ]) {
        expect(() => BinaryHttpRequest(bytes: bytes), throwsArgumentError);
      }
      for (final mime in ['', 'audio/wav\r\nHost: other', 'audio/\x00wav']) {
        expect(
          () => BinaryHttpRequest(bytes: [], contentType: mime),
          throwsArgumentError,
        );
      }
      for (final method in [HttpMethod.get, HttpMethod.head]) {
        for (final body in [
          JsonHttpRequest(body: {}),
          BinaryHttpRequest(bytes: []),
        ]) {
          await expectLater(
            client.send('/models', method: method, prepare: () => body),
            throwsArgumentError,
          );
        }
      }
    },
  );

  test(
    'SSE retains event names, IDs, repeated query and headers across fragmented UTF8',
    () async {
      handler = (request) async {
        expect(request.uri.queryParametersAll['include'], ['one', 'two']);
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'prompt': 'hello',
        });
        request.response.headers.set('x-request-id', 'r1');
        final bytes = utf8.encode(
          '\uFEFF: heartbeat\r\nid: first\r\nevent: text\r\ndata: {"message":\r\ndata: "مرحبا"}\r\n\r\ndata: {"message":"again"}\r\n\r\ndata: [DONE]\r\n\r\n',
        );
        for (final byte in bytes) {
          request.response.add([byte]);
          await request.response.flush();
        }
        await request.response.close();
      };
      final events = await client
          .streamJson(
            '/chat',
            prepare: prepare,
            query: {
              'include': ['one', 'two'],
            },
          )
          .toList();
      expect(events, hasLength(3));
      final first = events.first as JsonSseData;
      expect(first.data, {'message': 'مرحبا'});
      expect(first.event, 'text');
      expect(first.id, 'first');
      expect(first.responseHeaders['x-request-id'], 'r1');
      final second = events[1] as JsonSseData;
      expect(second.event, isNull);
      expect(second.id, 'first');
      expect(events.last, isA<JsonSseDone>());
    },
  );
  test(
    'credential resolution cancellation never sends a late request',
    () async {
      var calls = 0;
      handler = (request) async {
        calls++;
        await request.response.close();
      };
      final credentials = Completer<JsonHttpRequest>();
      final entered = Completer<void>();
      final token = CancellationToken();
      final result = client.sendJson(
        '/chat',
        cancellation: token,
        prepare: () {
          entered.complete();
          return credentials.future;
        },
      );
      await entered.future;
      token.cancel();
      await expectLater(result, throwsA(isA<RunCancelled>()));
      credentials.complete(prepare());
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
    },
  );
  test(
    'request timeout includes credential resolution and does not send after it completes',
    () async {
      var calls = 0;
      handler = (request) async {
        calls++;
        await request.response.close();
      };
      final waiting = Completer<JsonHttpRequest>();
      final short = JsonHttpClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        requestTimeout: const Duration(milliseconds: 40),
      );
      try {
        await expectLater(
          short.sendJson('/chat', prepare: () => waiting.future),
          throwsA(
            isA<JsonHttpException>().having(
              (e) => e.message,
              'message',
              'Request timed out',
            ),
          ),
        );
        waiting.complete(prepare());
        await Future<void>.delayed(Duration.zero);
        expect(calls, 0);
      } finally {
        short.close();
      }
    },
  );
  test(
    'stream cancellation aborts pending headers and leaves client usable',
    () async {
      final started = Completer<void>();
      handler = (request) async {
        await request.drain<void>();
        started.complete();
      };
      final sub = client.streamJson('/chat', prepare: prepare).listen((_) {});
      await started.future;
      await sub.cancel().timeout(const Duration(seconds: 1));
      handler = (request) async {
        await request.drain<void>();
        request.response.write('{}');
        await request.response.close();
      };
      expect((await client.sendJson('/chat', prepare: prepare)).body, '{}');
    },
  );
  test('malformed and incomplete SSE fail without echoing payloads', () async {
    for (final body in [
      'data: {"secret":oops}\n\n',
      'data: {"secret":"unfinished"}',
    ]) {
      handler = (request) async {
        await request.drain<void>();
        request.response.write(body);
        await request.response.close();
      };
      await expectLater(
        client.streamJson('/chat', prepare: prepare).toList(),
        throwsA(
          isA<JsonHttpException>().having(
            (e) => e.toString().contains('secret'),
            'redacted',
            false,
          ),
        ),
      );
    }
  });
  test(
    'path, transport headers and cyclic JSON fail before dispatch',
    () async {
      handler = (_) async => fail('must not send');
      final cycle = <String, Object?>{};
      cycle['self'] = cycle;
      expect(() => JsonHttpRequest(body: cycle), throwsArgumentError);
      expect(
        () => JsonHttpRequest(body: {}, headers: {'Host': 'other'}),
        throwsArgumentError,
      );
      for (final path in [
        'https://example.com',
        '//example.com',
        '/%2e%2e/chat',
        '/chat?key=private',
      ]) {
        await expectLater(
          client.sendJson(path, prepare: prepare),
          throwsArgumentError,
        );
      }
    },
  );
  test('timeout interrupts a custom HTTP body that ignores abort', () async {
    final stalled = StreamController<List<int>>();
    final custom = MockClient.streaming((request, body) async {
      await body.drain<void>();
      return http.StreamedResponse(stalled.stream, 200);
    });
    final bounded = JsonHttpClient(
      baseUrl: 'https://example.test',
      httpClient: custom,
      requestTimeout: const Duration(milliseconds: 40),
    );
    try {
      await expectLater(
        bounded.streamJson('/chat', prepare: prepare).toList(),
        throwsA(
          isA<JsonHttpException>().having(
            (e) => e.message,
            'message',
            'Request timed out',
          ),
        ),
      );
    } finally {
      bounded.close();
      custom.close();
      await stalled.close();
    }
  });
  test(
    'close cancels own resolver wait and retains borrowed client ownership',
    () async {
      final borrowed = _TrackedClient();
      final transport = JsonHttpClient(
        baseUrl: 'https://example.test',
        httpClient: borrowed,
      );
      final entered = Completer<void>();
      final waiting = Completer<JsonHttpRequest>();
      final response = transport.sendJson(
        '/chat',
        prepare: () {
          entered.complete();
          return waiting.future;
        },
      );
      await entered.future;
      transport.close();
      await expectLater(response, throwsA(isA<RunCancelled>()));
      expect(borrowed.closed, false);
      expect(
        (await borrowed.get(Uri.parse('https://example.test'))).statusCode,
        200,
      );
      waiting.complete(prepare());
      borrowed.close();
    },
  );
  test(
    'streaming through a closed client reports an ordinary stream error',
    () async {
      client.close();
      await expectLater(
        client.streamJson('/chat', prepare: prepare).toList(),
        throwsStateError,
      );
    },
  );
}

final class _TrackedClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  }

  @override
  void close() {
    closed = true;
  }
}
