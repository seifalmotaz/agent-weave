// Offline consumer exercise: dart --enable-asserts run examples/review_cases/cloudflare.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_cloudflare/agent_weave_cloudflare.dart';

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  var executions = 0;
  server.listen((request) async {
    count++;
    final n = count;
    assert(request.headers.value('authorization') == 'Bearer token-$n');
    final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
    final body = bytes.isEmpty || n == 4
        ? null
        : jsonDecode(utf8.decode(bytes));
    request.response.headers.set('cf-aig-request-id', 'req-$n');
    request.response.headers.set('cf-aig-cache-status', 'HIT');
    if (n == 1) {
      assert(request.uri.path.endsWith('/ai/run/@cf/baai/bge-base-en-v1.5'));
      assert(
        body['text'][0] == 'hello' &&
            body['pooling'] == 'cls' &&
            body['future'] == 7,
      );
      request.response.write(
        '{"success":true,"result":{"data":[[1,2]],"shape":[1,2],"pooling":"cls"}}',
      );
    } else if (n == 2) {
      assert(request.uri.path.endsWith('/ai/run'));
      assert(
        body['model'] == '@cf/test' &&
            body['input']['prompt'] == 'hello' &&
            body['options']['stream'] == false,
      );
      assert(request.headers.value('cf-aig-gateway-id') == 'gateway');
      assert(request.headers.value('cf-aig-skip-cache') == 'true');
      assert(
        jsonDecode(request.headers.value('cf-aig-metadata')!)['tenant'] ==
            'test',
      );
      request.response.write('{"success":true,"result":{"response":"ok"}}');
    } else if (n == 3) {
      assert(
        request.method == 'GET' &&
            request.uri.queryParameters['model'] == '@cf/a b',
      );
      request.response.write('{"success":true,"result":{"input":{}}}');
    } else if (n == 4) {
      assert(
        request.headers.contentType!.mimeType == 'audio/wav' &&
            bytes.join(',') == '1,2,3',
      );
      request.response.write(
        '{"success":true,"result":{"text":"hi","vtt":"WEBVTT"}}',
      );
    } else if (n == 5) {
      assert(body['audio'][0] == 4);
      request.response.write('{"success":true,"result":{"text":"json"}}');
    } else if (n == 6) {
      assert(body['prompt'] == 'cat');
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add([137, 80, 78, 71]);
    } else if (n == 7) {
      request.response.write(
        '{"success":true,"result":{"image":"AQID","other":1}}',
      );
    } else if (n == 8) {
      assert(body['tools'][0]['name'] == 'double');
      request.response.write(
        '{"success":true,"result":{"tool_calls":[{"name":"double","arguments":{"value":21}}]}}',
      );
    } else if (n == 9) {
      final messages = body['messages'] as List;
      assert(
        jsonDecode(
              messages[messages.length - 2]['content'] as String,
            )['name'] ==
            'double',
      );
      assert(
        messages.last['role'] == 'tool' && messages.last['content'] == '42',
      );
      request.response.write('{"success":true,"result":{"response":"42"}}');
    } else if (n == 10) {
      request.response.write(
        '{"success":true,"result":{"tool_calls":[{"name":"double","arguments":{"value":1}},{"name":"double","arguments":{"value":2}}]}}',
      );
    } else if (n == 11) {
      request.response.statusCode = 429;
      request.response.write(
        '{"errors":[{"message":"token-11 private-detail"}]}',
      );
    }
    await request.response.close();
  });
  var token = 0;
  final client = CloudflareClient(
    accountId: 'account',
    tokenResolver: () => 'token-${++token}',
    baseUrl: 'http://127.0.0.1:${server.port}/client/v4',
  );
  try {
    final embedding = await CloudflareEmbeddingModel(client: client).embed(
      CloudflareEmbeddingRequest(
        text: ['hello'],
        pooling: CloudflarePooling.cls,
        extra: {'future': 7},
      ),
    );
    assert(embedding.result['shape'].toString() == '[1, 2]');
    var immutable = false;
    try {
      embedding.vectors.first[0] = 9;
    } on UnsupportedError {
      immutable = true;
    }
    assert(immutable);
    final gateway = await CloudflareGatewayClient(client: client).runJson(
      '@cf/test',
      {'prompt': 'hello'},
      options: {'stream': false},
      gateway: CloudflareGatewayOptions(
        gatewayId: 'gateway',
        skipCache: true,
        metadata: {'tenant': 'test'},
      ),
    );
    assert(gateway.cacheStatus == 'HIT' && gateway.requestId == 'req-2');
    await client.getModelSchema('@cf/a b');
    final audio = await CloudflareTranscriptionModel(client: client).transcribe(
      CloudflareAudioInput.bytes([1, 2, 3], contentType: 'audio/wav'),
    );
    assert(audio.vtt == 'WEBVTT');
    await CloudflareTranscriptionModel(client: client).transcribe(
      CloudflareAudioInput.json({
        'audio': [4],
      }),
    );
    final image = await CloudflareImageModel(
      client: client,
    ).generate({'prompt': 'cat'});
    assert(
      image.response.json == null &&
          image.contentType == 'image/png' &&
          image.imageBytes.join(',') == '137,80,78,71',
    );
    immutable = false;
    try {
      image.imageBytes[0] = 0;
    } on UnsupportedError {
      immutable = true;
    }
    assert(immutable);
    final imageJson = await CloudflareImageModel(
      client: client,
    ).generate({'prompt': 'cat'});
    assert(
      imageJson.imageBytes.join(',') == '1,2,3' &&
          imageJson.contentType == 'image/jpeg' &&
          (imageJson.response.json!['result'] as Map)['other'] == 1,
    );
    final model = CloudflareChatModel(
      client: client,
      model: '@hf/nousresearch/hermes-2-pro-mistral-7b',
    );
    final agent = AiAgent<String>(
      model: model,
      tools: [
        Tool<int, int, String>(
          name: 'double',
          description: 'Double',
          inputSchema: const {
            'type': 'object',
            'properties': {
              'value': {'type': 'integer'},
            },
          },
          outputSchema: const {'type': 'integer'},
          needsApproval: true,
          decode: (json) => json['value'] as int,
          encode: (n) => n,
          execute: (n, context) {
            executions++;
            return n * 2;
          },
        ),
      ],
    );
    final paused = await agent.generate(
      ChatRequest(
        threadId: 't',
        runId: 'r1',
        messages: [ChatMessage.user('Double 21', id: 'u')],
      ),
      ownerId: 'o',
      context: 'app',
    );
    assert(paused.status == RunStatus.interrupted && executions == 0);
    final resumed = await agent.generate(
      ChatRequest(
        threadId: 't',
        runId: 'r2',
        parentRunId: paused.runId,
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'o',
      context: 'app',
    );
    assert(resumed.text == '42' && executions == 1);
    var rejected = false;
    try {
      await agent.generate(
        ChatRequest(
          threadId: 'other',
          runId: 'r3',
          messages: [ChatMessage.user('two', id: 'u2')],
        ),
        ownerId: 'o',
        context: 'app',
      );
    } catch (_) {
      rejected = true;
    }
    assert(rejected && executions == 1);
    try {
      await client.runJson('@cf/test', {});
      throw StateError('Expected provider error');
    } on CloudflareException catch (error) {
      assert(error.statusCode == 429 && error.requestId == 'req-11');
      assert(
        !error.toString().contains('private-detail') &&
            !error.details.toString().contains('token-11'),
      );
    }
    assert(count == 11 && token == 11);
    print(
      'PASS native, gateway, schema, media, approval, multi-call rejection, rotation and privacy',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
  final pending = Completer<String>();
  final cancelled = CancellationToken();
  final late = CloudflareClient(
    accountId: 'account',
    tokenResolver: () => pending.future,
    baseUrl: 'http://127.0.0.1:1',
  );
  final future = late.runJson('@cf/test', {}, cancellation: cancelled);
  cancelled.cancel();
  try {
    await future;
    throw StateError('Expected cancellation');
  } on RunCancelled {
    assert(cancelled.isCancelled);
  }
  pending.complete('secret');
  late.close();
  print('PASS cancellation while resolving credentials');
  final slow = Completer<String>();
  final timed = CloudflareClient(
    accountId: 'account',
    tokenResolver: () => slow.future,
    baseUrl: 'http://127.0.0.1:1',
    requestTimeout: const Duration(milliseconds: 20),
  );
  try {
    await timed.runJson('@cf/test', {});
    throw StateError('Expected deadline');
  } on CloudflareException catch (error) {
    assert(error.toString().contains('Request failed'));
  } finally {
    slow.complete('secret');
    timed.close();
  }
  print('PASS deadline during credential resolution');
  await compatible();
  await responses();
  await cancelAfterSend();
  await gatewayDefaultsAndStream();
}

Future<void> compatible() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  server.listen((request) async {
    count++;
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    assert(request.uri.path.endsWith('/ai/v1/chat/completions'));
    assert(request.headers.value('cf-aig-gateway-id') == 'gateway');
    if (count == 2) {
      final messages = body['messages'] as List;
      assert(messages.any((m) => m['role'] == 'tool' && m['content'] == '42'));
      assert(
        messages.any(
          (m) => m['role'] == 'assistant' && m['tool_calls'] != null,
        ),
      );
    }
    final delta = count == 1
        ? {
            'tool_calls': [
              {
                'index': 0,
                'id': 'call1',
                'type': 'function',
                'function': {'name': 'double', 'arguments': '{"value":21}'},
              },
            ],
          }
        : {'content': '42'};
    request.response.headers.contentType = ContentType('text', 'event-stream');
    request.response.write(
      'data: ${jsonEncode({
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': count == 1 ? 'tool_calls' : 'stop'},
        ],
      })}\n\ndata: [DONE]\n\n',
    );
    await request.response.close();
  });
  final native = CloudflareClient.withApiToken(
    accountId: 'account',
    apiToken: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}/client/v4',
  );
  try {
    final model = CloudflareCompatibleChatModel(
      client: CloudflareCompatibleClient(
        client: native,
        gateway: CloudflareGatewayOptions(gatewayId: 'gateway'),
      ),
      model: 'fixture',
    );
    final agent = AiAgent<String>(
      model: model,
      tools: [
        Tool<int, int, String>(
          name: 'double',
          description: 'Double',
          inputSchema: const {
            'type': 'object',
            'properties': {
              'value': {'type': 'integer'},
            },
          },
          outputSchema: const {'type': 'integer'},
          decode: (json) => json['value'] as int,
          encode: (n) => n,
          execute: (n, context) => n * 2,
        ),
      ],
    );
    final result = await agent.generate(
      ChatRequest(
        threadId: 'compatible',
        runId: 'r',
        messages: [ChatMessage.user('Double 21', id: 'u')],
      ),
      ownerId: 'o',
      context: 'app',
    );
    assert(result.text == '42' && count == 2);
    print('PASS compatible chat tool continuation');
  } finally {
    native.close();
    await server.close(force: true);
  }
}

Future<void> responses() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  server.listen((request) async {
    count++;
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    assert(request.uri.path.endsWith('/ai/v1/responses'));
    assert(request.headers.value('authorization') == 'Bearer fixture');
    assert(!jsonEncode(body).contains('reasoning.encrypted_content'));
    if (count == 2) {
      final input = jsonEncode(body['input']);
      assert(input.contains('function_call_output') && input.contains('42'));
      assert(input.contains('call1') && input.contains('double'));
    }
    request.response.headers.contentType = ContentType('text', 'event-stream');
    void event(Map<String, Object?> value) =>
        request.response.write('data: ${jsonEncode(value)}\n\n');
    if (count == 1) {
      event({
        'type': 'response.output_item.done',
        'sequence_number': 0,
        'output_index': 0,
        'item': {
          'type': 'function_call',
          'id': 'item1',
          'call_id': 'call1',
          'name': 'double',
          'arguments': '{"value":21}',
          'status': 'completed',
        },
      });
    } else {
      event({
        'type': 'response.output_text.delta',
        'sequence_number': 0,
        'item_id': 'item2',
        'output_index': 0,
        'content_index': 0,
        'delta': '42',
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
    await request.response.close();
  });
  final native = CloudflareClient.withApiToken(
    accountId: 'account',
    apiToken: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}/client/v4',
  );
  try {
    final model = CloudflareCompatibleResponsesModel(
      client: CloudflareCompatibleClient(client: native),
      model: 'fixture',
    );
    final agent = AiAgent<String>(
      model: model,
      tools: [
        Tool<int, int, String>(
          name: 'double',
          description: 'Double',
          inputSchema: const {
            'type': 'object',
            'properties': {
              'value': {'type': 'integer'},
            },
          },
          outputSchema: const {'type': 'integer'},
          decode: (json) => json['value'] as int,
          encode: (n) => n,
          execute: (n, context) => n * 2,
        ),
      ],
    );
    final result = await agent.generate(
      ChatRequest(
        threadId: 'responses',
        runId: 'r',
        messages: [ChatMessage.user('Double 21', id: 'u')],
      ),
      ownerId: 'o',
      context: 'app',
    );
    assert(result.text == '42' && count == 2);
    print('PASS compatible Responses tool continuation');
  } finally {
    native.close();
    await server.close(force: true);
  }
}

Future<void> cancelAfterSend() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final received = Completer<void>();
  server.listen((request) async {
    await request.drain<void>();
    received.complete();
    // Deliberately leave response headers pending until cancellation.
  });
  final client = CloudflareClient.withApiToken(
    accountId: 'account',
    apiToken: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}/client/v4',
  );
  final token = CancellationToken();
  try {
    final result = client.runJson('@cf/test', {}, cancellation: token);
    await received.future.timeout(const Duration(seconds: 2));
    token.cancel();
    try {
      await result.timeout(const Duration(seconds: 2));
      throw StateError('Expected cancellation');
    } on RunCancelled {
      assert(token.isCancelled);
    }
    print('PASS cancellation after send while headers are pending');
  } finally {
    client.close();
    await server.close(force: true);
  }
}

Future<void> gatewayDefaultsAndStream() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  server.listen((request) async {
    await request.drain<void>();
    count++;
    assert(
      request.headers.value('cf-aig-gateway-id') ==
          (count == 3 || count == 5 ? 'override' : 'default'),
    );
    assert(request.headers.value('cf-aig-skip-cache') == 'true');
    if (count == 6) {
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write('data: {"response":"first"}\n\n');
      await request.response.flush();
      return;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      count == 1
          ? '{"success":true,"result":{"data":[[1]],"shape":[1,1]}}'
          : '{"success":true,"result":{}}',
    );
    await request.response.close();
  });
  final client = CloudflareClient.withApiToken(
    accountId: 'account',
    apiToken: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}/client/v4',
    gateway: CloudflareGatewayOptions(gatewayId: 'default', skipCache: true),
  );
  try {
    await CloudflareEmbeddingModel(
      client: client,
    ).embed(CloudflareEmbeddingRequest(text: ['one']));
    await CloudflareGatewayClient(client: client).runJson('@cf/test', {});
    await CloudflareGatewayClient(client: client).runJson(
      '@cf/test',
      {},
      gateway: CloudflareGatewayOptions(gatewayId: 'override'),
    );
    await CloudflareCompatibleClient(client: client).createChat({});
    await CloudflareCompatibleClient(
      client: client,
      gateway: CloudflareGatewayOptions(gatewayId: 'override'),
    ).createChat({});
    final token = CancellationToken();
    final iterator = StreamIterator(
      client.stream('@cf/test', {}, cancellation: token),
    );
    assert(await iterator.moveNext().timeout(const Duration(seconds: 2)));
    final next = iterator.moveNext();
    token.cancel();
    try {
      await next.timeout(const Duration(seconds: 2));
      throw StateError('Expected stream cancellation');
    } on RunCancelled {
      assert(token.isCancelled);
    }
    await iterator.cancel();
    assert(count == 6);
    print(
      'PASS gateway defaults and overrides, streaming cancellation after headers',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}
