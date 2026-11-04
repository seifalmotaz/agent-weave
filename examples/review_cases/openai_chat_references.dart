// Offline consumer: dart run examples/review_cases/openai_chat_references.dart
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

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
final annotation = <String, Object?>{
  'type': 'url_citation',
  'url_citation': {
    'url': 'https://example.test/source',
    'title': 'Source',
    'start_index': 0,
    'end_index': 3,
    'type': 'file_citation',
    'file_id': 'PRIVATE-FAKE',
    'filename': 'fake',
    'index': 0,
    'future': 'PRIVATE-UNKNOWN',
  },
};
Map<String, Object?> response(Map<String, Object?> message, String reason) => {
  'id': 'chat-id',
  'object': 'chat.completion',
  'created': 0,
  'model': 'fixture',
  'choices': [
    {'index': 0, 'message': message, 'finish_reason': reason},
  ],
  'usage': {'prompt_tokens': 2, 'completion_tokens': 3},
  'future': 'PRIVATE-RESPONSE',
};
Map<String, Object?> chunk(Map<String, Object?> delta, [String? reason]) => {
  'id': 'c',
  'object': 'chat.completion.chunk',
  'created': 0,
  'model': 'fixture',
  'choices': [
    {'index': 0, 'delta': delta, 'finish_reason': reason},
  ],
};

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, dynamic>>[];
  server.listen((req) async {
    final body =
        jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
    bodies.add(body);
    final prompt = jsonEncode(body['messages']);
    if (body['stream'] == true) {
      req.response.headers.contentType = ContentType('text', 'event-stream');
      final bad = prompt.contains('stream-bad');
      req.response.write(
        'data: ${jsonEncode(chunk({
          'content': 'ok',
          'annotations': bad ? [annotation] : <Object?>[],
        }))}\n\n',
      );
      req.response.write(
        'data: ${jsonEncode(chunk({}, 'stop'))}\n\ndata: [DONE]\n\n',
      );
    } else {
      req.response.headers.contentType = ContentType.json;
      final malformed = prompt.contains('malformed');
      final schemaRequest = body['response_format'] != null;
      final first = bodies.length == 1;
      req.response.write(
        jsonEncode(
          response({
            'role': 'assistant',
            'content': schemaRequest
                ? '{"value":42}'
                : first || malformed
                ? 'A😀B'
                : '42',
            if (first || malformed)
              'annotations': [
                malformed
                    ? {
                        'type': 'url_citation',
                        'url_citation': {
                          'url': 'https://user:secret@example.test/',
                          'title': 'bad',
                          'start_index': 0,
                          'end_index': 1,
                        },
                      }
                    : annotation,
              ],
            if (first || malformed)
              'tool_calls': [
                {
                  'id': 'call-1',
                  'type': 'function',
                  'function': {'name': 'double', 'arguments': '{"value":21}'},
                },
              ],
          }, first || malformed ? 'tool_calls' : 'stop'),
        ),
      );
    }
    await req.response.close();
  });
  final client = openai.OpenAIClient(
    config: openai.OpenAIConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      authProvider: openai.ApiKeyProvider('fixture'),
    ),
  );
  final model = openai.OpenAIChatModel(
    client: client,
    model: 'fixture',
    streamText: false,
    configure: (r) => openai.ChatCompletionCreateRequest.fromJson({
      ...r.toJson(),
      'web_search_options': {'search_context_size': 'low'},
    }),
  );
  final store = MemoryRunStore();
  var effects = 0;
  AiAgent<void> agent() => AiAgent(
    model: model,
    store: store,
    tools: [
      Tool<int, int, void>(
        name: 'double',
        description: 'Double',
        inputSchema: schema,
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
            messages: [ChatMessage.user('search and double', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        )
        .toList();
    check(events.last.type == 'RUN_FINISHED' && effects == 0, 'approval pause');
    check(
      bodies.first['stream'] == false &&
          bodies.first['web_search_options']['search_context_size'] == 'low',
      'typed search config',
    );
    final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
    final assistant = (state['messages'] as List)
        .map((m) => ChatMessage.fromJson(Map<String, Object?>.from(m as Map)))
        .firstWhere((m) => m.role == MessageRole.assistant);
    check(
      assistant.text == 'A😀B' && assistant.references.length == 1,
      'typed reference',
    );
    final ref = assistant.references.single;
    check(
      ref.partStart == 0 &&
          ref.partEnd == 4 &&
          ref.position is ProviderTextRange &&
          (ref.position as ProviderTextRange).end == 3,
      'enclosing span or native position',
    );
    check(
      ref.source is UrlCitationSource &&
          (ref.source as UrlCitationSource).url ==
              'https://example.test/source' &&
          ref.source.title == 'Source',
      'source card or nested fake type',
    );
    final live = events
        .where(
          (e) =>
              e.type == 'CUSTOM' && e.json['name'] == 'agent_weave:reference',
        )
        .single;
    final payload = live.json['value'] as Map;
    final hydration = chatHydration(state);
    final hydrated =
        (hydration['messages'] as List).firstWhere(
              (m) => m['id'] == assistant.id,
            )
            as Map;
    final references =
        ((hydrated['metadata'] as Map)['agent_weave'] as Map)['references'];
    check(
      payload['referenceIndex'] == 0 &&
          jsonEncode(payload['reference']) == jsonEncode(ref.toJson()) &&
          jsonEncode(references) == jsonEncode([ref.toJson()]),
      'reference event/hydration parity',
    );
    check(
      !jsonEncode(
        chatHydration(await store.load(ownerId: 'other', threadId: 'thread')),
      ).contains('example.test/source'),
      'owner isolation',
    );
    final public = jsonEncode({
      'events': events.map((e) => e.json).toList(),
      'hydration': chatHydration(state),
    });
    check(
      !public.contains('PRIVATE-FAKE') &&
          !public.contains('PRIVATE-UNKNOWN') &&
          !public.contains('PRIVATE-RESPONSE'),
      'private fields exposed',
    );
    final audit = jsonEncode(assistant.providerData['openai.chat_completions']);
    check(
      audit.contains('PRIVATE-FAKE') && audit.contains('PRIVATE-RESPONSE'),
      'full private response lost',
    );
    final id = ((state['pending'] as List).single as Map)['id'] as String;
    final result = await agent().generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'two',
        parentRunId: 'one',
        resume: [ResumeAnswer(interruptId: id, value: true)],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(result.text == '42' && effects == 1, 'approval recreation');
    final next = jsonEncode(bodies[1]['messages']);
    check(
      !next.contains('annotations') &&
          !next.contains('PRIVATE-FAKE') &&
          next.contains('call-1'),
      'response-only annotations in input',
    );
    final value = await generateObject<int>(
      model: model,
      prompt: 'schema',
      schema: schema,
      decode: (j) => (j as Map)['value'] as int,
    );
    check(
      value.value == 42 &&
          bodies.last['response_format'] != null &&
          bodies.last['web_search_options'] != null,
      'typed schema/config',
    );
    final before = bodies.length;
    final guarded = openai.OpenAIChatModel(
      client: client,
      model: 'fixture',
      streamText: false,
      configure: (r) => openai.ChatCompletionCreateRequest.fromJson({
        ...r.toJson(),
        'messages': <Object?>[],
      }),
    );
    var guardedRejected = false;
    try {
      await guarded
          .stream(
            ModelRequest(messages: [ChatMessage.user('guard', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList();
    } on ArgumentError {
      guardedRejected = true;
    }
    check(
      guardedRejected && bodies.length == before,
      'runtime-owned messages override',
    );
    var malformedRejected = false;
    final badEvents = <ModelEvent>[];
    try {
      await for (final event in model.stream(
        ModelRequest(
          messages: [ChatMessage.user('malformed', id: 'u')],
          tools: [
            const ModelTool(
              name: 'double',
              description: 'Double',
              inputSchema: schema,
            ),
          ],
        ),
        cancellation: CancellationToken(),
      )) {
        badEvents.add(event);
      }
    } catch (_) {
      malformedRejected = true;
    }
    check(
      malformedRejected &&
          badEvents.whereType<ToolCallReady>().isEmpty &&
          badEvents.whereType<ReferenceReady>().isEmpty &&
          effects == 1,
      'malformed annotation released effect or reference',
    );
    final streaming = openai.OpenAIChatModel(client: client, model: 'fixture');
    final good = await streaming
        .stream(
          ModelRequest(messages: [ChatMessage.user('stream-good', id: 'u')]),
          cancellation: CancellationToken(),
        )
        .toList();
    check(
      good.whereType<TextDelta>().map((e) => e.text).join() == 'ok',
      'empty stream annotations',
    );
    var unsupported = false;
    try {
      await streaming
          .stream(
            ModelRequest(messages: [ChatMessage.user('stream-bad', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList();
    } on UnsupportedError {
      unsupported = true;
    }
    check(unsupported, 'nonempty SSE annotation not explicitly unsupported');
    print(
      'PASS buffered Chat reference, SDK config/schema, approval audit, guards and stream boundary',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}
