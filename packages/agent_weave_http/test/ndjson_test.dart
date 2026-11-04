import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  JsonHttpRequest prepare() => JsonHttpRequest(body: {});
  late HttpServer server;
  late JsonHttpClient client;
  late Future<void> Function(HttpRequest) handler;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = JsonHttpClient(baseUrl: 'http://127.0.0.1:${server.port}');
    server.listen((request) => handler(request));
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test(
    'fragmented UTF8, CRLF, blanks, final line, query and immutable snapshots',
    () async {
      handler = (request) async {
        expect(request.uri.queryParametersAll['q'], ['one', 'two']);
        await request.drain<void>();
        request.response.headers.set('x-request-id', 'id');
        for (final byte in utf8.encode(
          '{"nested":{"value":"مرحبا"}}\r\n\r\n{"done":true}',
        )) {
          request.response.add([byte]);
          await request.response.flush();
        }
        await request.response.close();
      };
      final lines = await client
          .streamJsonLines(
            '/stream',
            prepare: prepare,
            query: {
              'q': ['one', 'two'],
            },
          )
          .toList();
      expect(lines.map((line) => line.data), [
        {
          'nested': {'value': 'مرحبا'},
        },
        {'done': true},
      ]);
      expect(lines.first.responseHeaders['x-request-id'], 'id');
      expect(
        () => lines.first.responseHeaders['x'] = 'x',
        throwsUnsupportedError,
      );
      expect(
        () =>
            (lines.first.data['nested'] as Map<String, Object?>)['value'] = 'x',
        throwsUnsupportedError,
      );
      final original = <String, Object?>{
        'nested': <Object?>[1],
      };
      final line = JsonLineData(original, responseHeaders: {'x': 'first'});
      (original['nested'] as List<Object?>).add(2);
      expect(line.data['nested'], [1]);
    },
  );

  test(
    'malformed, truncated and non-object lines fail without revealing content',
    () async {
      for (final body in [
        '{"secret":',
        '{"secret":oops}\n',
        '[1,2]\n',
        'null',
      ]) {
        handler = (request) async {
          await request.drain<void>();
          request.response.write(body);
          await request.response.close();
        };
        await expectLater(
          client.streamJsonLines('/stream', prepare: prepare).toList(),
          throwsA(
            isA<JsonHttpException>().having(
              (e) => e.toString().contains('secret'),
              'redacted',
              false,
            ),
          ),
        );
      }
    },
  );

  test(
    'cancel pending headers and unsubscribe stalled body while sibling survives',
    () async {
      final headersStarted = Completer<void>();
      final bodyStarted = Completer<void>();
      handler = (request) async {
        await request.drain<void>();
        if (request.uri.path == '/headers') {
          headersStarted.complete();
          return;
        }
        if (request.uri.path == '/body') {
          request.response.bufferOutput = false;
          request.response.write('{"first":true}\n{');
          await request.response.flush();
          bodyStarted.complete();
          return;
        }
        request.response.write('{"sibling":true}\n');
        await request.response.close();
      };
      final token = CancellationToken();
      final waiting = client
          .streamJsonLines('/headers', prepare: prepare, cancellation: token)
          .toList();
      await headersStarted.future.timeout(const Duration(seconds: 2));
      token.cancel();
      await expectLater(
        waiting.timeout(const Duration(seconds: 2)),
        throwsA(isA<RunCancelled>()),
      );
      final first = Completer<void>();
      final subscription = client
          .streamJsonLines('/body', prepare: prepare)
          .listen((_) => first.complete());
      await bodyStarted.future.timeout(const Duration(seconds: 2));
      await first.future.timeout(const Duration(seconds: 2));
      await subscription.cancel().timeout(const Duration(seconds: 1));
      expect(
        (await client.streamJsonLines('/sibling', prepare: prepare).toList())
            .single
            .data,
        {'sibling': true},
      );
    },
  );

  test('cancelling a stalled body does not abort an active sibling', () async {
    final bothStarted = Completer<void>();
    final releaseSibling = Completer<void>();
    var count = 0;
    handler = (request) async {
      await request.drain<void>();
      request.response.bufferOutput = false;
      request.response.write('{"first":true}\n');
      await request.response.flush();
      if (++count == 2) bothStarted.complete();
      if (request.uri.path == '/sibling') {
        await releaseSibling.future;
        request.response.write('{"done":true}\n');
        await request.response.close();
      }
    };
    final token = CancellationToken();
    final cancelled = client
        .streamJsonLines('/stalled', prepare: prepare, cancellation: token)
        .toList();
    final sibling = client
        .streamJsonLines('/sibling', prepare: prepare)
        .toList();
    await bothStarted.future.timeout(const Duration(seconds: 2));
    token.cancel();
    await expectLater(
      cancelled.timeout(const Duration(seconds: 2)),
      throwsA(isA<RunCancelled>()),
    );
    releaseSibling.complete();
    expect((await sibling).last.data, {'done': true});
  });

  test('timeout interrupts stalled native body', () async {
    handler = (request) async {
      await request.drain<void>();
      request.response.write('{"first":true}\n{');
      await request.response.flush();
    };
    final bounded = JsonHttpClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      requestTimeout: const Duration(milliseconds: 100),
    );
    addTearDown(bounded.close);
    await expectLater(
      bounded.streamJsonLines('/stream', prepare: prepare).toList(),
      throwsA(
        isA<JsonHttpException>().having(
          (e) => e.message,
          'message',
          'Request timed out',
        ),
      ),
    );
  });

  test('pause and resume propagate and borrowed client stays open', () async {
    var paused = false;
    var resumed = false;
    final chunks = StreamController<List<int>>(
      onPause: () => paused = true,
      onResume: () => resumed = true,
    );
    var calls = 0;
    final borrowed = MockClient.streaming((request, body) async {
      await body.drain<void>();
      return http.StreamedResponse(
        calls++ == 0 ? chunks.stream : Stream.value(utf8.encode('{}')),
        200,
      );
    });
    final transport = JsonHttpClient(
      baseUrl: 'http://example.test',
      httpClient: borrowed,
    );
    final first = Completer<void>();
    final sub = transport
        .streamJsonLines('/stream', prepare: prepare)
        .listen((_) => first.complete());
    chunks.add(utf8.encode('{}\n'));
    await first.future.timeout(const Duration(seconds: 2));
    sub.pause();
    await Future<void>.delayed(Duration.zero);
    expect(paused, true);
    sub.resume();
    await Future<void>.delayed(Duration.zero);
    expect(resumed, true);
    await sub.cancel();
    transport.close();
    expect(
      (await borrowed.post(Uri.parse('http://example.test'))).statusCode,
      200,
    );
    borrowed.close();
    await chunks.close();
  });
}
