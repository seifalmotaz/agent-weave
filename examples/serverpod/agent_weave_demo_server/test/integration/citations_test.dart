import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';
import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Citations PostgreSQL recreation', (builder, _) {
    test(
      'retains typed attribution, private replay and approval isolation',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <JsonObject>[];
        final rawCitation = <String, Object?>{
          'type': 'char_location',
          'document_index': 0,
          'document_title': 'Policy',
          'cited_text': 'The source is distinct from the generated response.',
          'start_char_index': 0,
          'end_char_index': 12,
          'file_id': 'PRIVATE-RESPONSE-FILE',
          'future': {'signature': 'PRIVATE-ANNOTATION'},
        };
        server.listen((request) async {
          requests.add(
            Map<String, Object?>.from(
              jsonDecode(await utf8.decoder.bind(request).join()) as Map,
            ),
          );
          final first = requests.length == 1;
          final blocks = <JsonObject>[
            {
              'type': 'text',
              'text': first ? 'A 🌿 grows.' : 'Confirmed.',
              'citations': [rawCitation],
            },
            if (first)
              {
                'type': 'tool_use',
                'id': 'gate-call',
                'name': 'gate',
                'input': {},
              },
          ];
          final events = <JsonObject>[
            {
              'type': 'message_start',
              'message': {
                'id': first ? 'first' : 'second',
                'model': 'fixture',
                'content': [],
                'usage': {'input_tokens': 2, 'output_tokens': 0},
              },
            },
            for (var i = 0; i < blocks.length; i++) ...[
              {
                'type': 'content_block_start',
                'index': i,
                'content_block': blocks[i],
              },
              {'type': 'content_block_stop', 'index': i},
            ],
            {
              'type': 'message_delta',
              'delta': {'stop_reason': first ? 'tool_use' : 'end_turn'},
              'usage': {'output_tokens': 1},
            },
            {'type': 'message_stop'},
          ];
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          for (final event in events) {
            request.response.write('data: ${jsonEncode(event)}\n\n');
          }
          await request.response.close();
        });
        final client = api.AnthropicNativeClient.withApiKey(
          apiKey: 'fixture',
          baseUrl: 'http://127.0.0.1:${server.port}',
        );
        var effects = 0;
        AiAgent<void> agent() => AiAgent<void>(
          model: client.chatModel(model: 'fixture', citations: true),
          store: ServerpodRunStore(builder.build()),
          tools: [
            Tool<JsonObject, bool, void>(
              name: 'gate',
              description: 'An approved application action',
              inputSchema: const {'type': 'object'},
              outputSchema: const {'type': 'boolean'},
              needsApproval: true,
              decode: (value) => value,
              encode: (value) => value,
              execute: (_, _) {
                effects++;
                return true;
              },
            ),
          ],
        );
        try {
          final first = agent();
          final paused = await first.generate(
            ChatRequest(
              threadId: 'cited',
              runId: 'first',
              messages: [
                ChatMessage(
                  id: 'u',
                  role: MessageRole.user,
                  content: [
                    DocumentPart.bytes(
                      utf8.encode('Policy text.'),
                      mimeType: 'text/plain',
                      filename: 'Policy',
                    ),
                    const TextPart('Read and propose the action.'),
                  ],
                ),
              ],
            ),
            ownerId: 'owner',
            context: null,
          );
          expect(paused.status, RunStatus.interrupted);
          expect(effects, 0);
          final initialCitation =
              paused.responseMessages.single.citations.single;
          expect(initialCitation.start, 0);
          expect(initialCitation.end, 'A 🌿 grows.'.length);
          final saved = (await first.store.load(
            ownerId: 'owner',
            threadId: 'cited',
          ))!;
          expect(jsonEncode(saved), contains('PRIVATE-ANNOTATION'));
          final hydrated = chatHydration(saved);
          expect(jsonEncode(hydrated), isNot(contains('PRIVATE-ANNOTATION')));
          expect(
            jsonEncode(hydrated),
            isNot(contains('PRIVATE-RESPONSE-FILE')),
          );
          expect(
            (hydrated['messages'] as List)
                .last['metadata']['agent_weave']['citations'],
            [initialCitation.toJson()],
          );
          final storedEvents = await first.store.events(
            ownerId: 'owner',
            threadId: 'cited',
            runId: 'first',
          );
          expect(
            storedEvents.where(
              (e) =>
                  e['type'] == 'CUSTOM' && e['name'] == 'agent_weave:citation',
            ),
            hasLength(1),
          );
          expect(
            jsonEncode(storedEvents),
            isNot(contains('PRIVATE-ANNOTATION')),
          );
          final fresh = agent();
          expect(
            await fresh.store.load(ownerId: 'other', threadId: 'cited'),
            isNull,
          );
          final finished = await fresh.generate(
            ChatRequest(
              threadId: 'cited',
              runId: 'resume',
              parentRunId: 'first',
              resume: [paused.interrupts.single.approve()],
            ),
            ownerId: 'owner',
            context: null,
          );
          expect(finished.status, RunStatus.completed);
          expect(effects, 1);
          expect(requests, hasLength(2));
          final priorAssistant =
              (requests.last['messages'] as List).singleWhere(
                    (m) => m['role'] == 'assistant',
                  )
                  as Map;
          final inputCitation =
              priorAssistant['content'][0]['citations'][0] as Map;
          expect(inputCitation.containsKey('file_id'), false);
          expect(inputCitation['future'], rawCitation['future']);
          expect(
            (requests.last['messages'] as List)
                .first['content'][0]['citations'],
            {'enabled': true},
          );
          final restored = (await agent().store.load(
            ownerId: 'owner',
            threadId: 'cited',
          ))!;
          final assistants = (restored['messages'] as List)
              .map(
                (m) =>
                    ChatMessage.fromJson(Map<String, Object?>.from(m as Map)),
              )
              .where((m) => m.role == MessageRole.assistant)
              .toList();
          expect(assistants, hasLength(2));
          expect(
            assistants.first.citations.single.toJson(),
            initialCitation.toJson(),
          );
          expect(assistants.last.citations.single.end, 'Confirmed.'.length);
          expect(
            jsonEncode(chatHydration(restored)),
            isNot(contains('PRIVATE-ANNOTATION')),
          );
        } finally {
          client.close();
          await server.close(force: true);
        }
      },
    );
  });
}
