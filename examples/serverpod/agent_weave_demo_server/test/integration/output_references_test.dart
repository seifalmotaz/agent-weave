import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';
import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Native references PostgreSQL recreation', (builder, _) {
    test(
      'retains references and private native replay across approval',
      () async {
        final requests = <JsonObject>[];
        var effects = 0;
        final annotations = <JsonObject>[
          {
            'type': 'file_citation',
            'file_id': 'file-source',
            'filename': 'policy.pdf',
            'index': 2,
            'opaque': 'PRIVATE-REFERENCE',
          },
          {
            'type': 'container_file_citation',
            'file_id': 'file-generated',
            'container_id': 'container',
            'filename': 'result.csv',
            'start_index': 0,
            'end_index': 0,
          },
          {'type': 'file_path', 'file_id': 'file-path', 'index': 99},
          {
            'type': 'url_citation',
            'url': 'https://example.com/source',
            'title': 'Source',
            'start_index': 0,
            'end_index': 2,
          },
        ];
        JsonObject message(String id, String text) => {
          'id': id,
          'type': 'message',
          'role': 'assistant',
          'status': 'completed',
          'content': [
            {'type': 'output_text', 'text': text, 'annotations': annotations},
          ],
        };
        final original = message('native-message', 'A😀');
        AiAgent<void> agent() => AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          model: api.ResponsesProtocolModel.native(
            model: 'fixture',
            transport: (body, _) async* {
              requests.add(immutableJson(body));
              final first = requests.length == 1;
              final output = <JsonObject>[
                first ? original : message('final-message', 'Done'),
                if (first)
                  {
                    'type': 'function_call',
                    'id': 'native-function',
                    'call_id': 'gate-call',
                    'name': 'gate',
                    'arguments': '{}',
                    'status': 'completed',
                  },
              ];
              yield {
                'type': 'response.output_text.delta',
                'delta': first ? 'A😀' : 'Done',
              };
              yield {
                'type': 'response.completed',
                'response': {
                  'status': 'completed',
                  'model': 'fixture',
                  'output': output,
                },
              };
            },
          ),
          tools: [
            Tool<JsonObject, bool, void>(
              name: 'gate',
              description: 'An application effect',
              needsApproval: true,
              inputSchema: const {'type': 'object'},
              outputSchema: const {'type': 'boolean'},
              decode: (json) => json,
              encode: (value) => value,
              execute: (_, _) {
                effects++;
                return true;
              },
            ),
          ],
        );
        final first = agent();
        final paused = await first.generate(
          ChatRequest(
            threadId: 'references',
            runId: 'first',
            messages: [ChatMessage.user('Create', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(paused.status, RunStatus.interrupted);
        expect(effects, 0);
        final refs = paused.responseMessages.single.references;
        expect(refs, hasLength(4));
        expect((refs[1].position as ProviderTextRange).end, 0);
        expect((refs[2].position as FileListPosition).index, 99);
        expect((refs[2].source as FileCitationSource).filename, isNull);
        final fresh = agent();
        expect(
          await fresh.store.load(ownerId: 'other', threadId: 'references'),
          isNull,
        );
        final rejected = await fresh
            .run(
              ChatRequest(
                threadId: 'references',
                runId: 'foreign',
                resume: [paused.interrupts.single.approve()],
              ),
              ownerId: 'other',
              context: null,
            )
            .toList();
        expect(rejected.last.type, 'RUN_ERROR');
        expect(effects, 0);
        expect(requests, hasLength(1));
        final restored = (await fresh.store.load(
          ownerId: 'owner',
          threadId: 'references',
        ))!;
        expect(jsonEncode(restored), contains('PRIVATE-REFERENCE'));
        final public = chatHydration(restored);
        expect(jsonEncode(public), isNot(contains('PRIVATE-REFERENCE')));
        expect(jsonEncode(public), contains('file-source'));
        expect(
          (public['messages'] as List)
              .last['metadata']['agent_weave']['references'],
          refs.map((r) => r.toJson()).toList(),
        );
        final eventLog = await fresh.store.events(
          ownerId: 'owner',
          threadId: 'references',
          runId: 'first',
        );
        final referenceEvents = eventLog
            .where((e) => e['name'] == 'agent_weave:reference')
            .toList();
        expect(
          referenceEvents.map((e) => (e['value'] as Map)['referenceIndex']),
          [0, 1, 2, 3],
        );
        expect(jsonEncode(eventLog), isNot(contains('PRIVATE-REFERENCE')));
        final finalResult = await agent().generate(
          ChatRequest(
            threadId: 'references',
            runId: 'resume',
            parentRunId: 'first',
            resume: [paused.interrupts.single.approve()],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(finalResult.status, RunStatus.completed);
        expect(effects, 1);
        final replay = (requests.last['input'] as List).singleWhere(
          (item) => item['id'] == 'native-message',
        );
        expect(replay, original);
        expect(
          finalResult.responseMessages
              .where((m) => m.role == MessageRole.assistant)
              .single
              .references,
          hasLength(4),
        );
        final finalState = await agent().store.load(
          ownerId: 'owner',
          threadId: 'references',
        );
        expect(
          jsonEncode(chatHydration(finalState)),
          isNot(contains('PRIVATE-REFERENCE')),
        );
      },
    );
  });
}
