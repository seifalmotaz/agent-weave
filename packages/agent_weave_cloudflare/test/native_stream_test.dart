import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_cloudflare/agent_weave_cloudflare.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final request = ModelRequest(
    messages: [ChatMessage.user('hello', id: 'u')],
    maxOutputTokens: 42,
  );
  test('streams text before completion with request headers and usage', () async {
    final body = StreamController<List<int>>();
    final started = Completer<void>();
    late Map<String, dynamic> sent;
    late Map<String, String> headers;
    final transport = MockClient.streaming((req, data) async {
      sent =
          jsonDecode(await utf8.decoder.bind(data).join())
              as Map<String, dynamic>;
      headers = req.headers;
      started.complete();
      return http.StreamedResponse(body.stream, 200);
    });
    final client = CloudflareClient.withApiToken(
      accountId: 'abc',
      apiToken: 'secret',
      httpClient: transport,
      gateway: CloudflareGatewayOptions(gatewayId: 'gw', skipCache: true),
    );
    final first = Completer<String>();
    final finished = Completer<void>();
    final events = <ModelEvent>[];
    final subscription =
        CloudflareChatModel(
              client: client,
              model: 'm',
              options: {'temperature': 0.4},
            )
            .stream(request, cancellation: CancellationToken())
            .listen(
              (event) {
                events.add(event);
                if (event is TextDelta && !first.isCompleted) {
                  first.complete(event.text);
                }
              },
              onDone: finished.complete,
              onError: finished.completeError,
            );
    await started.future;
    body.add(
      utf8.encode(
        'data: {"response":"hello","usage":{"prompt_tokens":2,"completion_tokens":1}}\n\n',
      ),
    );
    expect(await first.future.timeout(const Duration(seconds: 1)), 'hello');
    expect(finished.isCompleted, false);
    expect(events.whereType<TokenUsage>(), isEmpty);
    expect(sent, {
      'temperature': 0.4,
      'messages': [
        {'role': 'user', 'content': 'hello'},
      ],
      'max_tokens': 42,
      'stream': true,
    });
    expect(headers['cf-aig-gateway-id'], 'gw');
    expect(headers['cf-aig-skip-cache'], 'true');
    expect(headers['authorization'], 'Bearer secret');
    body.add(
      utf8.encode(
        'data: {"response":"!","usage":{"prompt_tokens":2,"completion_tokens":3}}\n\ndata: [DONE]\n\n',
      ),
    );
    await finished.future.timeout(const Duration(seconds: 1));
    expect(events.whereType<TextDelta>().map((e) => e.text), ['hello', '!']);
    final usage = events.whereType<TokenUsage>().single;
    expect([usage.inputTokens, usage.outputTokens, usage.model], [2, 3, null]);
    expect(events.last, isA<ModelFinished>());
    await subscription.cancel();
    await body.close();
    client.close();
    transport.close();
  });
  test('rejects incomplete, malformed, unsupported and error streams', () async {
    for (final wire in [
      'data: {"response":"partial","usage":{"prompt_tokens":2,"completion_tokens":1}}\n\n',
      'data: [DONE]\n\n',
      'data: {"response":42}\n\ndata: [DONE]\n\n',
      'data: {"tool_calls":[]}\n\ndata: [DONE]\n\n',
      'data: {"choices":[]}\n\ndata: [DONE]\n\n',
      'data: {"error":"failed"}\n\n',
      'data: {bad}\n\n',
    ]) {
      final transport = MockClient(
        (_) async => http.Response(
          wire,
          200,
          headers: {'content-type': 'text/event-stream'},
        ),
      );
      final client = CloudflareClient.withApiToken(
        accountId: 'abc',
        apiToken: 'secret',
        httpClient: transport,
      );
      final events = <ModelEvent>[];
      await expectLater(
        CloudflareChatModel(
          client: client,
          model: 'm',
        ).stream(request, cancellation: CancellationToken()).map((e) {
          events.add(e);
          return e;
        }).toList(),
        throwsA(anything),
      );
      expect(events.whereType<ModelFinished>(), isEmpty);
      expect(events.whereType<TokenUsage>(), isEmpty);
      client.close();
      transport.close();
    }
  });
  test('cancel before credentials and after text', () async {
    final credentials = Completer<String>();
    var sent = false;
    final transport = MockClient((_) async {
      sent = true;
      return http.Response('', 200);
    });
    final client = CloudflareClient(
      accountId: 'abc',
      tokenResolver: () => credentials.future,
      httpClient: transport,
    );
    final token = CancellationToken();
    final result = CloudflareChatModel(
      client: client,
      model: 'm',
    ).stream(request, cancellation: token).toList();
    token.cancel();
    await expectLater(result, throwsA(isA<RunCancelled>()));
    credentials.complete('secret');
    await Future<void>.delayed(Duration.zero);
    expect(sent, false);
    client.close();
    transport.close();
    final body = StreamController<List<int>>();
    final started = Completer<void>();
    final httpClient = MockClient.streaming((req, data) async {
      await data.drain<void>();
      started.complete();
      return http.StreamedResponse(body.stream, 200);
    });
    final streamingClient = CloudflareClient.withApiToken(
      accountId: 'abc',
      apiToken: 'secret',
      httpClient: httpClient,
    );
    final first = Completer<void>();
    final parent = CancellationToken();
    final subscription =
        CloudflareChatModel(
          client: streamingClient,
          model: 'm',
        ).stream(request, cancellation: parent).listen((e) {
          if (e is TextDelta) first.complete();
        });
    await started.future;
    body.add(utf8.encode('data: {"response":"x"}\n\n'));
    await first.future;
    await subscription.cancel().timeout(const Duration(seconds: 1));
    expect(parent.isCancelled, false);
    await body.close();
    streamingClient.close();
    httpClient.close();
  });
  test('schema and explicit opt out use buffered requests', () async {
    final bodies = <Map<String, dynamic>>[];
    final transport = MockClient((req) async {
      bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{"success":true,"result":{"response":"ok"}}', 200);
    });
    final client = CloudflareClient.withApiToken(
      accountId: 'abc',
      apiToken: 'secret',
      httpClient: transport,
    );
    await CloudflareChatModel(
      client: client,
      model: 'm',
      streamText: false,
    ).stream(request, cancellation: CancellationToken()).toList();
    await CloudflareChatModel(client: client, model: 'm')
        .stream(
          ModelRequest(
            messages: [ChatMessage.user('hello', id: 'u')],
            outputSchema: {'type': 'object'},
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    expect(bodies.every((body) => !body.containsKey('stream')), true);
    expect(bodies.last['response_format'], {
      'type': 'json_schema',
      'json_schema': {'type': 'object'},
    });
    client.close();
    transport.close();
  });
}
