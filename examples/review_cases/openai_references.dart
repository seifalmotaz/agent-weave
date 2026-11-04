// Offline consumer: dart run examples/review_cases/openai_references.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

final annotations = <Map<String, Object?>>[
  {
    'type': 'url_citation',
    'start_index': 0,
    'end_index': 2,
    'url': 'https://example.test/article',
    'title': 'Article',
    'future': 'PRIVATE-URL',
  },
  {
    'type': 'container_file_citation',
    'start_index': 0,
    'end_index': 0,
    'container_id': 'container-1',
    'file_id': 'file-created',
    'filename': 'plot.png',
    'future': 'PRIVATE-CONTAINER',
  },
  {
    'type': 'file_citation',
    'index': 3,
    'file_id': 'file-source',
    'filename': 'notes.pdf',
  },
  {
    'type': 'file_citation',
    'index': 3,
    'file_id': 'file-source',
    'filename': 'notes.pdf',
  },
  {'type': 'file_path', 'index': 99, 'file_id': 'file-other'},
];
final parts = <Map<String, Object?>>[
  {
    'type': 'output_text',
    'text': 'A😀',
    'annotations': annotations,
    'logprobs': <Object?>[],
  },
  {
    'type': 'output_text',
    'text': '',
    'annotations': [
      {'type': 'file_path', 'index': 4, 'file_id': 'empty-file'},
    ],
    'logprobs': <Object?>[],
  },
  {
    'type': 'output_text',
    'text': ' tail',
    'annotations': [
      {
        'type': 'url_citation',
        'start_index': 0,
        'end_index': 5,
        'url': 'https://example.test/tail',
        'title': 'Tail',
      },
    ],
    'logprobs': <Object?>[],
  },
];
final assistantItem = <String, Object?>{
  'id': 'msg-one',
  'type': 'message',
  'role': 'assistant',
  'status': 'completed',
  'content': parts,
  'future': 'PRIVATE-MESSAGE',
};
final imageOutput = <String, Object?>{
  'id': 'image-one',
  'type': 'image_generation_call',
  'status': 'completed',
  'result':
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
  'output_format': 'png',
};
final toolCall = <String, Object?>{
  'id': 'item-one',
  'type': 'function_call',
  'call_id': 'call-one',
  'name': 'double',
  'arguments': '{"value":21}',
  'status': 'completed',
};
Map<String, Object?> terminal(List<Object?> output) => {
  'id': 'response',
  'object': 'response',
  'created_at': 0,
  'status': 'completed',
  'model': 'fixture',
  'output': output,
};

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, dynamic>>[];
  server.listen((req) async {
    bodies.add(
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>,
    );
    req.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    void send(Map<String, Object?> data) =>
        req.response.write('data: ${jsonEncode(data)}\n\n');
    if (bodies.length == 1) {
      send({
        'type': 'response.output_text.delta',
        'item_id': 'msg-one',
        'output_index': 0,
        'content_index': 0,
        'delta': 'A😀',
      });
      for (var i = 0; i < annotations.length; i++) {
        send({
          'type': 'response.output_text.annotation.added',
          'item_id': 'msg-one',
          'output_index': 0,
          'content_index': 0,
          'annotation_index': i,
          'annotation': annotations[i],
        });
      }
      for (var i = 0; i < parts.length; i++) {
        if (i == 2) {
          send({
            'type': 'response.output_text.delta',
            'item_id': 'msg-one',
            'output_index': 0,
            'content_index': 2,
            'delta': ' tail',
          });
        }
        send({
          'type': 'response.content_part.done',
          'item_id': 'msg-one',
          'output_index': 0,
          'content_index': i,
          'part': parts[i],
        });
      }
      send({
        'type': 'response.output_item.done',
        'output_index': 0,
        'item': assistantItem,
      });
      send({
        'type': 'response.output_item.done',
        'output_index': 1,
        'item': imageOutput,
      });
      send({
        'type': 'response.output_item.done',
        'output_index': 2,
        'item': toolCall,
      });
      send({
        'type': 'response.completed',
        'response': terminal([assistantItem, imageOutput, toolCall]),
      });
    } else {
      send({
        'type': 'response.output_text.delta',
        'item_id': 'final',
        'output_index': 0,
        'content_index': 0,
        'delta': '42',
      });
      send({'type': 'response.completed', 'response': terminal(<Object?>[])});
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
  var effects = 0;
  AiAgent<void> agent() => AiAgent(
    model: openai.OpenAIResponsesModel.native(
      client: client,
      model: 'fixture',
      hostedTools: [
        openai.OpenAIHostedTool.fromJson({
          'type': 'image_generation',
          'output_format': 'png',
        }),
      ],
    ),
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
          effects++;
          return x * 2;
        },
      ),
    ],
  );
  try {
    final events = await agent()
        .run(
          ChatRequest(
            threadId: 'thread',
            runId: 'one',
            messages: [ChatMessage.user('Search and double', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        )
        .toList();
    check(events.last.type == 'RUN_FINISHED' && effects == 0, 'approval pause');
    final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
    final message = (state['messages'] as List)
        .map((m) => ChatMessage.fromJson(Map<String, Object?>.from(m as Map)))
        .firstWhere((m) => m.role == MessageRole.assistant);
    check(
      message.content.whereType<ImagePart>().length == 1,
      'image output lost',
    );
    check(
      message.text == 'A😀 tail' && message.references.length == 7,
      'typed references',
    );
    check(
      message.references
              .take(5)
              .every(
                (r) =>
                    r.provider == 'openai' &&
                    r.partStart == 0 &&
                    r.partEnd == 3,
              ) &&
          message.references[5].partStart == 3 &&
          message.references[5].partEnd == 3 &&
          message.references[6].partStart == 3 &&
          message.references[6].partEnd == 8,
      'UTF-16 enclosing text part',
    );
    check(
      message.references[0].source is UrlCitationSource &&
          message.references[0].position is ProviderTextRange,
      'URL reference',
    );
    final container = message.references[1];
    check(
      (container.position as ProviderTextRange).start == 0 &&
          (container.position as ProviderTextRange).end == 0 &&
          (container.source as FileCitationSource).containerId == 'container-1',
      '0/0 container',
    );
    check(
      message.references[2].position is ProviderTextPosition &&
          message.references[3].position is ProviderTextPosition &&
          jsonEncode(message.references[2].toJson()) ==
              jsonEncode(message.references[3].toJson()),
      'equal file citations',
    );
    final path = message.references[4];
    check(
      (path.position as FileListPosition).index == 99 &&
          (path.source as FileCitationSource).filename == null,
      'file-list ordinal and absent filename',
    );
    final source = path.source as FileCitationSource;
    final reusable =
        DocumentPart.fileId(source.fileId, provider: source.provider)
            as FileIdDocumentPart;
    check(
      reusable.provider == 'openai' && reusable.fileId == 'file-other',
      'scoped reusable handle',
    );
    final custom = events
        .where(
          (e) =>
              e.type == 'CUSTOM' && e.json['name'] == 'agent_weave:reference',
        )
        .toList();
    check(
      jsonEncode(
            custom
                .map((e) => (e.json['value'] as Map)['referenceIndex'])
                .toList(),
          ) ==
          '[0,1,2,3,4,5,6]',
      'reference index',
    );
    final hydration = chatHydration(state);
    final h =
        (hydration['messages'] as List).firstWhere((m) => m['id'] == message.id)
            as Map;
    final saved = ((h['metadata'] as Map)['agent_weave'] as Map)['references'];
    final expected = message.references.map((r) => r.toJson()).toList();
    check(
      jsonEncode(saved) == jsonEncode(expected) &&
          jsonEncode(
                custom
                    .map((e) => (e.json['value'] as Map)['reference'])
                    .toList(),
              ) ==
              jsonEncode(expected),
      'live/hydration parity',
    );
    check(
      !jsonEncode({
        'events': events.map((e) => e.json).toList(),
        'hydration': hydration,
      }).contains('PRIVATE-'),
      'opaque native metadata leaked',
    );
    check(
      !jsonEncode(
        chatHydration(await store.load(ownerId: 'other', threadId: 'thread')),
      ).contains('file-source'),
      'owner isolation',
    );
    final pending = ((state['pending'] as List).single as Map)['id'] as String;
    var otherRejected = false;
    try {
      await agent().generate(
        ChatRequest(
          threadId: 'thread',
          runId: 'other',
          parentRunId: 'one',
          resume: [ResumeAnswer(interruptId: pending, value: true)],
        ),
        ownerId: 'other',
        context: null,
      );
    } catch (_) {
      otherRejected = true;
    }
    check(otherRejected && effects == 0, 'other owner resumed approval');
    final result = await agent().generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'two',
        parentRunId: 'one',
        resume: [ResumeAnswer(interruptId: pending, value: true)],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(result.text == '42' && effects == 1, 'approval resume');
    final input = bodies.last['input'] as List;
    final native = input.firstWhere((item) => item['id'] == 'msg-one');
    check(
      jsonEncode(native) == jsonEncode(assistantItem),
      'exact native replay',
    );
    print(
      'PASS Responses references, source handles, event/hydration parity, owner privacy and approval replay',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
  await failureCases();
  await cancelCase();
}

Future<void> failureCases() async {
  for (final mode in ['conflict', 'eof', 'invalid']) {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
      req.response.headers.contentType = ContentType('text', 'event-stream');
      void send(Map<String, Object?> event) =>
          req.response.write('data: ${jsonEncode(event)}\n\n');
      final invalid = <String, Object?>{
        'type': 'url_citation',
        'start_index': 0,
        'end_index': 1,
        'title': 'bad',
        'url': 'https://user:secret@example.test/',
      };
      final emitted = mode == 'invalid' ? invalid : annotations.first;
      final complete = mode == 'conflict'
          ? {...annotations.first, 'url': 'https://example.test/other'}
          : emitted;
      final part = <String, Object?>{
        'type': 'output_text',
        'text': 'X',
        'annotations': [complete],
      };
      final item = <String, Object?>{
        'type': 'message',
        'id': 'msg',
        'role': 'assistant',
        'status': 'completed',
        'content': [part],
      };
      send({
        'type': 'response.output_text.delta',
        'item_id': 'msg',
        'output_index': 0,
        'content_index': 0,
        'delta': 'X',
      });
      send({
        'type': 'response.output_text.annotation.added',
        'item_id': 'msg',
        'output_index': 0,
        'content_index': 0,
        'annotation_index': 0,
        'annotation': emitted,
      });
      send({
        'type': 'response.output_item.done',
        'output_index': 1,
        'item': toolCall,
      });
      if (mode != 'eof') {
        send({
          'type': 'response.content_part.done',
          'item_id': 'msg',
          'output_index': 0,
          'content_index': 0,
          'part': part,
        });
        send({
          'type': 'response.output_item.done',
          'output_index': 0,
          'item': item,
        });
        send({
          'type': 'response.completed',
          'response': terminal([item, toolCall]),
        });
      }
      await req.response.close();
    });
    final client = openai.OpenAIClient(
      config: openai.OpenAIConfig(
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        authProvider: openai.ApiKeyProvider('fixture'),
      ),
    );
    var effects = 0;
    try {
      final agent = AiAgent<void>(
        model: openai.OpenAIResponsesModel.native(
          client: client,
          model: 'fixture',
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
            outputSchema: const {'type': 'integer'},
            decode: (j) => j['value'] as int,
            encode: (v) => v,
            execute: (v, _) {
              effects++;
              return v * 2;
            },
          ),
        ],
      );
      final events = await agent
          .run(
            ChatRequest(
              threadId: mode,
              runId: mode,
              messages: [ChatMessage.user('test', id: 'u')],
            ),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      check(
        events.last.type == 'RUN_ERROR' &&
            effects == 0 &&
            !events.any(
              (e) =>
                  e.type == 'CUSTOM' &&
                  e.json['name'] == 'agent_weave:reference',
            ),
        '$mode accepted or emitted a reference/effect',
      );
    } finally {
      client.close();
      await server.close(force: true);
    }
  }
  print(
    'PASS conflicting, unsafe and incomplete annotations fail before effects',
  );
}

Future<void> cancelCase() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sent = Completer<void>();
  final release = Completer<void>();
  server.listen((req) async {
    await req.drain<void>();
    req.response.bufferOutput = false;
    req.response.headers.contentType = ContentType('text', 'event-stream');
    req.response.write(
      'data: ${jsonEncode({'type': 'response.output_item.done', 'output_index': 1, 'item': toolCall})}\n\n',
    );
    await req.response.flush();
    sent.complete();
    await release.future;
    await req.response.close();
  });
  final client = openai.OpenAIClient(
    config: openai.OpenAIConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      authProvider: openai.ApiKeyProvider('fixture'),
    ),
  );
  final token = CancellationToken();
  var effects = 0;
  try {
    final agent = AiAgent<void>(
      model: openai.OpenAIResponsesModel.native(
        client: client,
        model: 'fixture',
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
          decode: (j) => j['value'] as int,
          encode: (v) => v,
          execute: (v, _) {
            effects++;
            return v * 2;
          },
        ),
      ],
    );
    final pending = agent
        .run(
          ChatRequest(
            threadId: 'cancel',
            runId: 'cancel',
            messages: [ChatMessage.user('test', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
          cancellation: token,
        )
        .toList();
    await sent.future.timeout(const Duration(seconds: 3));
    token.cancel();
    final events = await pending.timeout(const Duration(seconds: 3));
    check(
      effects == 0 &&
          !events.any(
            (e) =>
                e.type == 'CUSTOM' && e.json['name'] == 'agent_weave:reference',
          ),
      'cancel emitted reference or executed tool',
    );
  } finally {
    release.complete();
    client.close();
    await server.close(force: true);
  }
  print('PASS cancellation before terminal prevents effects');
}
