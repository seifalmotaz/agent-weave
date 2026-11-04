import 'dart:convert';
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
  'usage': {'output_tokens': 2},
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
  server.listen((req) async {
    final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
    check(req.uri.path == '/v1/messages', 'wrong path');
    check(req.headers.value('x-api-key') == 'fixture', 'missing key');
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
        messages[1]['content'][0]['signature'] == 'signed',
        'thinking signature not replayed',
      );
      check(messages[1]['content'][1]['type'] == 'tool_use', 'tool missing');
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
            'message': 'fixture bad request',
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
            block(0, {'type': 'thinking', 'thinking': '', 'signature': ''}),
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
  final client = api.AnthropicClient.withApiKey(
    'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}',
  );
  final model = api.AnthropicChatModel(client: client, model: 'fixture');
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
    final agent = AiAgent<void>(
      model: model,
      tools: [
        Tool<int, int, void>(
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
    final result = await agent.generate(
      ChatRequest(
        threadId: 't',
        runId: 'r',
        messages: [ChatMessage.user('double', id: 'u')],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(count == 1 && result.text == '42', 'tool loop');
    print(
      'PASS text, structured output, two-invocation tool and signed thinking replay over loopback HTTP',
    );
    try {
      await generateText(model: model, prompt: 'bad');
      throw StateError('expected API failure');
    } on AgentRunException catch (e) {
      check(e.code == 'MODEL_FAILED', 'error code');
      print('PASS HTTP 400 => ${e.code}, cause=${e.cause}');
    }
    check(calls == 5, 'request count');
  } finally {
    client.close();
    await server.close(force: true);
  }
}
