import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:serverpod/serverpod.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Anthropic computer PostgreSQL continuation', (builder, _) {
    test(
      'reloads approval, rejects target drift, and halts failed batch',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Map<String, dynamic>>[];
        final calls = [
          {
            'type': 'tool_use',
            'id': 'call-key',
            'name': 'key',
            'toolset_name': 'computer',
            'caller': {'type': 'direct'},
            'input': {'text': 'Tab'},
            'private_extra': 'PRIVATE-KEY',
          },
          {
            'type': 'tool_use',
            'id': 'call-shot',
            'name': 'screenshot',
            'toolset_name': 'computer',
            'caller': {'type': 'direct'},
            'input': <String, Object?>{},
            'private_extra': 'PRIVATE-SHOT',
          },
        ];
        server.listen((request) async {
          requests.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          final events = <Map<String, Object?>>[
            {
              'type': 'message_start',
              'message': {
                'id': 'message',
                'type': 'message',
                'role': 'assistant',
                'model': 'fixture',
                'content': <Object?>[],
                'usage': {'input_tokens': 1, 'output_tokens': 0},
              },
            },
            if (requests.length == 1)
              for (var i = 0; i < calls.length; i++) ...[
                {
                  'type': 'content_block_start',
                  'index': i,
                  'content_block': calls[i],
                },
                {'type': 'content_block_stop', 'index': i},
              ]
            else ...[
              {
                'type': 'content_block_start',
                'index': 0,
                'content_block': {'type': 'text', 'text': 'Done'},
              },
              {'type': 'content_block_stop', 'index': 0},
            ],
            {
              'type': 'message_delta',
              'delta': {
                'stop_reason': requests.length == 1 ? 'tool_use' : 'end_turn',
                'stop_sequence': null,
              },
              'usage': {'output_tokens': 1},
            },
            {'type': 'message_stop'},
          ];
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          for (final event in events) {
            request.response.write(
              'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
            );
          }
          await request.response.close();
        });
        final client = anthropic.AnthropicNativeClient.withApiKey(
          apiKey: 'fixture',
          baseUrl: 'http://127.0.0.1:${server.port}',
        );
        final executed = <String>[];
        String? idempotencyKey;
        AiAgent<Session> agent(String environment) => AiAgent<Session>(
          model: client.chatModel(model: 'fixture'),
          store: ServerpodRunStore(builder.build()),
          tools: [
            anthropic.AnthropicComputerTool<Session>(
              environmentId: environment,
              execute: (call, context) {
                expect(context.approved, isTrue);
                expect(context.toolCallId, call.id);
                idempotencyKey = context.idempotencyKey;
                executed.add(call.id);
                return anthropic.AnthropicComputerResult.error(
                  'fixture failure',
                );
              },
            ),
          ],
        );
        try {
          final paused = await agent('desktop-A').generate(
            ChatRequest(
              threadId: 'anthropic-computer-durable',
              runId: 'pause',
              messages: [ChatMessage.user('Inspect', id: 'user')],
            ),
            ownerId: 'anthropic-owner',
            context: builder.build(),
          );
          expect(paused.status, RunStatus.interrupted);
          expect(paused.interrupts, hasLength(2));
          expect(executed, isEmpty);
          expect(requests, hasLength(1));
          ChatRequest resume(String run) => ChatRequest(
            threadId: paused.threadId,
            runId: run,
            parentRunId: paused.runId,
            resume: [
              for (final interrupt in paused.interrupts) interrupt.approve(),
            ],
          );
          await expectLater(
            agent('desktop-B').generate(
              resume('wrong-environment'),
              ownerId: 'anthropic-owner',
              context: builder.build(),
            ),
            throwsA(isA<AgentRunException>()),
          );
          expect(executed, isEmpty);
          expect(requests, hasLength(1));
          final recreated = agent('desktop-A');
          final done = await recreated.generate(
            resume('resume'),
            ownerId: 'anthropic-owner',
            context: builder.build(),
          );
          expect(done.text, 'Done');
          expect(executed, ['call-key']);
          expect(idempotencyKey, isNotEmpty);
          expect(requests, hasLength(2));
          final messages = requests.last['messages'] as List;
          final assistant = messages[messages.length - 2] as Map;
          final replay = (assistant['content'] as List)
              .where((block) => block['type'] == 'tool_use')
              .toList();
          expect(replay, calls);
          final results = (messages.last as Map)['content'] as List;
          expect(results, hasLength(2));
          for (var i = 0; i < results.length; i++) {
            expect(results[i]['type'], 'tool_result');
            expect(results[i]['tool_use_id'], calls[i]['id']);
            expect(results[i]['toolset_name'], 'computer');
            expect(results[i]['is_error'], isTrue);
          }
          expect(
            jsonEncode(results.first['content']),
            contains('fixture failure'),
          );
          expect(
            results.last['content'],
            [
              {
                'type': 'text',
                'text':
                    'Not executed: an earlier computer action in this turn failed.',
              },
            ],
          );
          final state = await recreated.store.load(
            ownerId: 'anthropic-owner',
            threadId: paused.threadId,
          );
          expect(jsonEncode(state), contains('PRIVATE-KEY'));
          expect(jsonEncode(state), contains('PRIVATE-SHOT'));
          expect(
            jsonEncode(chatHydration(state)),
            isNot(contains('PRIVATE-KEY')),
          );
          expect(
            jsonEncode(chatHydration(state)),
            isNot(contains('PRIVATE-SHOT')),
          );
          await expectLater(
            recreated.generate(
              resume('duplicate'),
              ownerId: 'anthropic-owner',
              context: builder.build(),
            ),
            throwsA(isA<RunConflict>()),
          );
          expect(executed, ['call-key']);
          expect(requests, hasLength(2));
        } finally {
          client.close();
          await server.close(force: true);
        }
      },
    );
  });
}
