@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('raw create, count and GET preserve JSON, headers and query', () async {
    final calls = <http.Request>[];
    final transport = MockClient((request) async {
      calls.add(request);
      return http.Response(
        '{"future":{"value":[1,true,null]}}',
        201,
        headers: {'request-id': 'req-1', 'x-extra': 'kept'},
      );
    });
    final client = AnthropicNativeClient.withApiKey(
      apiKey: 'secret',
      httpClient: transport,
      apiVersion: 'test-version',
      betas: ['first', 'second'],
      workspaceId: 'workspace',
      userProfileId: 'profile',
      headers: {'X-Custom': 'custom'},
    );
    addTearDown(() {
      client.close();
      transport.close();
    });
    final body = <String, Object?>{
      'model': 'future',
      'unknown': {
        'nested': [1, true, null],
      },
    };
    final response = await client.createMessage(
      body,
      query: {
        'tag': ['one', 'two'],
      },
    );
    expect(response.statusCode, 201);
    expect(response.data, {
      'future': {
        'value': [1, true, null],
      },
    });
    expect(response.headers['request-id'], 'req-1');
    expect(() => response.data['new'] = 1, throwsUnsupportedError);
    expect(
      () => (response.data['future'] as Map)['new'] = 1,
      throwsUnsupportedError,
    );
    await client.countTokens(body);
    await client.send(
      '/v1/custom',
      method: HttpMethod.get,
      query: {
        'tag': ['a b', 'c'],
      },
    );
    expect(calls.map((r) => r.url.path), [
      '/v1/messages',
      '/v1/messages/count_tokens',
      '/v1/custom',
    ]);
    expect(jsonDecode(calls[0].body), body);
    expect(jsonDecode(calls[1].body), body);
    expect(calls[0].url.queryParametersAll['tag'], ['one', 'two']);
    expect(calls[2].url.queryParametersAll['tag'], ['a b', 'c']);
    expect(calls[2].method, 'GET');
    expect(calls[2].body, isEmpty);
    for (final request in calls) {
      expect(request.headers['anthropic-version'], 'test-version');
      expect(request.headers['anthropic-beta'], 'first,second');
      expect(request.headers['anthropic-workspace-id'], 'workspace');
      expect(request.headers['anthropic-user-profile-id'], 'profile');
      expect(request.headers['x-custom'], 'custom');
      expect(request.headers['x-api-key'], 'secret');
    }
    expect(jsonDecode(calls[0].body), isNot(contains('anthropic-beta')));
  });

  test('snapshots request before asynchronous credentials resolve', () async {
    final credentials = Completer<String>();
    final transport = MockClient((request) async {
      expect(jsonDecode(request.body), {
        'nested': {
          'items': [1],
        },
      });
      return http.Response('{}', 200);
    });
    final client = AnthropicNativeClient(
      credentialResolver: () => credentials.future,
      httpClient: transport,
    );
    final items = <Object?>[1];
    final body = <String, Object?>{
      'nested': <String, Object?>{'items': items},
    };
    final pending = client.createMessage(body);
    items.add(2);
    credentials.complete('key');
    await pending;
    client.close();
    transport.close();
  });

  test('stream snapshots body, headers, and query before listening', () async {
    final transport = MockClient((request) async {
      expect(jsonDecode(request.body), {
        'nested': {
          'items': [1],
        },
        'stream': true,
      });
      expect(request.headers['x-custom'], 'original');
      expect(request.url.queryParametersAll['tag'], ['original']);
      return http.Response('data: {"type":"message_stop"}\n\n', 200);
    });
    final client = AnthropicNativeClient.withApiKey(
      apiKey: 'secret',
      httpClient: transport,
    );
    final items = <Object?>[1];
    final tags = ['original'];
    final headers = {'x-custom': 'original'};
    final stream = client.streamMessages(
      {
        'nested': {'items': items},
      },
      query: {'tag': tags},
      headers: headers,
    );
    items.add(2);
    tags.add('changed');
    headers['x-custom'] = 'changed';
    final result = await stream.toList();
    expect(result, hasLength(1));
    expect(
      () => (result.single as JsonSseData).data['type'] = 'changed',
      throwsUnsupportedError,
    );
    client.close();
    transport.close();
  });

  test('guards configuration and credential ownership', () async {
    for (final url in [
      'file:///tmp/x',
      'https://user:pass@example.com',
      'https://example.com/#fragment',
    ]) {
      expect(
        () => AnthropicNativeClient.withApiKey(apiKey: 'x', baseUrl: url),
        throwsArgumentError,
      );
    }
    expect(
      () => AnthropicNativeClient.withApiKey(
        apiKey: 'x',
        requestTimeout: Duration.zero,
      ),
      throwsArgumentError,
    );
    for (final name in [
      'X-API-KEY',
      'Authorization',
      'Cookie',
      'Proxy-Authorization',
    ]) {
      expect(
        () =>
            AnthropicNativeClient.withApiKey(apiKey: 'x', headers: {name: 'x'}),
        throwsArgumentError,
      );
    }
    final transport = MockClient((_) async => fail('must not send'));
    final client = AnthropicNativeClient.withApiKey(
      apiKey: 'x',
      httpClient: transport,
    );
    expect(() => client.createMessage({'stream': true}), throwsArgumentError);
    await expectLater(
      client.send('/v1/messages', headers: {'Authorization': 'x'}),
      throwsArgumentError,
    );
    await expectLater(
      client.send('/v1/messages', method: HttpMethod.get, body: {}),
      throwsArgumentError,
    );
    client.close();
    transport.close();
  });

  test('rotates credentials and redacts errors and diagnostic headers', () async {
    var calls = 0;
    final transport = MockClient((request) async {
      calls++;
      if (calls == 1) {
        expect(request.headers['x-api-key'], 'first-secret');
        return http.Response('{}', 200);
      }
      expect(request.headers['x-api-key'], 'second-secret');
      return http.Response(
        '{"error":{"message":"second-secret", "second-secret": ["second-secret"]}}',
        400,
        headers: {
          'request-id': 'id-second-secret',
          'set-cookie': 'second-secret',
          'x-other': 'second-secret',
        },
      );
    });
    final client = AnthropicNativeClient(
      credentialResolver: () => calls == 0 ? 'first-secret' : 'second-secret',
      httpClient: transport,
    );
    await client.createMessage({});
    try {
      await client.createMessage({});
      fail('expected failure');
    } on JsonHttpException catch (error) {
      expect(error.statusCode, 400);
      expect(error.requestId, 'id-[REDACTED]');
      expect(error.details.toString(), isNot(contains('second-secret')));
      expect(
        error.responseHeaders.toString(),
        isNot(contains('second-secret')),
      );
      expect(error.responseHeaders, isNot(contains('set-cookie')));
      expect(error.toString(), isNot(contains('second-secret')));
    }
    client.close();
    transport.close();
  });

  test(
    'resolver failures and invalid credentials do not disclose secrets',
    () async {
      final transport = MockClient((_) async => fail('must not send'));
      for (final resolver in <AnthropicCredentialResolver>[
        () => throw StateError('private resolver data'),
        () => '',
        () => 'bad\r\nkey',
      ]) {
        final client = AnthropicNativeClient(
          credentialResolver: resolver,
          httpClient: transport,
        );
        await expectLater(
          client.createMessage({}),
          throwsA(
            isA<JsonHttpException>().having(
              (e) => e.toString(),
              'message',
              isNot(contains('private resolver data')),
            ),
          ),
        );
        client.close();
      }
      transport.close();
    },
  );

  for (final (name, wire, valid) in [
    (
      'error',
      'event: error\ndata: {"type":"error","error":{"message":"secret"}}\n\n',
      false,
    ),
    ('early EOF', 'data: {"type":"message_start"}\n\n', false),
    ('malformed', 'data: {not-json}\n\n', false),
    (
      'complete',
      'data: {"type":"future_event","new_field":42}\n\ndata: {"type":"message_stop"}\n\n',
      true,
    ),
  ]) {
    test('SSE $name', () async {
      final transport = MockClient((request) async {
        expect(jsonDecode(request.body), {'model': 'm', 'stream': true});
        return http.Response(
          wire,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final client = AnthropicNativeClient.withApiKey(
        apiKey: 'secret',
        httpClient: transport,
      );
      final stream = client.streamMessages({'model': 'm', 'stream': false});
      if (valid) {
        final events = await stream.toList();
        expect((events.first as JsonSseData).data['new_field'], 42);
      } else {
        await expectLater(
          stream.toList(),
          throwsA(
            isA<JsonHttpException>().having(
              (e) => e.toString() + e.details.toString(),
              'redaction',
              isNot(contains('secret')),
            ),
          ),
        );
      }
      client.close();
      transport.close();
    });
  }

  test(
    'pre-cancel and cancellation during credential resolution prevent dispatch',
    () async {
      var sends = 0;
      var resolutions = 0;
      final pendingKey = Completer<String>();
      final transport = MockClient((_) async {
        sends++;
        return http.Response('{}', 200);
      });
      final client = AnthropicNativeClient(
        credentialResolver: () {
          resolutions++;
          return pendingKey.future;
        },
        httpClient: transport,
      );
      final cancelled = CancellationToken()..cancel();
      await expectLater(
        client.createMessage({}, cancellation: cancelled),
        throwsA(isA<RunCancelled>()),
      );
      expect(resolutions, 0);
      final token = CancellationToken();
      final pending = client.createMessage({}, cancellation: token);
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await expectLater(
        pending.timeout(const Duration(seconds: 1)),
        throwsA(isA<RunCancelled>()),
      );
      pendingKey.complete('key');
      await Future<void>.delayed(Duration.zero);
      expect(sends, 0);
      client.close();
      transport.close();
    },
  );

  group('local HTTP cancellation', () {
    late HttpServer server;
    late StreamSubscription<HttpRequest> serverSubscription;
    late Future<void> Function(HttpRequest) handler;
    late http.Client borrowed;
    late AnthropicNativeClient client;
    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverSubscription = server.listen((request) {
        unawaited(handler(request));
      });
      borrowed = http.Client();
      client = AnthropicNativeClient.withApiKey(
        apiKey: 'key',
        baseUrl: 'http://127.0.0.1:${server.port}',
        httpClient: borrowed,
        requestTimeout: const Duration(seconds: 1),
      );
    });
    tearDown(() async {
      client.close();
      borrowed.close();
      await serverSubscription.cancel();
      await server.close(force: true);
    });

    test(
      'pending headers cancellation leaves sibling and borrowed client usable',
      () async {
        final received = Completer<void>();
        final release = Completer<void>();
        handler = (request) async {
          if (request.uri.path == '/v1/slow') {
            received.complete();
            await release.future;
          }
          request.response.write('{}');
          try {
            await request.response.close();
          } catch (_) {}
        };
        final token = CancellationToken();
        final slow = client.send('/v1/slow', cancellation: token);
        await received.future.timeout(const Duration(seconds: 1));
        final sibling = client.send('/v1/fast');
        token.cancel();
        await expectLater(
          slow.timeout(const Duration(seconds: 1)),
          throwsA(isA<RunCancelled>()),
        );
        expect((await sibling).data, isEmpty);
        client.close();
        expect(
          (await borrowed.get(
            Uri.parse('http://127.0.0.1:${server.port}/ping'),
          )).statusCode,
          200,
        );
        release.complete();
      },
    );

    test('request timeout interrupts pending headers', () async {
      final received = Completer<void>();
      final release = Completer<void>();
      handler = (request) async {
        received.complete();
        await release.future;
        try {
          await request.response.close();
        } catch (_) {}
      };
      final short = AnthropicNativeClient.withApiKey(
        apiKey: 'key',
        baseUrl: 'http://127.0.0.1:${server.port}',
        httpClient: borrowed,
        requestTimeout: const Duration(milliseconds: 80),
      );
      final pending = short.createMessage({});
      await received.future.timeout(const Duration(seconds: 1));
      await expectLater(
        pending.timeout(const Duration(seconds: 1)),
        throwsA(isA<JsonHttpException>()),
      );
      short.close();
      release.complete();
    });

    test('cancellation interrupts stalled SSE body', () async {
      final ready = Completer<void>();
      final release = Completer<void>();
      handler = (request) async {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write('data: {"type":"message_start"}\n\n');
        await request.response.flush();
        ready.complete();
        await release.future;
        try {
          await request.response.close();
        } catch (_) {}
      };
      final token = CancellationToken();
      final events = client.streamMessages({}, cancellation: token).toList();
      await ready.future.timeout(const Duration(seconds: 1));
      token.cancel();
      await expectLater(
        events.timeout(const Duration(seconds: 1)),
        throwsA(isA<RunCancelled>()),
      );
      release.complete();
    });

    test('unsubscribing pending stream does not cancel a sibling', () async {
      final ready = Completer<void>();
      final release = Completer<void>();
      handler = (request) async {
        if (request.uri.path == '/v1/messages') {
          ready.complete();
          await release.future;
        }
        request.response.write('{}');
        try {
          await request.response.close();
        } catch (_) {}
      };
      final subscription = client.streamMessages({}).listen((_) {});
      await ready.future.timeout(const Duration(seconds: 1));
      await subscription.cancel().timeout(const Duration(seconds: 1));
      expect((await client.send('/v1/other')).data, isEmpty);
      release.complete();
    });
  });
}
