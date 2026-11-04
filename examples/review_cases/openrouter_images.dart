// Offline consumer review: dart run examples/review_cases/openrouter_images.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;

const png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';
void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, dynamic>>[];
  server.listen((req) async {
    bodies.add(
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>,
    );
    req.response.headers.contentType = ContentType.json;
    final incoming = jsonEncode(bodies.last['messages']);
    if (incoming.contains('malformed-json')) {
      req.response.write('{');
      await req.response.close();
      return;
    }
    if (incoming.contains('no-choice')) {
      req.response.write('{"choices":[]}');
      await req.response.close();
      return;
    }
    if (incoming.contains('bad-url')) {
      req.response.write(
        jsonEncode({
          'id': 'bad',
          'object': 'chat.completion',
          'created': 0,
          'model': 'fixture',
          'choices': [
            {
              'index': 0,
              'message': {
                'role': 'assistant',
                'content': 'bad',
                'images': [
                  {
                    'image_url': {'url': 'not-a-url'},
                  },
                ],
              },
              'finish_reason': 'stop',
            },
          ],
        }),
      );
      await req.response.close();
      return;
    }
    final message = bodies.length == 1
        ? {
            'role': 'assistant',
            'content': 'Caption',
            'images': [
              {
                'image_url': {'url': png},
                'private_signature': 'PRIVATE-IMAGE',
              },
              {
                'image_url': {'url': png},
                'private_signature': 'PRIVATE-SECOND',
              },
            ],
            'tool_calls': [
              {
                'id': 'call-1',
                'type': 'function',
                'function': {'name': 'double', 'arguments': '{"value":21}'},
              },
            ],
          }
        : {'role': 'assistant', 'content': '42'};
    req.response.write(
      jsonEncode({
        'id': 'fixture',
        'object': 'chat.completion',
        'created': 0,
        'model': 'fixture',
        'choices': [
          {
            'index': 0,
            'message': message,
            'finish_reason': bodies.length == 1 ? 'tool_calls' : 'stop',
          },
        ],
      }),
    );
    await req.response.close();
  });
  final client = router.OpenRouterClient.withApiKey(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}',
  );
  final imageConfig = <String, Object?>{'aspect_ratio': '1:1'};
  final options = router.OpenRouterChatOptions(
    modalities: [
      router.OpenRouterOutputModality.text,
      router.OpenRouterOutputModality.image,
    ],
    imageConfig: imageConfig,
  );
  imageConfig['aspect_ratio'] = '16:9';
  final model = router.OpenRouterChatModel(
    client: client,
    model: 'fixture',
    options: options,
  );
  final store = MemoryRunStore();
  var executions = 0;
  AiAgent<void> agent() => AiAgent(
    model: model,
    store: store,
    tools: [
      Tool<int, int, void>(
        name: 'double',
        description: 'Double',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'value': {'type': 'integer'},
          },
          'required': ['value'],
        },
        outputSchema: const {'type': 'integer'},
        needsApproval: true,
        decode: (j) => j['value'] as int,
        encode: (x) => x,
        execute: (x, _) {
          executions++;
          return x * 2;
        },
      ),
    ],
  );
  try {
    final paused = await agent().generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'one',
        messages: [ChatMessage.user('draw and double', id: 'u')],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      paused.status == RunStatus.interrupted && executions == 0,
      'approval',
    );
    check(
      paused.images.length == 2 &&
          paused.images.every((image) => image.url == png),
      'result.images excludes current tool-step output',
    );
    final hydration = jsonEncode(
      chatHydration(await store.load(ownerId: 'owner', threadId: 'thread')),
    );
    check(
      hydration.contains(png) && !hydration.contains('PRIVATE-IMAGE'),
      'public image or private metadata in hydration',
    );
    final otherOwner = jsonEncode(
      chatHydration(await store.load(ownerId: 'other', threadId: 'thread')),
    );
    check(
      !otherOwner.contains(png) && !otherOwner.contains('PRIVATE-IMAGE'),
      'owner isolation',
    );
    final assistant = paused.responseMessages.firstWhere(
      (m) => m.role == MessageRole.assistant,
    );
    check(
      assistant.content.length == 3 &&
          assistant.content[0] is TextPart &&
          (assistant.content[0] as TextPart).text == 'Caption' &&
          assistant.content[1] is ImagePart &&
          (assistant.content[1] as ImagePart).url == png &&
          assistant.content[2] is ImagePart &&
          (assistant.content[2] as ImagePart).url == png,
      'ordered text and image',
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
    check(
      resumed.text == '42' && executions == 1 && resumed.images.isEmpty,
      'recreated agent resume or previous-run image leak',
    );
    final replay = (bodies.last['messages'] as List).firstWhere(
      (message) => message['role'] == 'assistant',
    );
    check(
      jsonEncode(replay['images']) ==
          jsonEncode([
            {
              'image_url': {'url': png},
              'private_signature': 'PRIVATE-IMAGE',
            },
            {
              'image_url': {'url': png},
              'private_signature': 'PRIVATE-SECOND',
            },
          ]),
      'native image metadata not replayed exactly',
    );
    check(
      jsonEncode(bodies.first['modalities']) == '["text","image"]' &&
          bodies.first['image_config']['aspect_ratio'] == '1:1' &&
          bodies.first['stream'] == false,
      'options serialization or snapshot',
    );
    for (final prompt in ['malformed-json', 'no-choice', 'bad-url']) {
      var rejected = false;
      try {
        await model
            .stream(
              ModelRequest(messages: [ChatMessage.user(prompt, id: prompt)]),
              cancellation: CancellationToken(),
            )
            .toList();
      } catch (_) {
        rejected = true;
      }
      check(rejected, '$prompt accepted');
    }
    final count = bodies.length;
    final audio = router.OpenRouterChatModel(
      client: client,
      model: 'fixture',
      options: router.OpenRouterChatOptions(
        modalities: [router.OpenRouterOutputModality.audio],
      ),
    );
    var rejected = false;
    try {
      await audio
          .stream(
            ModelRequest(messages: [ChatMessage.user('audio', id: 'audio')]),
            cancellation: CancellationToken(),
          )
          .toList();
    } catch (_) {
      rejected = true;
    }
    check(
      rejected && bodies.length == count,
      'unsupported audio sent to provider',
    );
    print(
      'PASS ordered media, persisted approval, private replay and options snapshot',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
  await configurationAndCancellation();
}

Future<void> configurationAndCancellation() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, dynamic>>[];
  final pending = Completer<void>();
  server.listen((req) async {
    final body =
        jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    bodies.add(body);
    if (jsonEncode(body['messages']).contains('pending')) {
      pending.complete();
      return;
    }
    req.response.headers.contentType = ContentType.json;
    req.response.write(
      jsonEncode({
        'id': 'fixture',
        'object': 'chat.completion',
        'created': 0,
        'model': 'fixture',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'ok',
              'images': [
                {
                  'image_url': {'url': png},
                },
              ],
            },
            'finish_reason': 'stop',
          },
        ],
      }),
    );
    await req.response.close();
  });
  final client = router.OpenRouterClient.withApiKey(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}',
  );
  final options = router.OpenRouterChatOptions(
    modalities: [
      router.OpenRouterOutputModality.text,
      router.OpenRouterOutputModality.image,
    ],
  );
  ModelRequest request(String text) => ModelRequest(
    messages: [ChatMessage.user(text, id: text)],
    instructions: 'original',
    maxOutputTokens: 47,
    outputSchema: const {
      'type': 'object',
      'properties': {
        'value': {'type': 'integer'},
      },
    },
    tools: [
      ModelTool(
        name: 'double',
        description: 'Double',
        inputSchema: const {'type': 'object'},
      ),
    ],
  );
  try {
    final configured = router.OpenRouterChatModel(
      client: client,
      model: 'fixture',
      options: options,
      configure: (r) => r.copyWith(temperature: 0.2),
    );
    await configured
        .stream(request('configured'), cancellation: CancellationToken())
        .toList();
    check(
      bodies.single['temperature'] == 0.2 &&
          bodies.single['max_completion_tokens'] == 47,
      'typed configure erased valid token settings',
    );
    for (final override in <Map<String, Object?>>[
      {
        'messages': [
          {'role': 'system', 'content': 'overridden'},
        ],
      },
      {
        'response_format': {'type': 'json_object'},
      },
      {
        'tools': [
          {
            'type': 'function',
            'function': {
              'name': 'forged',
              'parameters': {'type': 'object'},
            },
          },
        ],
      },
    ]) {
      final guarded = router.OpenRouterChatModel(
        client: client,
        model: 'fixture',
        options: options,
        configure: (r) => openai.ChatCompletionCreateRequest.fromJson({
          ...r.toJson(),
          ...override,
        }),
      );
      final count = bodies.length;
      var rejected = false;
      try {
        await guarded
            .stream(request('guarded'), cancellation: CancellationToken())
            .toList();
      } catch (_) {
        rejected = true;
      }
      check(
        rejected && bodies.length == count,
        'configure accepted runtime-owned field: $override',
      );
    }
    final parent = CancellationToken();
    final iterator = StreamIterator(
      configured.stream(request('pending'), cancellation: parent),
    );
    final next = iterator.moveNext();
    await pending.future.timeout(const Duration(seconds: 3));
    final sibling = configured
        .stream(request('sibling'), cancellation: parent)
        .toList();
    await iterator.cancel().timeout(const Duration(seconds: 3));
    await next.catchError((_) => false);
    final siblingEvents = await sibling.timeout(const Duration(seconds: 3));
    check(
      siblingEvents.whereType<ContentPartReady>().isNotEmpty &&
          !parent.isCancelled,
      'cancel affected sibling or parent token',
    );
    print(
      'PASS typed configure boundaries and buffered cancellation isolation',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}
