// Offline consumer review: dart run examples/review_cases/anthropic_citations.dart
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;

void check(bool value, String message) {
  if (!value) throw StateError(message);
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
Map<String, Object?> block(int index, Map<String, Object?> content) => {
  'type': 'content_block_start',
  'index': index,
  'content_block': content,
};
Map<String, Object?> delta(int index, Map<String, Object?> content) => {
  'type': 'content_block_delta',
  'index': index,
  'delta': content,
};
Map<String, Object?> stop(int index) => {
  'type': 'content_block_stop',
  'index': index,
};
Map<String, Object?> finish(String reason) => {
  'type': 'message_delta',
  'delta': {'stop_reason': reason, 'stop_sequence': null},
  'usage': {'output_tokens': 5},
};
const schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'value': {'type': 'integer'},
  },
  'required': ['value'],
};
final nativeCitations = <Map<String, Object?>>[
  {
    'type': 'char_location',
    'cited_text': 'source excerpt',
    'document_index': 0,
    'document_title': 'Notes',
    'start_char_index': 0,
    'end_char_index': 4,
    'file_id': 'PRIVATE-FILE',
    'future': 'PRIVATE-FUTURE',
  },
  {
    'type': 'page_location',
    'cited_text': 'page quote',
    'document_index': 1,
    'document_title': null,
    'start_page_number': 1,
    'end_page_number': 2,
    'file_id': null,
  },
  {
    'type': 'content_block_location',
    'cited_text': 'block quote',
    'document_index': 0,
    'document_title': 'Notes',
    'start_block_index': 1,
    'end_block_index': 2,
    'file_id': null,
  },
  {
    'type': 'web_search_result_location',
    'cited_text': 'web quote',
    'title': 'Web',
    'url': 'https://example.test/page',
    'encrypted_index': 'PRIVATE-INDEX',
  },
  {
    'type': 'search_result_location',
    'cited_text': 'search quote',
    'title': null,
    'source': 'local-index',
    'search_result_index': 0,
    'start_block_index': 0,
    'end_block_index': 1,
  },
];

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, dynamic>>[];
  server.listen((req) async {
    bodies.add(
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>,
    );
    final first = bodies.length == 1;
    final events = first
        ? <Map<String, Object?>>[
            start(),
            block(0, {'type': 'text', 'text': ''}),
            delta(0, {'type': 'text_delta', 'text': 'A😀'}),
            for (final citation in nativeCitations)
              delta(0, {'type': 'citations_delta', 'citation': citation}),
            delta(0, {'type': 'text_delta', 'text': 'B'}),
            stop(0),
            block(1, {'type': 'text', 'text': ''}),
            delta(1, {'type': 'text_delta', 'text': ' more'}),
            stop(1),
            block(2, {
              'type': 'tool_use',
              'id': 'call-1',
              'name': 'double',
              'input': {},
            }),
            delta(2, {
              'type': 'input_json_delta',
              'partial_json': '{"value":21}',
            }),
            stop(2),
            finish('tool_use'),
            {'type': 'message_stop'},
          ]
        : <Map<String, Object?>>[
            start(),
            block(0, {'type': 'text', 'text': ''}),
            delta(0, {'type': 'text_delta', 'text': '42'}),
            stop(0),
            finish('end_turn'),
            {'type': 'message_stop'},
          ];
    final input = jsonEncode(bodies.last['messages']);
    if (input.contains('BAD-URL') ||
        input.contains('UNKNOWN-CITATION') ||
        input.contains('EARLY-EOF')) {
      events
        ..clear()
        ..addAll([
          start(),
          block(0, {'type': 'text', 'text': ''}),
          delta(0, {'type': 'text_delta', 'text': 'partial'}),
          delta(0, {
            'type': 'citations_delta',
            'citation': input.contains('BAD-URL')
                ? {
                    'type': 'web_search_result_location',
                    'cited_text': 'quote',
                    'title': null,
                    'url': 'https://user:secret@example.test/',
                    'encrypted_index': 'PRIVATE',
                  }
                : input.contains('UNKNOWN-CITATION')
                ? {'type': 'future_location', 'cited_text': 'quote'}
                : nativeCitations.first,
          }),
          if (!input.contains('EARLY-EOF')) ...[
            stop(0),
            finish('end_turn'),
            {'type': 'message_stop'},
          ],
        ]);
    }
    req.response.headers.contentType = ContentType(
      'text',
      'event-stream',
      charset: 'utf-8',
    );
    for (final event in events) {
      req.response.write(
        'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
      );
    }
    await req.response.close();
  });
  final client = api.AnthropicNativeClient.withApiKey(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}',
  );
  final model = client.chatModel(model: 'fixture', citations: true);
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
        encode: (v) => v,
        execute: (v, _) {
          effects++;
          return v * 2;
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
            messages: [
              ChatMessage(
                id: 'u',
                role: MessageRole.user,
                content: [
                  const TextPart('Summarize and double'),
                  DocumentPart.bytes(
                    utf8.encode('Test source.'),
                    mimeType: 'text/plain',
                    filename: 'Notes',
                  ),
                  DocumentPart.url(
                    'https://example.test/source.pdf',
                    filename: 'PDF',
                  ),
                ],
              ),
            ],
          ),
          ownerId: 'owner',
          context: null,
        )
        .toList();
    check(events.last.type == 'RUN_FINISHED' && effects == 0, 'approval pause');
    final body = bodies.single;
    final docs = ((body['messages'] as List).first['content'] as List)
        .where((e) => e['type'] == 'document')
        .toList();
    check(
      docs.length == 2 && docs.every((d) => d['citations']['enabled'] == true),
      'document citations enabled',
    );
    final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
    final assistant = (state['messages'] as List)
        .map((e) => ChatMessage.fromJson(Map<String, Object?>.from(e as Map)))
        .firstWhere((m) => m.role == MessageRole.assistant);
    check(
      assistant.text == 'A😀B more' && assistant.citations.length == 5,
      'typed citation result',
    );
    check(
      assistant.citations.every((c) => c.start == 0 && c.end == 4),
      'UTF-16 block span',
    );
    check(
      assistant.citations[0].citedText == 'source excerpt' &&
          assistant.citations[0].source is DocumentCitationSource &&
          assistant.citations[3].source is UrlCitationSource &&
          assistant.citations[4].source is SearchResultCitationSource,
      'typed source mapping',
    );
    final custom = events
        .where(
          (e) => e.type == 'CUSTOM' && e.json['name'] == 'agent_weave:citation',
        )
        .toList();
    check(custom.length == 5, 'live citation events');
    check(
      jsonEncode(
            custom
                .map((e) => (e.json['value'] as Map)['citationIndex'])
                .toList(),
          ) ==
          '[0,1,2,3,4]',
      'stable citation positions',
    );
    final hydration = chatHydration(state);
    final hydratedMessage =
        (hydration['messages'] as List).firstWhere(
              (m) => m['id'] == assistant.id,
            )
            as Map;
    final hydratedCitations =
        ((hydratedMessage['metadata'] as Map)['agent_weave']
            as Map)['citations'];
    final expectedCitations = assistant.citations
        .map((c) => c.toJson())
        .toList();
    check(
      jsonEncode(hydratedCitations) == jsonEncode(expectedCitations),
      'hydration mismatch',
    );
    check(
      jsonEncode(
            custom.map((e) => (e.json['value'] as Map)['citation']).toList(),
          ) ==
          jsonEncode(expectedCitations),
      'stream/hydration mismatch',
    );
    check(
      jsonEncode(
            ChatMessage.fromJson(
              assistant.toJson(),
            ).citations.map((c) => c.toJson()).toList(),
          ) ==
          jsonEncode(expectedCitations),
      'citation JSON roundtrip',
    );
    final publicData = jsonEncode({
      'events': events.map((e) => e.json).toList(),
      'hydration': hydration,
    });
    check(
      !publicData.contains('PRIVATE-INDEX') &&
          !publicData.contains('PRIVATE-FILE') &&
          !publicData.contains('PRIVATE-FUTURE'),
      'private native citation leaked',
    );
    check(
      publicData.contains('source excerpt') &&
          publicData.contains('agent_weave'),
      'hydration citation metadata',
    );
    check(
      !jsonEncode(
        chatHydration(await store.load(ownerId: 'other', threadId: 'thread')),
      ).contains('source excerpt'),
      'owner isolation',
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
    check(result.text == '42' && effects == 1, 'recreated agent resume');
    final replay = jsonEncode(bodies.last['messages']);
    check(
      replay.contains('PRIVATE-INDEX') &&
          replay.contains('PRIVATE-FUTURE') &&
          !replay.contains('PRIVATE-FILE'),
      'native replay fields',
    );
    final count = bodies.length;
    check(
      !model.capabilities.structuredOutput,
      'citation model advertises structured output',
    );
    var rejected = false;
    try {
      await AiAgent<void>(model: model, outputSchema: schema).generate(
        ChatRequest(
          threadId: 'schema',
          runId: 'schema',
          messages: [
            ChatMessage(
              id: 'u',
              role: MessageRole.user,
              content: [
                DocumentPart.bytes(
                  utf8.encode('source'),
                  mimeType: 'text/plain',
                ),
              ],
            ),
          ],
        ),
        ownerId: 'owner',
        context: null,
      );
    } on ArgumentError catch (error) {
      rejected = error.toString().contains(
        'does not support structured output',
      );
    }
    check(
      rejected && bodies.length == count,
      'citations/schema preflight must reject with ArgumentError before HTTP',
    );
    var directRejected = false;
    try {
      await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'schema',
                  role: MessageRole.user,
                  content: [
                    DocumentPart.bytes(
                      utf8.encode('source'),
                      mimeType: 'text/plain',
                    ),
                  ],
                ),
              ],
              outputSchema: schema,
            ),
            cancellation: CancellationToken(),
          )
          .toList();
    } on ArgumentError {
      directRejected = true;
    }
    check(
      directRejected && bodies.length == count,
      'direct model schema guard before HTTP',
    );
    final decorated = client.chatModel(
      model: 'fixture',
      citations: true,
      configure: (body) {
        final copy = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
        final doc =
            (((copy['messages'] as List).first as Map)['content'] as List).first
                as Map;
        doc['context'] = 'Background';
        doc['cache_control'] = {'type': 'ephemeral'};
        return copy;
      },
    );
    final docRequest = ModelRequest(
      messages: [
        ChatMessage(
          id: 'doc',
          role: MessageRole.user,
          content: [DocumentPart.url('https://example.test/original.pdf')],
        ),
      ],
    );
    await decorated
        .stream(docRequest, cancellation: CancellationToken())
        .toList();
    final decoratedDoc =
        (((bodies.last['messages'] as List).first as Map)['content'] as List)
                .first
            as Map;
    check(
      decoratedDoc['context'] == 'Background' &&
          decoratedDoc['cache_control']['type'] == 'ephemeral' &&
          decoratedDoc['citations']['enabled'] == true,
      'valid native document decorations',
    );
    final mixed = client.chatModel(
      model: 'fixture',
      citations: true,
      configure: (body) {
        final copy = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
        final doc =
            (((copy['messages'] as List).first as Map)['content'] as List).first
                as Map;
        doc['citations'] = {'enabled': false};
        return copy;
      },
    );
    final beforeMixed = bodies.length;
    var mixedRejected = false;
    try {
      await mixed
          .stream(docRequest, cancellation: CancellationToken())
          .toList();
    } catch (_) {
      mixedRejected = true;
    }
    check(
      mixedRejected && bodies.length == beforeMixed,
      'disabled document citations accepted',
    );
    for (final field in ['source', 'title']) {
      final changed = client.chatModel(
        model: 'fixture',
        citations: true,
        configure: (body) {
          final copy = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
          final doc =
              (((copy['messages'] as List).first as Map)['content'] as List)
                      .first
                  as Map;
          doc[field] = field == 'title'
              ? 'Forged'
              : {'type': 'url', 'url': 'https://attacker.example/replaced.pdf'};
          return copy;
        },
      );
      final before = bodies.length;
      var blocked = false;
      try {
        await changed
            .stream(docRequest, cancellation: CancellationToken())
            .toList();
      } catch (_) {
        blocked = true;
      }
      check(
        blocked && bodies.length == before,
        'configure changed document $field',
      );
    }
    final guarded = client.chatModel(
      model: 'fixture',
      citations: true,
      configure: (body) {
        final doc =
            (((body['messages'] as List).first as Map)['content'] as List).first
                as Map;
        doc['source'] = {
          'type': 'url',
          'url': 'https://attacker.example/replaced.pdf',
        };
        return body;
      },
    );
    final beforeGuard = bodies.length;
    var guardRejected = false;
    try {
      await guarded
          .stream(
            ModelRequest(
              messages: [
                ChatMessage(
                  id: 'doc',
                  role: MessageRole.user,
                  content: [
                    DocumentPart.url('https://example.test/original.pdf'),
                  ],
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
    } catch (_) {
      guardRejected = true;
    }
    check(
      guardRejected && bodies.length == beforeGuard,
      'configure changed runtime document source in place',
    );
    for (final prompt in ['BAD-URL', 'UNKNOWN-CITATION', 'EARLY-EOF']) {
      final seen = <ModelEvent>[];
      var failed = false;
      try {
        await for (final event in model.stream(
          ModelRequest(messages: [ChatMessage.user(prompt, id: prompt)]),
          cancellation: CancellationToken(),
        )) {
          seen.add(event);
        }
      } catch (_) {
        failed = true;
      }
      check(
        failed && seen.whereType<CitationReady>().isEmpty,
        '$prompt emitted a citation or completed',
      );
    }
    print(
      'PASS typed streamed citations, UTF-16 offsets, hydration, privacy, document options and approval replay',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}
