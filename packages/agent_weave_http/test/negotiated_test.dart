import 'dart:async';
import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  JsonHttpRequest prepare() => JsonHttpRequest(body: {'stream': true});
  for (final contentType in [
    'application/json; charset=utf-8',
    'application/vendor+json',
  ]) {
    test(
      'one POST buffers $contentType with immutable data and headers',
      () async {
        var calls = 0;
        final mock = MockClient((request) async {
          calls++;
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {'stream': true});
          return http.Response(
            '{"data":[{"value":42}]}',
            202,
            headers: {
              'Content-Type': contentType,
              'x-request-id': 'server-request',
            },
          );
        });
        final client = JsonHttpClient(
          baseUrl: 'https://example.invalid',
          httpClient: mock,
        );
        addTearDown(client.close);
        addTearDown(mock.close);
        final events = await client
            .streamJsonOrSse('/images', prepare: prepare)
            .toList();
        expect(calls, 1);
        final value = events.single as JsonBufferedData;
        expect(value.statusCode, 202);
        expect(value.responseHeaders['x-request-id'], 'server-request');
        expect(value.data, {
          'data': [
            {'value': 42},
          ],
        });
        expect(
          () => (value.data['data'] as List).clear(),
          throwsUnsupportedError,
        );
        expect(() => value.responseHeaders.clear(), throwsUnsupportedError);
      },
    );
  }
  test(
    'SSE shares framing and stops at the sentinel without another request',
    () async {
      var calls = 0;
      final wire = utf8.encode(
        ': heartbeat\n\nid: 7\nevent: update\ndata: {"text":"مرحبا"}\n\ndata: [DONE]\n\ndata: not-json-after-terminal\n\n',
      );
      final mock = MockClient.streaming((_, _) async {
        calls++;
        return http.StreamedResponse(
          Stream.fromIterable([
            for (var i = 0; i < wire.length; i += 3)
              wire.sublist(i, i + 3 > wire.length ? wire.length : i + 3),
          ]),
          200,
          headers: {'content-type': 'Text/Event-Stream; charset=utf-8'},
        );
      });
      final client = JsonHttpClient(
        baseUrl: 'https://example.invalid',
        httpClient: mock,
      );
      addTearDown(client.close);
      addTearDown(mock.close);
      final events = await client
          .streamJsonOrSse('/images', prepare: prepare)
          .toList();
      expect(calls, 1);
      expect(events, hasLength(2));
      final data = events.first as JsonSseData;
      expect(data.data, {'text': 'مرحبا'});
      expect(data.event, 'update');
      expect(data.id, '7');
      expect(events.last, isA<JsonSseDone>());
    },
  );
  test(
    'invalid JSON and unsupported media preserve diagnostics without content',
    () async {
      for (final fixture in [
        (type: 'application/json', bytes: utf8.encode('private-invalid')),
        (type: 'application/json', bytes: utf8.encode('[]')),
        (type: 'application/json', bytes: [255]),
        (
          type: 'text/event-stream',
          bytes: [...utf8.encode('data: private-invalid'), 255, 10, 10],
        ),
        (type: 'text/plain', bytes: utf8.encode('private-invalid')),
      ]) {
        final mock = MockClient(
          (_) async => http.Response.bytes(
            fixture.bytes,
            200,
            headers: {
              'content-type': fixture.type,
              'request-id': 'server-request',
            },
          ),
        );
        final client = JsonHttpClient(
          baseUrl: 'https://example.invalid',
          httpClient: mock,
        );
        addTearDown(client.close);
        addTearDown(mock.close);
        await expectLater(
          client.streamJsonOrSse('/images', prepare: prepare).toList(),
          throwsA(
            isA<JsonHttpException>()
                .having((error) => error.statusCode, 'statusCode', 200)
                .having(
                  (error) => error.requestId,
                  'requestId',
                  'server-request',
                )
                .having(
                  (error) => error.toString(),
                  'public text',
                  isNot(contains('private-invalid')),
                ),
          ),
        );
      }
    },
  );
  test('pre-cancellation never prepares or dispatches', () async {
    final token = CancellationToken()..cancel();
    final mock = MockClient((_) async => throw StateError('Must not send'));
    final client = JsonHttpClient(
      baseUrl: 'https://example.invalid',
      httpClient: mock,
    );
    addTearDown(client.close);
    addTearDown(mock.close);
    await expectLater(
      client
          .streamJsonOrSse(
            '/images',
            cancellation: token,
            prepare: () => throw StateError('Must not prepare'),
          )
          .toList(),
      throwsA(isA<RunCancelled>()),
    );
  });
  test(
    'cancellation during headers releases and discards a late response body',
    () async {
      final started = Completer<void>();
      final response = Completer<http.StreamedResponse>();
      var bodyCancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => bodyCancelled = true,
      );
      final mock = MockClient.streaming((_, _) {
        started.complete();
        return response.future;
      });
      final client = JsonHttpClient(
        baseUrl: 'https://example.invalid',
        httpClient: mock,
      );
      addTearDown(client.close);
      addTearDown(mock.close);
      final token = CancellationToken();
      final settled = expectLater(
        client
            .streamJsonOrSse('/images', cancellation: token, prepare: prepare)
            .toList(),
        throwsA(isA<RunCancelled>()),
      );
      await started.future;
      token.cancel();
      await settled.timeout(const Duration(seconds: 1));
      response.complete(
        http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(bodyCancelled, true);
      await body.close();
    },
  );
  test(
    'JSON fallback deadline cancels a stalled body without resubmission',
    () async {
      var calls = 0;
      var bodyCancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => bodyCancelled = true,
      );
      final mock = MockClient.streaming((_, _) async {
        calls++;
        return http.StreamedResponse(
          body.stream,
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = JsonHttpClient(
        baseUrl: 'https://example.invalid',
        requestTimeout: const Duration(milliseconds: 50),
        httpClient: mock,
      );
      addTearDown(client.close);
      addTearDown(mock.close);
      await expectLater(
        client
            .streamJsonOrSse('/images', prepare: prepare)
            .toList()
            .timeout(const Duration(seconds: 1)),
        throwsA(
          isA<JsonHttpException>().having(
            (error) => error.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
      expect(calls, 1);
      expect(bodyCancelled, true);
      await body.close();
    },
  );
}
