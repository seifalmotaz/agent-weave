import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Map<String, Object?> start() => {
  'type': 'message_start',
  'message': {
    'id': 'm',
    'type': 'message',
    'role': 'assistant',
    'model': 'fixture',
    'content': <Object?>[],
    'usage': {'input_tokens': 5, 'output_tokens': 0},
  },
};
Map<String, Object?> block(int i, Map<String, Object?> data) => {
  'type': 'content_block_start',
  'index': i,
  'content_block': data,
};
Map<String, Object?> delta(int i, Map<String, Object?> data) => {
  'type': 'content_block_delta',
  'index': i,
  'delta': data,
};
Map<String, Object?> stop(int i) => {'type': 'content_block_stop', 'index': i};
Map<String, Object?> finish(String reason) => {
  'type': 'message_delta',
  'delta': {'stop_reason': reason, 'stop_sequence': null},
  'usage': {
    'output_tokens': 2,
    'cache_read_input_tokens': 2,
    'cache_creation_input_tokens': 3,
    'output_tokens_details': {'thinking_tokens': 1},
  },
};
List<Map<String, Object?>> textEvents(String text) => [
  start(),
  block(0, {'type': 'text', 'text': ''}),
  delta(0, {'type': 'text_delta', 'text': text}),
  stop(0),
  finish('end_turn'),
  {'type': 'message_stop'},
];
const schema = {
  'type': 'object',
  'properties': {
    'value': {'type': 'integer'},
  },
  'required': ['value'],
  'additionalProperties': false,
};
Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var calls = 0;
  final bodies = <Map<String, dynamic>>[];
  final seenKeys = <String?>[];
  server.listen((req) async {
    final body =
        jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    check(req.uri.path == '/v1/messages', 'wrong path');
    bodies.add(body);
    seenKeys.add(req.headers.value('x-api-key'));
    check(
      req.headers.value('anthropic-version') == '2023-06-01',
      'missing version',
    );
    final n = calls++;
    if (n == 1) {
      check(
        body['output_config']['format']['schema']['properties']['value']['type'] ==
            'integer',
        'schema missing',
      );
    }
    if (n == 3) {
      final messages = body['messages'] as List;
      check(
        messages[1]['content'][0]['signature'] == 'signed' &&
            messages[1]['content'][0]['future_extra'] == 'private-extra',
        'thinking signature not replayed',
      );
      check(messages[1]['content'][1]['type'] == 'tool_use', 'tool missing');
      check(
        messages[1]['content'][2]['citations'][0]['future'] ==
            'PRIVATE-CITATION',
        'citation replay',
      );
      check(
        messages[2]['content'][0]['tool_use_id'] == 'call-1',
        'tool result missing',
      );
      check(
        messages[2]['content'][0]['content'].toString().contains('42'),
        'tool result value missing',
      );
    }
    if (n == 4) {
      req.response.statusCode = 400;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'type': 'error',
          'error': {
            'type': 'invalid_request_error',
            'message': 'fixture bad request key-5',
          },
        }),
      );
      await req.response.close();
      return;
    }
    final events = n == 0
        ? textEvents('hello')
        : n == 1
        ? textEvents('{"value":42}')
        : n == 2
        ? [
            start(),
            block(0, {
              'type': 'thinking',
              'thinking': '',
              'signature': '',
              'future_extra': 'private-extra',
            }),
            delta(0, {'type': 'thinking_delta', 'thinking': 'reason'}),
            delta(0, {'type': 'signature_delta', 'signature': 'signed'}),
            stop(0),
            block(1, {
              'type': 'tool_use',
              'id': 'call-1',
              'name': 'double',
              'input': {},
            }),
            delta(1, {
              'type': 'input_json_delta',
              'partial_json': '{"value":21}',
            }),
            stop(1),
            block(2, {'type': 'text', 'text': ''}),
            delta(2, {'type': 'text_delta', 'text': 'Working'}),
            delta(2, {
              'type': 'citations_delta',
              'citation': {
                'type': 'char_location',
                'document_title': 'Source',
                'document_index': 0,
                'cited_text': 'S',
                'start_char_index': 0,
                'end_char_index': 1,
                'future': 'PRIVATE-CITATION',
              },
            }),
            stop(2),
            finish('tool_use'),
            {'type': 'message_stop'},
          ]
        : textEvents('42');
    req.response.headers.contentType = ContentType('text', 'event-stream');
    for (final event in events) {
      req.response.write(
        'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
      );
    }
    await req.response.close();
  });
  var key = 0;
  final borrowed = http.Client();
  final client = api.AnthropicNativeClient(
    credentialResolver: () => 'key-${++key}',
    baseUrl: 'http://127.0.0.1:${server.port}',
    httpClient: borrowed,
  );
  final model = client.chatModel(
    model: 'fixture',
    configure: (request) => {
      ...request,
      'cache_control': {'type': 'ephemeral'},
      'future_option': {'nested': true},
    },
  );
  try {
    final text = await generateText(model: model, prompt: 'hello');
    check(text.text == 'hello', 'text');
    final object = await generateObject<int>(
      model: model,
      prompt: 'answer',
      schema: schema,
      decode: (x) => (x as Map)['value'] as int,
    );
    check(object.value == 42, 'object');
    var count = 0;
    final store = MemoryRunStore();
    AiAgent<void> agent() => AiAgent<void>(
      model: client.chatModel(
        model: 'fixture',
        citations: true,
        configure: model.configure,
      ),
      store: store,
      tools: [
        Tool<int, int, void>(
          needsApproval: true,
          name: 'double',
          description: 'Double',
          inputSchema: schema,
          outputSchema: const {'type': 'integer'},
          decode: (j) => j['value'] as int,
          encode: (x) => x,
          execute: (x, c) {
            count++;
            return x * 2;
          },
        ),
      ],
    );
    final paused = await agent().generate(
      ChatRequest(
        threadId: 't',
        runId: 'r',
        messages: [
          ChatMessage(
            id: 'u',
            role: MessageRole.user,
            content: [
              DocumentPart.bytes(
                utf8.encode('Source.'),
                mimeType: 'text/plain',
              ),
              const TextPart('double'),
            ],
          ),
        ],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(paused.status == RunStatus.interrupted && count == 0, 'approval');
    final result = await agent().generate(
      ChatRequest(
        threadId: 't',
        runId: 'r2',
        parentRunId: paused.runId,
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(count == 1 && result.text == '42', 'tool loop');
    check(
      jsonEncode(
        result.responseMessages.map((m) => m.providerData).toList(),
      ).contains('anthropic.messages.metadata'),
      'metadata missing',
    );
    check(
      !jsonEncode(
            chatHydration(await store.load(ownerId: 'owner', threadId: 't')),
          ).contains('private-extra') &&
          !jsonEncode(
            chatHydration(await store.load(ownerId: 'owner', threadId: 't')),
          ).contains('PRIVATE-CITATION'),
      'private data leaked',
    );
    check(
      result.usage?.inputTokens == 10 &&
          result.usage?.cachedInputTokens == 2 &&
          result.usage?.reasoningTokens == 1 &&
          result.usage?.outputTokens == 2 &&
          result.usage?.model == 'fixture',
      'usage',
    );
    check(
      bodies.every(
        (b) =>
            b['cache_control']['type'] == 'ephemeral' &&
            b['future_option']['nested'] == true,
      ),
      'native option lost',
    );
    check(seenKeys.join(',') == 'key-1,key-2,key-3,key-4', 'rotation');
    print(
      'PASS text, structured output, two-invocation tool and signed thinking replay over loopback HTTP',
    );
    try {
      await generateText(model: model, prompt: 'bad');
      throw StateError('expected API failure');
    } on AgentRunException catch (e) {
      check(e.code == 'MODEL_FAILED', 'error code');
      check(
        !e.toString().contains('key-5') &&
            !e.cause.toString().contains('key-5'),
        'credential leaked',
      );
      print('PASS HTTP 400 => ${e.code}, cause=${e.cause}');
    }
    check(calls == 5, 'request count');
  } finally {
    client.close();
    borrowed.close();
    await server.close(force: true);
  }
  await transportCases();
}

Future<void> transportCases() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final preHeaders = Completer<void>();
  final bodyStarted = Completer<void>();
  final siblingStarted = Completer<void>();
  final release = Completer<void>();
  server.listen((req) async {
    if (req.uri.path == '/alive') {
      req.response.write('ok');
      await req.response.close();
      return;
    }
    final body =
        jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    if (body['model'] == 'pending') {
      preHeaders.complete();
      await release.future;
      await req.response.close();
      return;
    }
    if (body['model'] == 'body') {
      req.response.headers.contentType = ContentType('text', 'event-stream');
      req.response.write('data: ${jsonEncode(start())}\n\n');
      await req.response.flush();
      bodyStarted.complete();
      await release.future;
      await req.response.close();
      return;
    }
    if (body['model'] == 'sibling') {
      req.response.headers.contentType = ContentType('text', 'event-stream');
      siblingStarted.complete();
      await release.future;
      req.response.write('data: ${jsonEncode({'type': 'message_stop'})}\n\n');
      await req.response.close();
      return;
    }
    if (body['model'] == 'malformed') {
      req.response.headers.contentType = ContentType('text', 'event-stream');
      req.response.write('data: {broken}\n\n');
      await req.response.close();
      return;
    }
    if (body['model'] == 'unknown') {
      req.response.headers.contentType = ContentType('text', 'event-stream');
      for (final event in [
        start(),
        block(0, {'type': 'future_private', 'data': 'SECRET'}),
        stop(0),
        finish('end_turn'),
        {'type': 'message_stop'},
      ]) {
        req.response.write('data: ${jsonEncode(event)}\n\n');
      }
      await req.response.close();
      return;
    }
    check(req.headers.value('anthropic-beta') == 'test-beta', 'beta');
    check(req.headers.value('x-review') == 'yes', 'request header');
    check(req.uri.queryParametersAll['extra']?.join(',') == 'a,b', 'query');
    req.response.headers.contentType = ContentType.json;
    req.response.headers.set('request-id', 'request-1');
    req.response.write(
      jsonEncode({
        'path': req.uri.path,
        'opaque': {'x': 1},
      }),
    );
    await req.response.close();
  });
  final borrowed = http.Client();
  final client = api.AnthropicNativeClient.withApiKey(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}',
    betas: ['test-beta'],
    httpClient: borrowed,
  );
  try {
    for (final count in [false, true]) {
      final response = count
          ? await client.countTokens(
              {'model': 'raw'},
              headers: {'x-review': 'yes'},
              query: {
                'extra': ['a', 'b'],
              },
            )
          : await client.createMessage(
              {'model': 'raw'},
              headers: {'x-review': 'yes'},
              query: {
                'extra': ['a', 'b'],
              },
            );
      check(
        response.data['path'] ==
                (count ? '/v1/messages/count_tokens' : '/v1/messages') &&
            (response.data['opaque'] as Map)['x'] == 1 &&
            response.headers['request-id'] == 'request-1',
        'raw endpoint',
      );
    }
    final token = CancellationToken();
    final pending = client.createMessage({
      'model': 'pending',
    }, cancellation: token);
    await preHeaders.future.timeout(const Duration(seconds: 5));
    token.cancel();
    try {
      await pending.timeout(const Duration(seconds: 5));
      throw StateError('pre-header cancellation failed');
    } on RunCancelled {
      print('PASS pending request cancellation');
    }
    final parent = CancellationToken();
    final stream = client
        .streamMessages({'model': 'body'}, cancellation: parent)
        .listen((_) {});
    await bodyStarted.future.timeout(const Duration(seconds: 5));
    final sibling = client.streamMessages({
      'model': 'sibling',
    }, cancellation: parent).toList();
    await siblingStarted.future.timeout(const Duration(seconds: 5));
    await stream.cancel().timeout(const Duration(seconds: 5));
    check(!parent.isCancelled, 'stream cancellation changed parent');
    release.complete();
    check(
      (await sibling.timeout(const Duration(seconds: 5))).isNotEmpty,
      'sibling cancelled',
    );
    try {
      await client.streamMessages({'model': 'malformed'}).toList();
      throw StateError('malformed accepted');
    } on api.JsonHttpException {
      print('PASS malformed stream rejected');
    }
    final raw = await client.streamMessages({'model': 'unknown'}).toList();
    check(
      raw.whereType<api.JsonSseData>().any(
        (e) => e.data.toString().contains('future_private'),
      ),
      'raw unknown missing',
    );
    try {
      await generateText(
        model: client.chatModel(model: 'unknown'),
        prompt: 'x',
      );
      throw StateError('unknown block accepted');
    } on AgentRunException {
      print('PASS unknown block rejected by model');
    }
    print(
      'PASS raw endpoints, query/headers, cancellation, malformed SSE, unknown block raw/fail closed',
    );
  } finally {
    if (!release.isCompleted) release.complete();
    client.close();
    final response = await borrowed.get(
      Uri.parse('http://127.0.0.1:${server.port}/alive'),
    );
    check(response.body == 'ok', 'borrowed client closed');
    borrowed.close();
    await server.close(force: true);
  }
}
