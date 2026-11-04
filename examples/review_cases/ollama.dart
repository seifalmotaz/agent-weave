// Offline consumer exercise: dart --enable-asserts run examples/review_cases/ollama.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:http/http.dart' as http;
import 'package:agent_weave_ollama/agent_weave_ollama.dart' as ollama;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  server.listen((request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    count++;
    assert(request.headers.value('authorization') == 'Bearer fixture');
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/api/embed') {
      assert(body['input'] is List && body['model'] == 'embedding');
      request.response.write(
        jsonEncode({
          'model': 'embedding',
          'embeddings': [
            [1.0, 2.0],
            [3.0, 4.0],
          ],
          'prompt_eval_count': 4,
        }),
      );
    } else {
      assert(request.uri.path == '/api/chat' && body['model'] == 'fixture');
      assert(body['options']['temperature'] == 0.2);
      final Map<String, Object?> message;
      if (count == 1) {
        assert(body['format'] is Map);
        message = {'role': 'assistant', 'content': '{"answer":42}'};
      } else if (count == 2) {
        assert(body['tools'][0]['function']['name'] == 'double');
        message = {
          'role': 'assistant',
          'content': '',
          'thinking': 'private-thinking',
          'future': {'opaque': true},
          'tool_calls': [
            {
              'id': 'native-call',
              'function': {
                'index': 0,
                'name': 'double',
                'arguments': {'answer': 21},
              },
            },
          ],
        };
      } else {
        final messages = body['messages'] as List;
        final assistant = messages.lastWhere((m) => m['tool_calls'] != null);
        assert(
          assistant['thinking'] == 'private-thinking' &&
              assistant['future']['opaque'] == true,
        );
        assert(
          assistant['tool_calls'][0]['id'] == 'native-call' &&
              assistant['tool_calls'][0]['function']['index'] == 0,
        );
        assert(
          messages.last['role'] == 'tool' && messages.last['content'] == '42',
        );
        message = {'role': 'assistant', 'content': '42'};
      }
      request.response.write(
        '${jsonEncode({'model': 'fixture', 'created_at': '2026-01-01T00:00:00Z', 'message': message, 'done': true, 'done_reason': 'stop', 'prompt_eval_count': 3, 'prompt_eval_cached_count': 1, 'eval_count': 2, 'total_duration': 100})}\n',
      );
    }
    await request.response.close();
  });
  final client = ollama.OllamaNativeClient(
    baseUrl: 'http://127.0.0.1:${server.port}',
    credentialResolver: () => 'fixture',
  );
  try {
    final model = client.chatModel(
      model: 'fixture',
      options: const ollama.ModelOptions(temperature: 0.2),
    );
    const schema = <String, Object?>{
      'type': 'object',
      'properties': {
        'answer': {'type': 'integer'},
      },
      'required': ['answer'],
    };
    final result = await generateObject<int>(
      model: model,
      schema: schema,
      decode: (v) => (v as Map<String, Object?>)['answer'] as int,
      prompt: 'Answer',
    );
    assert(result.value == 42);
    assert(
      result.generation.usage?.inputTokens == 3 &&
          result.generation.usage?.cachedInputTokens == 1,
    );
    assert(
      result
              .generation
              .responseMessages
              .last
              .providerData['ollama.chat.metadata']!
              .single['total_duration'] ==
          100,
    );
    var executions = 0;
    final agent = AiAgent<String>(
      model: model,
      tools: [
        Tool<int, int, String>(
          name: 'double',
          description: 'Double',
          inputSchema: schema,
          outputSchema: const {'type': 'integer'},
          needsApproval: true,
          decode: (v) => v['answer'] as int,
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
      ownerId: 'owner',
      context: 'app',
    );
    assert(paused.status == RunStatus.interrupted && executions == 0);
    final hydration = chatHydration(
      await agent.store.load(ownerId: 'owner', threadId: 't'),
    );
    assert(
      !jsonEncode(hydration).contains('private-thinking') &&
          !jsonEncode(hydration).contains('native-call'),
    );
    final resumed = await agent.generate(
      ChatRequest(
        threadId: 't',
        runId: 'r2',
        parentRunId: 'r1',
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: 'app',
    );
    assert(resumed.text == '42' && executions == 1);
    final embeddings = await ollama.OllamaEmbeddingModel(client).embed(
      const ollama.EmbedRequest(
        model: 'embedding',
        input: ollama.EmbedInput.list(['a', 'b']),
      ),
    );
    assert(
      embeddings.embeddings.length == 2 &&
          embeddings.embeddings.first[1] == 2.0 &&
          embeddings.inputTokens == 4,
    );
    var immutable = false;
    try {
      embeddings.embeddings.first[0] = 9;
    } on UnsupportedError {
      immutable = true;
    }
    assert(immutable);
    print(
      'PASS Ollama schema, typed options, approval, private thinking replay and immutable embeddings',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
  await rawTransportCases();
  await imageAndCancellation();
}

Future<void> rawTransportCases() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  server.listen((request) async {
    await request.drain<void>();
    requests++;
    if (requests == 1) {
      request.response.statusCode = 401;
      request.response.write('{"error":"private"}');
    } else if (requests == 2) {
      request.response.write('{bad json}\n');
    } else {
      request.response.write('{"model":"ok","done":true}\n');
    }
    await request.response.close();
  });
  final client = ollama.OllamaNativeClient(
    baseUrl: 'http://127.0.0.1:${server.port}',
  );
  try {
    var failed = false;
    try {
      await client.createChat({'model': 'fixture', 'messages': <Object>[]});
    } catch (_) {
      failed = true;
    }
    assert(failed);
    failed = false;
    try {
      await client.streamChat({
        'model': 'fixture',
        'messages': <Object>[],
      }).toList();
    } catch (_) {
      failed = true;
    }
    assert(failed);
    final valid = await client.streamChat({
      'model': 'fixture',
      'messages': <Object>[],
    }).toList();
    assert(valid.single.data['model'] == 'ok');
    print(
      'PASS HTTP and malformed NDJSON failures followed by successful stream',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}

Future<void> imageAndCancellation() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  final active = Completer<void>();
  server.listen((request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    count++;
    if (count == 1) {
      assert(body['messages'][0]['images'][0] == 'AQID');
      request.response.write(
        '{"model":"fixture","message":{"role":"assistant","content":"seen"},"done":true}\n',
      );
      await request.response.close();
    } else if (count == 2) {
      request.response.write(
        '{"message":{"role":"assistant","content":"partial"},"done":false}\n',
      );
      await request.response.flush();
      active.complete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      try {
        await request.response.close();
      } catch (_) {}
    } else {
      request.response.write('{"model":"fixture","done":true}\n');
      await request.response.close();
    }
  });
  final borrowed = http.Client();
  final client = ollama.OllamaNativeClient(
    baseUrl: 'http://127.0.0.1:${server.port}',
    httpClient: borrowed,
  );
  try {
    final cancelled = CancellationToken()..cancel();
    try {
      await client.streamChat({
        'model': 'fixture',
        'messages': <Object>[],
      }, cancellation: cancelled).toList();
    } catch (_) {}
    assert(count == 0);
    final agent = AiAgent<void>(model: client.chatModel(model: 'fixture'));
    final result = await agent.generate(
      ChatRequest(
        threadId: 'image',
        runId: 'image',
        messages: [
          ChatMessage(
            id: 'u',
            role: MessageRole.user,
            content: [
              const TextPart('see'),
              const ImagePart('data:image/png;base64,AQID'),
            ],
          ),
        ],
      ),
      ownerId: 'owner',
      context: null,
    );
    assert(result.text == 'seen');
    final stream = client.streamChat({
      'model': 'fixture',
      'messages': <Object>[],
    });
    final subscription = stream.listen((_) {});
    await active.future.timeout(const Duration(seconds: 3));
    await subscription.cancel();
    final sibling = await client.streamChat({
      'model': 'fixture',
      'messages': <Object>[],
    }).toList();
    assert(sibling.single.data['done'] == true);
    client.close();
    final response = await borrowed.post(
      Uri.parse('http://127.0.0.1:${server.port}/api/chat'),
      body: '{}',
    );
    assert(response.statusCode == 200);
    print(
      'PASS inline image, unsubscribe, sibling stream and borrowed HTTP ownership',
    );
  } finally {
    client.close();
    borrowed.close();
    await server.close(force: true);
  }
}
