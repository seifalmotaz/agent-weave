// Offline consumer review. Run with Dart 3.12.2 and --enable-asserts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:http/http.dart' as http;
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

const schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'value': {'type': 'integer'},
  },
  'required': ['value'],
  'additionalProperties': false,
};

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests = <Map<String, Object?>>[];
  final headers = <HttpHeaders>[];
  server.listen((req) async {
    final body =
        jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, Object?>;
    requests.add(body);
    headers.add(req.headers);
    final n = requests.length;
    if (n == 1) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'id': 'gen',
          'provider': 'actual',
          'usage': {'cost': 0.25},
          'opaque': {'x': 1},
        }),
      );
      await req.response.close();
    } else if (n == 2) {
      await sse(req.response, [
        chatDelta({'content': '{"value":42}'}),
        chatDelta({}, 'stop'),
      ]);
    } else if (n == 3) {
      await sse(req.response, [
        chatDelta({
          'reasoning_details': [
            {'type': 'reasoning.encrypted', 'data': 'SECRET-STATE', 'index': 0},
            {
              'type': 'future.unknown',
              'opaque': {'x': 2},
              'index': 1,
            },
          ],
          'tool_calls': [
            {
              'index': 0,
              'id': 'call-1',
              'type': 'function',
              'function': {'name': 'double', 'arguments': '{"value":21}'},
            },
          ],
        }),
        chatDelta({}, 'tool_calls'),
      ]);
    } else if (n == 5) {
      await sse(req.response, [
        chatDelta({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call-2',
              'type': 'function',
              'function': {'name': 'double', 'arguments': '{"value":3}'},
            },
          ],
        }),
        chatDelta({}, 'tool_calls'),
      ]);
    } else if (n == 7) {
      await sse(req.response, [
        {
          'type': 'response.output_text.delta',
          'sequence_number': 0,
          'item_id': 'i',
          'output_index': 0,
          'content_index': 0,
          'delta': '{"value":7}',
        },
        {
          'type': 'response.completed',
          'sequence_number': 1,
          'response': {
            'id': 'r',
            'object': 'response',
            'created_at': 0,
            'status': 'completed',
            'model': 'actual/model',
            'provider': 'actual-provider',
            'output': <Object?>[],
            'usage': {
              'input_tokens': 3,
              'output_tokens': 2,
              'total_tokens': 5,
              'cost': 0.12,
            },
          },
        },
      ]);
    } else if (n == 9) {
      req.response.statusCode = 400;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'error': {'message': 'bad key-9'},
        }),
      );
      await req.response.close();
    } else {
      await sse(req.response, [
        chatDelta({'content': n == 4 ? '42' : 'again'}),
        chatDelta({}, 'stop'),
        if (n == 4)
          {
            'id': 'fixture',
            'object': 'chat.completion.chunk',
            'created': 0,
            'model': 'actual/model',
            'provider': 'actual-provider',
            'choices': [],
            'usage': {
              'prompt_tokens': 3,
              'completion_tokens': 2,
              'total_tokens': 5,
              'cost': 0.12,
            },
          },
      ]);
    }
  });
  var key = 0;
  final client = router.OpenRouterClient(
    credentialResolver: () => 'key-${++key}',
    baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
    siteUrl: 'https://example.test',
    appName: 'Review',
    sessionId: 'session',
  );
  try {
    final raw = await client.createChat({'model': 'fixture', 'messages': []});
    check(
      raw.data['provider'] == 'actual' &&
          (raw.data['usage'] as Map)['cost'] == 0.25,
      'raw metadata lost',
    );
    final model = router.OpenRouterChatModel(
      client: client,
      model: 'requested/model',
    );
    final answer = await generateObject<int>(
      model: model,
      prompt: 'answer',
      schema: schema,
      decode: (json) => (json as Map)['value'] as int,
    );
    check(answer.value == 42, 'schema generation');
    check(
      (requests[1]['response_format'] as Map)['json_schema'] != null,
      'schema missing from request',
    );
    var executions = 0;
    final store = MemoryRunStore();
    Tool<int, int, void> tool() => Tool(
      name: 'double',
      description: 'Double',
      inputSchema: schema,
      outputSchema: const {'type': 'integer'},
      needsApproval: true,
      decode: (j) => j['value'] as int,
      encode: (x) => x,
      execute: (x, _) {
        executions++;
        return x * 2;
      },
    );
    AiAgent<void> agent() =>
        AiAgent(model: model, store: store, tools: [tool()]);
    final paused = await agent().generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'one',
        messages: [ChatMessage.user('double', id: 'u1')],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      paused.status == RunStatus.interrupted && executions == 0,
      'approval did not pause',
    );
    final resumed = await agent().generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'two',
        parentRunId: paused.runId,
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(resumed.text == '42' && executions == 1, 'approval resume');
    check(
      resumed.usage?.inputTokens == 3 &&
          resumed.usage?.outputTokens == 2 &&
          resumed.usage?.model == 'actual/model',
      'reported usage or model lost',
    );
    final privateMetadata = jsonEncode(
      resumed.responseMessages.map((m) => m.providerData).toList(),
    );
    check(
      privateMetadata.contains('actual-provider') &&
          privateMetadata.contains('0.12'),
      'reported provider or cost lost',
    );
    final replay = (requests[3]['messages'] as List).firstWhere(
      (m) => m['role'] == 'assistant',
    )['reasoning_details'];
    check(
      jsonEncode(replay) ==
          jsonEncode([
            {'type': 'reasoning.encrypted', 'data': 'SECRET-STATE', 'index': 0},
            {
              'type': 'future.unknown',
              'opaque': {'x': 2},
              'index': 1,
            },
          ]),
      'opaque reasoning replay order',
    );
    final hydration = chatHydration(
      await store.load(ownerId: 'owner', threadId: 'thread'),
    );
    check(
      !jsonEncode(hydration).contains('SECRET-STATE'),
      'private reasoning leaked to hydration',
    );
    final next = await agent().generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'three',
        messages: [ChatMessage.user('again', id: 'u2')],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      next.status == RunStatus.interrupted && executions == 1,
      'second turn approval',
    );
    final nextResumed = await agent().generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'four',
        parentRunId: next.runId,
        resume: [next.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(nextResumed.text == 'again' && executions == 2, 'second turn tool');
    check(nextResumed.usage == null, 'usage was inferred when absent');
    final responses = router.OpenRouterResponsesModel(
      client: client,
      model: 'requested/model',
    );
    final structured = await generateObject<int>(
      model: responses,
      prompt: 'answer',
      schema: schema,
      decode: (json) => (json as Map)['value'] as int,
    );
    check(structured.value == 7, 'Responses schema generation');
    check(
      (requests[6]['text'] as Map)['format']['type'] == 'json_schema',
      'Responses schema missing',
    );
    final wrongProvider = ChatMessage(
      id: 'a',
      role: MessageRole.assistant,
      content: [const TextPart('earlier')],
      providerData: {
        'other.provider': [
          {'data': 'WRONG-PRIVATE'},
        ],
      },
    );
    await model
        .stream(
          ModelRequest(
            messages: [
              wrongProvider,
              ChatMessage.user('next', id: 'u'),
            ],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    check(
      !jsonEncode(requests[7]).contains('WRONG-PRIVATE'),
      'wrong provider state replayed',
    );
    try {
      await client.createChat({'model': 'fixture', 'messages': []});
      throw StateError('expected error');
    } on router.JsonHttpException catch (e) {
      check(
        e.statusCode == 400 &&
            !e.toString().contains('key-9') &&
            !jsonEncode(e.details).contains('key-9'),
        'unsafe error',
      );
    }
    check(
      headers[0].value('authorization') == 'Bearer key-1' &&
          headers[1].value('authorization') == 'Bearer key-2',
      'credential rotation',
    );
    check(
      headers.every(
        (h) =>
            h.value('http-referer') == 'https://example.test' &&
            h.value('x-title') == 'Review' &&
            h.value('x-session-id') == 'session',
      ),
      'attribution',
    );
    print(
      'PASS raw metadata, both schemas, approval, replay, hydration, next turn, credentials, error',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
  await cancellationAndOwnership();
  await responsesApproval();
}

Future<void> sse(
  HttpResponse response,
  List<Map<String, Object?>> events,
) async {
  response.bufferOutput = false;
  response.headers.contentType = ContentType('text', 'event-stream');
  for (final event in events) {
    response.write('data: ${jsonEncode(event)}\n\n');
  }
  response.write('data: [DONE]\n\n');
  await response.close();
}

Map<String, Object?> chatDelta(Map<String, Object?> delta, [String? finish]) =>
    {
      'id': 'fixture',
      'object': 'chat.completion.chunk',
      'created': 0,
      'model': 'actual/model',
      'provider': 'actual-provider',
      'choices': [
        {'index': 0, 'delta': delta, 'finish_reason': finish},
      ],
    };

Future<void> cancellationAndOwnership() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final beforeHeaders = Completer<void>();
  final afterHeaders = Completer<void>();
  final releaseSibling = Completer<void>();
  var streamCount = 0;
  server.listen((req) async {
    final raw = await utf8.decoder.bind(req).join();
    final path = req.uri.path;
    if (path.endsWith('/chat/completions') && raw.contains('pending')) {
      beforeHeaders.complete();
      return;
    }
    if (path.endsWith('/chat/completions')) {
      final index = ++streamCount;
      req.response.bufferOutput = false;
      req.response.headers.contentType = ContentType('text', 'event-stream');
      req.response.write(
        'data: ${jsonEncode(chatDelta({'content': 'started'}))}\n\n',
      );
      await req.response.flush();
      if (index == 1) {
        afterHeaders.complete();
      } else {
        await releaseSibling.future;
        req.response.write(
          'data: ${jsonEncode(chatDelta({}, 'stop'))}\n\ndata: [DONE]\n\n',
        );
        await req.response.close();
      }
      return;
    }
    req.response.write('ok');
    await req.response.close();
  });
  final borrowed = http.Client();
  final client = router.OpenRouterClient.withApiKey(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}',
    httpClient: borrowed,
  );
  final token = CancellationToken()..cancel();
  try {
    await client.createChat({'model': 'x'}, cancellation: token);
    throw StateError('pre-cancel failed');
  } on RunCancelled {
    print('PASS cancellation');
  }
  final pendingToken = CancellationToken();
  final pending = client.createChat({
    'model': 'pending',
  }, cancellation: pendingToken);
  await beforeHeaders.future.timeout(const Duration(seconds: 5));
  pendingToken.cancel();
  try {
    await pending.timeout(const Duration(seconds: 5));
    throw StateError('pending cancellation failed');
  } on RunCancelled {
    print('PASS cancellation');
  }
  final live = CancellationToken();
  final sub = client
      .streamChat({'model': 'x'}, cancellation: live)
      .listen((_) {});
  await afterHeaders.future.timeout(const Duration(seconds: 5));
  final sibling = client.streamChat({
    'model': 'sibling',
  }, cancellation: live).toList();
  await sub.cancel().timeout(const Duration(seconds: 5));
  releaseSibling.complete();
  final siblingEvents = await sibling.timeout(const Duration(seconds: 5));
  check(siblingEvents.isNotEmpty, 'sibling failed after cancellation');
  check(!live.isCancelled, 'stream cancellation altered parent');
  client.close();
  final response = await borrowed.get(
    Uri.parse('http://127.0.0.1:${server.port}/alive'),
  );
  check(response.body == 'ok', 'borrowed client closed');
  borrowed.close();
  await server.close(force: true);
  print(
    'PASS pre- and pending-header cancellation, sibling isolation and borrowed ownership',
  );
}

Future<void> responsesApproval() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, Object?>>[];
  final reasoning = <String, Object?>{
    'id': 'reasoning-id',
    'type': 'reasoning',
    'status': 'completed',
    'summary': <Object?>[],
    'encrypted_content': 'PRIVATE-OPAQUE',
    'signature': 'SIGNED',
    'unknown': {
      'nested': [1, 2],
    },
  };
  final message = <String, Object?>{
    'id': 'assistant-id',
    'type': 'message',
    'role': 'assistant',
    'status': 'completed',
    'content': [
      {'type': 'output_text', 'text': 'Checking', 'annotations': <Object?>[]},
    ],
  };
  final call = <String, Object?>{
    'type': 'function_call',
    'id': 'item-id',
    'call_id': 'call-id',
    'name': 'double',
    'arguments': '{"value":21}',
    'status': 'completed',
  };
  server.listen((req) async {
    bodies.add(
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, Object?>,
    );
    final first = bodies.length == 1;
    await sse(req.response, [
      if (first)
        {
          'type': 'response.output_item.done',
          'sequence_number': 0,
          'output_index': 2,
          'item': call,
        }
      else
        {
          'type': 'response.output_text.delta',
          'sequence_number': 0,
          'item_id': 'final-id',
          'output_index': 0,
          'content_index': 0,
          'delta': '42',
        },
      {
        'type': 'response.completed',
        'sequence_number': 1,
        'response': {
          'id': first ? 'response-one' : 'response-two',
          'object': 'response',
          'created_at': 0,
          'status': 'completed',
          'model': 'actual/model',
          'output': first ? [reasoning, message, call] : <Object?>[],
        },
      },
    ]);
  });
  final client = router.OpenRouterClient.withApiKey(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
  );
  try {
    final model = router.OpenRouterResponsesModel(
      client: client,
      model: 'requested/model',
    );
    final store = MemoryRunStore();
    var executed = 0;
    Tool<int, int, void> tool() => Tool(
      name: 'double',
      description: 'Double',
      inputSchema: schema,
      outputSchema: const {'type': 'integer'},
      needsApproval: true,
      decode: (j) => j['value'] as int,
      encode: (x) => x,
      execute: (x, _) {
        executed++;
        return x * 2;
      },
    );
    AiAgent<void> agent() =>
        AiAgent(model: model, store: store, tools: [tool()]);
    final paused = await agent().generate(
      ChatRequest(
        threadId: 'responses',
        runId: 'one',
        messages: [ChatMessage.user('double', id: 'user')],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      paused.status == RunStatus.interrupted && executed == 0,
      'Responses approval pause',
    );
    final hydration = chatHydration(
      await store.load(ownerId: 'owner', threadId: 'responses'),
    );
    check(
      !jsonEncode(hydration).contains('PRIVATE-OPAQUE'),
      'Responses reasoning leaked',
    );
    final result = await agent().generate(
      ChatRequest(
        threadId: 'responses',
        runId: 'two',
        parentRunId: paused.runId,
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      result.text == '42' && executed == 1 && bodies.length == 2,
      'Responses tool resume',
    );
    final input = bodies.last['input'] as List;
    check(
      jsonEncode(input.sublist(1, 4)) == jsonEncode([reasoning, message, call]),
      'Responses exact output replay',
    );
    check(
      input[4]['type'] == 'function_call_output' &&
          input[4]['call_id'] == 'call-id' &&
          input[4]['output'] == '42',
      'Responses tool result replay',
    );
    print(
      'PASS Responses persisted approval, ordered opaque reasoning and output replay',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}
