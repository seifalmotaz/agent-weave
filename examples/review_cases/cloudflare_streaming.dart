// Offline consumer review: dart run examples/review_cases/cloudflare_streaming.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_cloudflare/agent_weave_cloudflare.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

const schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'value': {'type': 'integer'},
  },
  'required': ['value'],
};

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, dynamic>>[];
  final release = Completer<void>();
  server.listen((req) async {
    final body =
        jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    bodies.add(body);
    final prompt = jsonEncode(body['messages']);
    if (body['stream'] == true) {
      req.response.bufferOutput = false;
      req.response.headers.contentType = ContentType('text', 'event-stream');
      if (prompt.contains('malformed')) {
        req.response.write('data: {"response":42}\n\n');
        await req.response.close();
        return;
      }
      if (prompt.contains('eof')) {
        req.response.write('data: {"response":"partial"}\n\n');
        await req.response.close();
        return;
      }
      req.response.write('data: {"response":"first"}\n\n');
      await req.response.flush();
      if (prompt.contains('slow')) await release.future;
      req.response.write('data: {"response":" second"}\n\ndata: [DONE]\n\n');
    } else {
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'success': true,
          'result': body.containsKey('response_format')
              ? {
                  'response': {'value': 42},
                }
              : {'response': 'buffered'},
        }),
      );
    }
    await req.response.close();
  });
  final client = CloudflareClient.withApiToken(
    accountId: 'account',
    apiToken: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}',
  );
  try {
    final options = <String, Object?>{'temperature': 0.4};
    final model = CloudflareChatModel(
      client: client,
      model: '@hf/nousresearch/hermes-2-pro-mistral-7b',
      options: options,
    );
    options['temperature'] = 0.9;
    final request = ModelRequest(messages: [ChatMessage.user('slow', id: 'u')]);
    final iterator = StreamIterator(
      model.stream(request, cancellation: CancellationToken()),
    );
    check(
      await iterator.moveNext().timeout(const Duration(seconds: 3)),
      'no incremental event',
    );
    check(
      iterator.current is TextDelta &&
          (iterator.current as TextDelta).text == 'first',
      'first chunk missing',
    );
    check(!release.isCompleted, 'first chunk buffered');
    final sibling = await model
        .stream(
          ModelRequest(messages: [ChatMessage.user('sibling', id: 's')]),
          cancellation: CancellationToken(),
        )
        .toList()
        .timeout(const Duration(seconds: 3));
    check(
      sibling.whereType<TextDelta>().map((e) => e.text).join() ==
          'first second',
      'sibling stream',
    );
    await iterator.cancel().timeout(const Duration(seconds: 3));
    release.complete();
    check(bodies.first['temperature'] == 0.4, 'options were not snapshotted');
    final result = await generateObject<int>(
      model: model,
      prompt: 'number',
      schema: schema,
      decode: (json) => (json as Map)['value'] as int,
    );
    check(
      result.value == 42 && bodies.last['stream'] != true,
      'schema must use buffered result',
    );
    final toolEvents = await model
        .stream(
          ModelRequest(
            messages: [ChatMessage.user('tool', id: 't')],
            tools: [
              ModelTool(
                name: 'double',
                description: 'Double',
                inputSchema: schema,
              ),
            ],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    check(
      toolEvents.whereType<TextDelta>().single.text == 'buffered' &&
          bodies.last['stream'] != true &&
          bodies.last['tools'] != null,
      'tool fallback',
    );
    for (final name in ['malformed', 'eof']) {
      var rejected = false;
      try {
        await model
            .stream(
              ModelRequest(messages: [ChatMessage.user(name, id: name)]),
              cancellation: CancellationToken(),
            )
            .toList();
      } catch (_) {
        rejected = true;
      }
      check(rejected, '$name stream accepted');
    }
    final buffered = CloudflareChatModel(
      client: client,
      model: '@hf/nousresearch/hermes-2-pro-mistral-7b',
      streamText: false,
    );
    final events = await buffered
        .stream(
          ModelRequest(messages: [ChatMessage.user('hello', id: 'b')]),
          cancellation: CancellationToken(),
        )
        .toList();
    check(
      events.whereType<TextDelta>().single.text == 'buffered' &&
          bodies.last['stream'] != true,
      'stream opt out',
    );
    var rejected = false;
    try {
      CloudflareChatModel(
        client: client,
        model: '@hf/nousresearch/hermes-2-pro-mistral-7b',
        options: {'stream': false},
      );
    } on ArgumentError {
      rejected = true;
    }
    check(rejected, 'request-owned stream option accepted');
    print(
      'PASS incremental text, sibling, cancellation, options, schema/tool fallback, malformed/EOF and opt out',
    );
  } finally {
    if (!release.isCompleted) release.complete();
    client.close();
    await server.close(force: true);
  }
}
