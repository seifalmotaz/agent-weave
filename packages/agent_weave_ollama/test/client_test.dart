import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_ollama/agent_weave_ollama.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test('routes, query, headers and rotating credentials', () async {
    final requests = <http.Request>[];
    var number = 0;
    final client = OllamaNativeClient(
      baseUrl: 'http://localhost:11434/base',
      credentialResolver: () => 'key${++number}',
      httpClient: MockClient((r) async {
        requests.add(r);
        return http.Response('{"ok":true}', 200);
      }),
    );
    await client.embed(
      {'model': 'a'},
      query: {
        'x': ['1', '2'],
      },
    );
    await client.show({'model': 'a'});
    expect(requests[0].url.path, endsWith('/api/embed'));
    expect(requests[0].url.queryParametersAll['x'], ['1', '2']);
    expect(requests[0].headers['authorization'], 'Bearer key1');
    expect(requests[1].headers['authorization'], 'Bearer key2');
    client.close();
  });
  test('credentials forbidden in headers', () {
    expect(
      () => OllamaNativeClient(headers: {'Authorization': 'bad'}),
      throwsArgumentError,
    );
  });
  test('nonstream chat forces stream false and rejects true', () async {
    final client = OllamaNativeClient(
      httpClient: MockClient((r) async {
        expect(jsonDecode(r.body)['stream'], false);
        return http.Response('{}', 200);
      }),
    );
    await client.createChat({'model': 'm'});
    expect(() => client.createGenerate({'stream': true}), throwsArgumentError);
    client.close();
  });
  test('stream snapshots body and query before listening', () async {
    final body = <String, Object?>{'model': 'first'};
    final query = <String, List<String>>{
      'a': ['first'],
    };
    final client = OllamaNativeClient(
      httpClient: MockClient((r) async {
        expect(jsonDecode(r.body)['model'], 'first');
        expect(r.url.queryParameters['a'], 'first');
        expect(jsonDecode(r.body)['stream'], true);
        return http.Response('{"done":true}\n', 200);
      }),
    );
    final stream = client.streamGenerate(body, query: query);
    body['model'] = 'second';
    query['a']![0] = 'second';
    expect(await stream.toList(), hasLength(1));
    client.close();
  });
  test('NDJSON handles CRLF and final line without newline', () async {
    final client = OllamaNativeClient(
      httpClient: MockClient(
        (_) async => http.Response(
          '{"response":"a","done":false}\r\n{"done":true}',
          200,
        ),
      ),
    );
    final events = await client.streamGenerate({}).toList();
    expect(events.map((e) => e.data['done']), [false, true]);
    client.close();
  });
  for (final fixture in [
    '{"done":false}\n',
    '{"done":true}\n{"done":true}\n',
    '{not json}\n',
    '{"error":"bad"}\n',
  ]) {
    test('rejects invalid or incomplete stream $fixture', () async {
      final client = OllamaNativeClient(
        httpClient: MockClient((_) async => http.Response(fixture, 200)),
      );
      await expectLater(
        client.streamChat({}).toList(),
        throwsA(isA<Exception>()),
      );
      client.close();
    });
  }
  test('error secrets are redacted from body and headers', () async {
    final client = OllamaNativeClient(
      credentialResolver: () => 'my-secret',
      httpClient: MockClient(
        (_) async => http.Response(
          '{"error":"my-secret"}',
          400,
          headers: {'x-request-id': 'my-secret'},
        ),
      ),
    );
    try {
      await client.embed({});
      fail('expected error');
    } catch (e) {
      expect(e.toString(), isNot(contains('my-secret')));
    }
    client.close();
  });
  test('credential resolver failure hides original error', () async {
    final client = OllamaNativeClient(
      credentialResolver: () => throw StateError('sensitive'),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    try {
      await client.show({});
      fail('expected error');
    } catch (e) {
      expect(e.toString(), isNot(contains('sensitive')));
    }
    client.close();
  });
  test('cancel during credential resolution does not send request', () async {
    final ready = Completer<String?>();
    var sent = false;
    final client = OllamaNativeClient(
      credentialResolver: () => ready.future,
      httpClient: MockClient((_) async {
        sent = true;
        return http.Response('{"done":true}\n', 200);
      }),
    );
    final token = CancellationToken();
    final result = client.streamChat({}, cancellation: token).toList();
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    ready.complete('key');
    await expectLater(result, throwsA(anything));
    expect(sent, false);
    client.close();
  });
  test('cancelling one pending stream leaves its sibling usable', () async {
    final pending = Completer<String?>();
    var resolutions = 0;
    final client = OllamaNativeClient(
      credentialResolver: () => ++resolutions == 1 ? pending.future : 'other',
      httpClient: MockClient(
        (_) async => http.Response('{"done":true}\n', 200),
      ),
    );
    final token = CancellationToken();
    final first = client.streamChat({}, cancellation: token).toList();
    await Future<void>.delayed(Duration.zero);
    final second = client.streamChat({}).toList();
    token.cancel();
    pending.complete('key');
    await expectLater(first, throwsA(anything));
    expect(await second, hasLength(1));
    client.close();
  });
}
