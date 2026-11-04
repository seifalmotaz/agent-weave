import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

final hostedOutput = <Map<String, Object?>>[
  {
    'type': 'web_search_call',
    'id': 'web-1',
    'status': 'completed',
    'action': {'type': 'search', 'query': 'Dart'},
    'future_field': {'secret': 'PRIVATE-WEB'},
  },
  {
    'type': 'file_search_call',
    'id': 'file-1',
    'status': 'completed',
    'queries': ['Dart'],
    'results': [
      {'file_id': 'file-123', 'text': 'PRIVATE-FILE'},
    ],
  },
  {
    'type': 'code_interpreter_call',
    'id': 'code-1',
    'status': 'completed',
    'container_id': 'container-1',
    'code': 'print(42)',
    'outputs': [
      {'type': 'logs', 'logs': 'PRIVATE-CODE'},
    ],
  },
  {
    'type': 'image_generation_call',
    'id': 'image-1',
    'status': 'completed',
    'result':
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aQAAAABJRU5ErkJggg==',
    'output_format': 'png',
  },
];
final appCall = <String, Object?>{
  'type': 'function_call',
  'id': 'item-1',
  'call_id': 'call-1',
  'name': 'double',
  'arguments': '{"value":21}',
  'status': 'completed',
  'future_field': 'PRIVATE-FUNCTION',
};

Future<void> main() async {
  await postDispatchCancellation();
  print('PASS post-dispatch cancellation');
  await schemaGuard();
  print('PASS schema guard');
  await injectedToolGuard();
  print('PASS injected tool guard');
  await hostedGuard();
  print('PASS hosted guard');
  await configurationGuard();
  print('PASS configuration guard');
  await wrongProvider();
  print('PASS wrong provider');
  for (final mode in [
    'approval',
    'auto',
    'eof',
    'cancel',
    'mismatch',
    'incomplete',
  ]) {
    await journey(mode);
    print('PASS $mode');
  }
}

Future<void> journey(String mode) async {
  final bodies = <Map<String, dynamic>>[];
  var executions = 0;
  var completed = false;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    bodies.add(
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>,
    );
    check(req.uri.path == '/v1/responses', 'Responses endpoint');
    req.response.headers.contentType = ContentType('text', 'event-stream');
    void send(Object event) =>
        req.response.write('data: ${jsonEncode(event)}\n\n');
    if (bodies.length == 1) {
      for (final item in [...hostedOutput, appCall]) {
        send({'type': 'response.output_item.done', 'item': item});
      }
      await req.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      check(executions == 0, 'App tool ran before response.completed');
      if (mode != 'eof') {
        completed = true;
        send({
          'type': mode == 'incomplete'
              ? 'response.incomplete'
              : 'response.completed',
          'response': {
            'id': 'r1',
            'object': 'response',
            'created_at': 0,
            'status': mode == 'incomplete' ? 'incomplete' : 'completed',
            'model': 'local',
            'output': [...hostedOutput, if (mode != 'mismatch') appCall],
          },
        });
      }
    } else {
      send({'type': 'response.output_text.delta', 'delta': '42'});
      send({
        'type': 'response.completed',
        'response': {
          'id': 'r2',
          'object': 'response',
          'created_at': 0,
          'status': 'completed',
          'model': 'local',
          'output': <Object?>[],
        },
      });
    }
    req.response.write('data: [DONE]\n\n');
    await req.response.close();
  });
  final client = openai.OpenAIClient(
    config: openai.OpenAIConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      authProvider: openai.ApiKeyProvider('fixture'),
    ),
  );
  final store = MemoryRunStore();
  AiAgent<void> agent() => AiAgent<void>(
    model: openai.OpenAIResponsesModel.native(
      client: client,
      model: 'local',
      hostedTools: [
        openai.OpenAIHostedTool(
          const openai.WebSearchTool(searchContextSize: 'low'),
        ),
        openai.OpenAIHostedTool(
          const openai.FileSearchTool(
            vectorStoreIds: ['vs-1'],
            maxNumResults: 2,
          ),
        ),
        openai.OpenAIHostedTool.fromJson({
          'type': 'code_interpreter',
          'container': {'type': 'auto', 'future_container_option': 'preserve'},
        }),
        openai.OpenAIHostedTool.fromJson({
          'type': 'image_generation',
          'output_format': 'png',
          'future_image_option': 'preserve',
        }),
      ],
      configure: (body) => {
        ...body,
        'future_request_option': {'value': 7},
      },
    ),
    store: store,
    tools: [
      Tool<int, int, void>(
        name: 'double',
        description: 'Double a number',
        needsApproval: mode == 'approval',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'value': {'type': 'integer'},
          },
          'required': ['value'],
        },
        decode: (value) => value['value'] as int,
        encode: (value) => value,
        execute: (value, context) {
          check(completed, 'App tool ran before completion');
          executions++;
          return value * 2;
        },
      ),
    ],
  );
  try {
    final token = CancellationToken();
    if (mode == 'cancel') token.cancel();
    AgentResult? paused;
    Object? failure;
    try {
      paused = await agent().generate(
        ChatRequest(
          threadId: 'thread',
          runId: 'first',
          messages: [ChatMessage.user('Find and calculate', id: 'u1')],
        ),
        ownerId: 'owner',
        context: null,
        cancellation: token,
      );
    } catch (e) {
      failure = e;
    }
    if (mode != 'cancel') {
      final tools = bodies.first['tools'] as List;
      for (final type in [
        'web_search',
        'file_search',
        'code_interpreter',
        'image_generation',
        'function',
      ]) {
        check(
          tools.where((tool) => (tool as Map)['type'] == type).length == 1,
          'Missing tool $type',
        );
      }
      check(
        jsonEncode(tools).contains('future_container_option') &&
            jsonEncode(tools).contains('future_image_option') &&
            bodies.first['future_request_option']['value'] == 7,
        'Unknown request fields lost',
      );
    }
    if (mode == 'eof' ||
        mode == 'cancel' ||
        mode == 'mismatch' ||
        mode == 'incomplete') {
      check(
        failure != null && executions == 0,
        '$mode should stop without execution',
      );
      check(bodies.length == (mode == 'cancel' ? 0 : 1), '$mode request count');
      return;
    }
    if (mode == 'auto') {
      check(
        failure == null &&
            paused?.text == '42' &&
            executions == 1 &&
            bodies.length == 2,
        'Automatic execution: $failure',
      );
      return;
    }
    check(
      failure == null &&
          paused != null &&
          paused.status == RunStatus.interrupted,
      'Approval pause: $failure',
    );
    check(
      executions == 0 && paused!.interrupts.length == 1,
      'Approval executed early',
    );
    check(
      paused!.responseMessages
          .expand((m) => m.content)
          .whereType<ImagePart>()
          .any(
            (p) =>
                p.url ==
                'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aQAAAABJRU5ErkJggg==',
          ),
      'Generated image unavailable in response',
    );
    final checkpoint = await store.load(ownerId: 'owner', threadId: 'thread');
    check(
      jsonEncode(checkpoint).contains('PRIVATE-WEB'),
      'Hosted result absent from private checkpoint',
    );
    check(
      !jsonEncode(chatHydration(checkpoint)).contains('PRIVATE-WEB'),
      'Hosted result leaked through hydration',
    );
    final approval = paused;
    var denied = false;
    try {
      await agent().generate(
        ChatRequest(
          threadId: 'thread',
          runId: 'intruder',
          parentRunId: approval.runId,
          resume: [approval.interrupts.single.approve()],
        ),
        ownerId: 'other-owner',
        context: null,
      );
    } catch (_) {
      denied = true;
    }
    check(
      denied && executions == 0 && bodies.length == 1,
      'Other owner resumed approval',
    );
    final result = await agent().generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'resume',
        parentRunId: approval.runId,
        resume: [approval.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      result.text == '42' && executions == 1 && bodies.length == 2,
      'Approval continuation',
    );
    final input = bodies.last['input'] as List;
    for (final item in [...hostedOutput, appCall]) {
      check(
        input.any(
          (candidate) => canonicalJson(candidate) == canonicalJson(item),
        ),
        'Lost replay item ${item['type']}',
      );
    }
  } finally {
    client.close();
    await server.close(force: true);
  }
}

Future<void> wrongProvider() async {
  Map<String, dynamic>? sent;
  final model = openai.ResponsesProtocolModel(
    model: 'local',
    transport: (request, _) {
      sent = request.toJson();
      return Stream.value({
        'type': 'response.completed',
        'response': {'status': 'completed', 'output': <Object?>[]},
      });
    },
  );
  await model
      .stream(
        ModelRequest(
          messages: [
            ChatMessage(
              id: 'a',
              role: MessageRole.assistant,
              content: [TextPart('visible')],
              providerData: {
                'other.provider': [
                  {'type': 'web_search_call', 'future': 'WRONG-PROVIDER'},
                ],
              },
            ),
          ],
        ),
        cancellation: CancellationToken(),
      )
      .toList();
  check(
    jsonEncode(sent).contains('visible') &&
        !jsonEncode(sent).contains('WRONG-PROVIDER'),
    'Wrong provider replay',
  );
}

Future<void> configurationGuard() async {
  var sent = false;
  final model = openai.ResponsesProtocolModel(
    model: 'local',
    configure: (request) => request.copyWith(instructions: 'replaced'),
    transport: (_, _) {
      sent = true;
      return const Stream.empty();
    },
  );
  var failed = false;
  try {
    await model
        .stream(
          ModelRequest(
            messages: [ChatMessage.user('hello', id: 'u')],
            instructions: 'trusted',
          ),
          cancellation: CancellationToken(),
        )
        .toList();
  } catch (_) {
    failed = true;
  }
  check(failed && !sent, 'Configuration replaced trusted instructions');
}

Future<void> hostedGuard() async {
  var sent = false;
  final model = openai.ResponsesProtocolModel.native(
    model: 'local',
    hostedTools: [
      openai.OpenAIHostedTool.fromJson({
        'type': 'web_search',
        'future': 'keep',
      }),
    ],
    configure: (body) => {
      ...body,
      'tools': [
        {'type': 'web_search'},
      ],
    },
    transport: (_, _) {
      sent = true;
      return const Stream.empty();
    },
  );
  var failed = false;
  try {
    await model
        .stream(
          ModelRequest(messages: [ChatMessage.user('hello', id: 'u')]),
          cancellation: CancellationToken(),
        )
        .toList();
  } catch (_) {
    failed = true;
  }
  check(failed && !sent, 'Configuration replaced hosted definition');
}

Future<void> injectedToolGuard() async {
  var sent = false;
  final model = openai.ResponsesProtocolModel.native(
    model: 'local',
    configure: (body) => {
      ...body,
      'tools': [
        {
          'type': 'function',
          'name': 'unregistered',
          'parameters': {'type': 'object'},
        },
      ],
    },
    transport: (_, _) {
      sent = true;
      return const Stream.empty();
    },
  );
  var failed = false;
  try {
    await model
        .stream(
          ModelRequest(messages: [ChatMessage.user('hello', id: 'u')]),
          cancellation: CancellationToken(),
        )
        .toList();
  } catch (_) {
    failed = true;
  }
  check(failed && !sent, 'Configuration injected unregistered tool');
}

Future<void> schemaGuard() async {
  var sent = false;
  final model = openai.ResponsesProtocolModel.native(
    model: 'local',
    configure: (body) => {
      ...body,
      'text': {
        'format': {'type': 'text'},
      },
    },
    transport: (_, _) {
      sent = true;
      return const Stream.empty();
    },
  );
  var failed = false;
  try {
    await model
        .stream(
          ModelRequest(
            messages: [ChatMessage.user('hello', id: 'u')],
            outputSchema: const {
              'type': 'object',
              'properties': {
                'answer': {'type': 'integer'},
              },
            },
          ),
          cancellation: CancellationToken(),
        )
        .toList();
  } catch (_) {
    failed = true;
  }
  check(failed && !sent, 'Configuration replaced runtime output schema');
}

Future<void> postDispatchCancellation() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final flushed = Completer<void>();
  final release = Completer<void>();
  var requests = 0;
  var executions = 0;
  server.listen((request) async {
    requests++;
    await utf8.decoder.bind(request).join();
    request.response.headers.contentType = ContentType('text', 'event-stream');
    request.response.write(
      'data: ${jsonEncode({'type': 'response.output_item.done', 'item': appCall})}\n\n',
    );
    await request.response.flush();
    flushed.complete();
    await release.future;
    try {
      await request.response.close();
    } catch (_) {}
  });
  final client = openai.OpenAIClient(
    config: openai.OpenAIConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      authProvider: openai.ApiKeyProvider('fixture'),
    ),
  );
  final token = CancellationToken();
  final agent = AiAgent<void>(
    model: openai.OpenAIResponsesModel.native(
      client: client,
      model: 'local',
      hostedTools: [openai.OpenAIHostedTool(const openai.WebSearchTool())],
    ),
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
        decode: (v) => v['value'] as int,
        encode: (v) => v,
        execute: (v, _) {
          executions++;
          return v * 2;
        },
      ),
    ],
  );
  try {
    final run = agent.generate(
      ChatRequest(
        threadId: 'cancel',
        runId: 'one',
        messages: [ChatMessage.user('Go', id: 'u')],
      ),
      ownerId: 'owner',
      context: null,
      cancellation: token,
    );
    await flushed.future.timeout(const Duration(seconds: 5));
    token.cancel();
    Object? failure;
    try {
      await run.timeout(const Duration(seconds: 5));
    } catch (e) {
      failure = e;
    }
    check(
      failure != null &&
          failure is! TimeoutException &&
          executions == 0 &&
          requests == 1,
      'Cancellation after dispatched call: $failure',
    );
  } finally {
    release.complete();
    client.close();
    await server.close(force: true);
  }
}
