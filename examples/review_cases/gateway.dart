// Offline consumer exercise. Uses a synthetic loopback fixture, not Vercel.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_vercel_gateway/agent_weave_vercel_gateway.dart'
    as gateway;

const schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'answer': {'type': 'integer'},
  },
  'required': ['answer'],
};

Future<void> main() async {
  await cancellation();
  await metadataAndIsolation();
  await diagnostics();
  for (final responses in [true, false]) {
    await journey(responses);
  }
}

Future<void> journey(bool responses) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  server.listen((req) async {
    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
    count++;
    assert(
      req.uri.path == (responses ? '/v1/responses' : '/v1/chat/completions'),
    );
    assert(req.headers.value('authorization') == 'Bearer token-$count');
    final opts = body['providerOptions'] as Map;
    assert(opts['gateway']['byok']['openai'][0]['apiKey'] == 'key-$count');
    assert(opts['gateway']['tags'][0] == 'fixture');
    assert(opts['anthropic']['thinking'] == true);
    if (count == 1) {
      assert(
        responses
            ? body['text']['format']['type'] == 'json_schema'
            : body['response_format']['type'] == 'json_schema',
      );
    } else if (count == 2) {
      assert((body['tools'] as List).isNotEmpty);
    } else {
      final history = jsonEncode(responses ? body['input'] : body['messages']);
      assert(history.contains('42'));
      assert(!history.contains('key-') && !history.contains('token-'));
    }
    req.response.headers.contentType = ContentType('text', 'event-stream');
    void event(Map<String, Object?> e) =>
        req.response.write('data: ${jsonEncode(e)}\n\n');
    if (responses) {
      if (count == 2) {
        event({
          'type': 'response.output_item.done',
          'sequence_number': 0,
          'output_index': 0,
          'item': {
            'type': 'function_call',
            'id': 'item',
            'call_id': 'call',
            'name': 'double',
            'arguments': '{"answer":21}',
            'status': 'completed',
          },
        });
      } else {
        event({
          'type': 'response.output_text.delta',
          'sequence_number': 0,
          'item_id': 'item',
          'output_index': 0,
          'content_index': 0,
          'delta': count == 1 ? '{"answer":42}' : '42',
        });
      }
      event({
        'type': 'response.completed',
        'sequence_number': 1,
        'response': {
          'id': 'r',
          'object': 'response',
          'created_at': 0,
          'status': 'completed',
          'model': 'fixture',
          'output': <Object>[],
        },
      });
    } else {
      event({
        'id': 'c',
        'object': 'chat.completion.chunk',
        'created': 0,
        'model': 'fixture',
        'choices': [
          {
            'index': 0,
            'delta': count == 2
                ? {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call',
                        'type': 'function',
                        'function': {
                          'name': 'double',
                          'arguments': '{"answer":21}',
                        },
                      },
                    ],
                  }
                : {'content': count == 1 ? '{"answer":42}' : '42'},
            'finish_reason': count == 2 ? 'tool_calls' : 'stop',
          },
        ],
      });
      req.response.write('data: [DONE]\n\n');
    }
    await req.response.close();
  });
  var credentials = 0;
  final client = gateway.GatewayClient(
    baseUrl: 'http://127.0.0.1:${server.port}',
    credentialResolver: () {
      credentials++;
      return gateway.GatewayCredentials(
        token: 'token-$credentials',
        byok: {
          'openai': [
            {'apiKey': 'key-$credentials'},
          ],
        },
      );
    },
  );
  final options = gateway.GatewayOptions(tags: ['fixture']);
  final model = responses
      ? gateway.GatewayResponsesModel(
          client: client,
          model: 'fixture',
          options: options,
          providerOptions: {
            'anthropic': {'thinking': true},
          },
        )
      : gateway.GatewayChatModel(
          client: client,
          model: 'fixture',
          options: options,
          providerOptions: {
            'anthropic': {'thinking': true},
          },
        );
  try {
    final object = await generateObject<int>(
      model: model,
      schema: schema,
      decode: (json) => (json as Map<String, Object?>)['answer'] as int,
      prompt: 'Answer',
    );
    assert(object.value == 42);
    var calls = 0;
    final store = MemoryRunStore();
    final agent = AiAgent<String>(
      store: store,
      model: model,
      tools: [
        Tool<int, int, String>(
          name: 'double',
          description: 'Double',
          inputSchema: schema,
          outputSchema: const {'type': 'integer'},
          needsApproval: true,
          decode: (json) => json['answer'] as int,
          encode: (n) => n,
          execute: (n, context) {
            calls++;
            return n * 2;
          },
        ),
      ],
    );
    final paused = await agent.generate(
      ChatRequest(
        threadId: 't',
        runId: 'first',
        messages: [ChatMessage.user('Double 21', id: 'u')],
      ),
      ownerId: 'owner',
      context: 'app',
    );
    assert(paused.status == RunStatus.interrupted && calls == 0);
    final hydrated = jsonEncode(
      chatHydration(await store.load(ownerId: 'owner', threadId: 't')),
    );
    assert(!hydrated.contains('token-') && !hydrated.contains('key-'));
    assert(hydrated.contains('double'));

    final resumed = await agent.generate(
      ChatRequest(
        threadId: 't',
        runId: 'second',
        parentRunId: paused.runId,
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: 'app',
    );
    assert(resumed.text == '42' && calls == 1 && count == 3);
    final stored = jsonEncode(
      await store.load(ownerId: 'owner', threadId: 't'),
    );
    assert(!stored.contains('token-') && !stored.contains('key-'));
    print(
      'PASS ${responses ? 'Responses' : 'Chat'} schema and approval lifecycle with rotating credentials',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}

Future<void> cancellation() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  server.listen((request) async {
    requests++;
    await request.response.close();
  });
  final delayed = Completer<gateway.GatewayCredentials>();
  final client = gateway.GatewayClient(
    baseUrl: 'http://127.0.0.1:${server.port}',
    credentialResolver: () => delayed.future,
  );
  try {
    final token = CancellationToken();
    final result = client.createChat({
      'model': 'fixture',
      'messages': [],
    }, cancellation: token);
    token.cancel();
    try {
      await result;
      assert(false);
    } on RunCancelled {
      /* expected */
    }
    delayed.complete(gateway.GatewayCredentials(token: 'late'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    assert(requests == 0);
    print(
      'PASS cancellation before async credential resolution prevents dispatch',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}

Future<void> metadataAndIsolation() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  server.listen((req) async {
    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
    count++;
    assert(req.headers.value('authorization') == 'Bearer rotating-$count');
    if (count == 1) {
      req.response.headers.set('x-request-id', 'fixture-request');
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"id":"fixture","gateway_extra":42}');
    } else {
      assert(!jsonEncode(body['input']).contains('wrong-provider-reasoning'));
      assert(jsonEncode(body['input']).contains('visible'));
      req.response.headers.contentType = ContentType('text', 'event-stream');
      req.response.write(
        'data: ${jsonEncode({
          'type': 'response.completed',
          'sequence_number': 0,
          'response': {'id': 'r', 'object': 'response', 'created_at': 0, 'status': 'completed', 'model': 'fixture', 'output': <Object>[]},
        })}\n\n',
      );
    }
    await req.response.close();
  });
  var i = 0;
  final client = gateway.GatewayClient(
    baseUrl: 'http://127.0.0.1:${server.port}',
    credentialResolver: () =>
        gateway.GatewayCredentials(token: 'rotating-${++i}'),
  );
  try {
    final raw = await client.createChat({'model': 'fixture', 'messages': []});
    assert(
      raw.headers['x-request-id'] == 'fixture-request' &&
          raw.data['gateway_extra'] == 42,
    );
    final model = gateway.GatewayResponsesModel(
      client: client,
      model: 'fixture',
    );
    final events = await model
        .stream(
          ModelRequest(
            messages: [
              ChatMessage(
                id: 'a',
                role: MessageRole.assistant,
                content: [TextPart('visible')],
                providerData: {
                  'openai.responses': [
                    {'type': 'reasoning', 'id': 'wrong-provider-reasoning'},
                  ],
                },
              ),
            ],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    assert(
      events.whereType<ProviderOutput>().single.provider ==
          'vercel.gateway.responses',
    );
    print(
      'PASS native response headers and metadata; other provider replay excluded',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}

Future<void> diagnostics() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  server.listen((req) async {
    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
    count++;
    final opts = body['providerOptions']['gateway'] as Map;
    assert(opts['caching'] == 'auto' && opts['serviceTier'] == 'flex');
    assert(opts['sort'] == 'cost' && opts['futureOption'] == 'enabled');
    final secret = count == 1 ? 'static-key' : 'rotated-key';
    assert(req.headers.value('authorization') == 'Bearer $secret');
    req.response.headers.set('x-request-id', 'request-$secret');
    if (count == 1) {
      req.response.statusCode = 429;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'error': {'code': 'rate_limit', 'message': 'private $secret'},
        }),
      );
    } else {
      req.response.headers.contentType = ContentType('text', 'event-stream');
      req.response.write(
        'data: ${jsonEncode({
          'error': {'code': 'upstream', 'message': 'private $secret byok-secret'},
        })}\n\n',
      );
    }
    await req.response.close();
  });
  final options = gateway.GatewayOptions(
    caching: gateway.GatewayCaching.auto,
    serviceTier: gateway.GatewayServiceTier.flex,
    sort: gateway.GatewayProviderSort.cost,
    extra: {'futureOption': 'enabled'},
  );
  final fixed = gateway.GatewayClient.withApiKey(
    apiKey: 'static-key',
    baseUrl: 'http://127.0.0.1:${server.port}',
  );
  final rotating = gateway.GatewayClient(
    baseUrl: 'http://127.0.0.1:${server.port}',
    credentialResolver: () => gateway.GatewayCredentials(
      token: 'rotated-key',
      byok: {
        'openai': [
          {'apiKey': 'byok-secret'},
        ],
      },
    ),
  );
  try {
    try {
      await fixed.createChat({
        'model': 'fixture',
        'messages': [],
      }, options: options);
      assert(false);
    } on gateway.JsonHttpException catch (e) {
      assert(e.statusCode == 429 && e.requestId == 'request-[REDACTED]');
      final details = jsonEncode(e.details);
      assert(details.contains('rate_limit') && details.contains('[REDACTED]'));
      assert(
        !details.contains('static-key') && !e.toString().contains('private'),
      );
    }
    try {
      await rotating.streamResponse({
        'model': 'fixture',
        'input': 'hello',
      }, options: options).toList();
      assert(false);
    } on gateway.JsonHttpException catch (e) {
      final details = jsonEncode(e.details);
      assert(details.contains('upstream') && details.contains('[REDACTED]'));
      assert(
        !details.contains('rotated-key') && !details.contains('byok-secret'),
      );
      assert(e.requestId == 'request-[REDACTED]');
    }
    print('PASS typed routing, withApiKey, safe HTTP and stream diagnostics');
  } finally {
    fixed.close();
    rotating.close();
    await server.close(force: true);
  }
}
