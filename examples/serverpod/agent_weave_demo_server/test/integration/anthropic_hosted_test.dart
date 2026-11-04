import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';
import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Anthropic hosted PostgreSQL continuation', (builder, _) {
    test(
      'reloads a paused turn, preserves container and isolates owner',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Map<String, dynamic>>[];
        final call = <String, Object?>{
          'type': 'server_tool_use',
          'id': 'hosted',
          'name': 'code_execution',
          'input': {'code': 'print(42)'},
          'private': 'OPAQUE',
        };
        server.listen((request) async {
          requests.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          final blocks = requests.length == 1
              ? [call]
              : <Map<String, Object?>>[
                  {
                    'type': 'code_execution_tool_result',
                    'tool_use_id': 'hosted',
                    'content': {
                      'type': 'code_execution_result',
                      'stdout': '42',
                      'stderr': '',
                      'return_code': 0,
                      'content': [],
                    },
                  },
                  {'type': 'text', 'text': '{"answer":42}'},
                ];
          final events = <Map<String, Object?>>[
            {
              'type': 'message_start',
              'message': {
                'id': 'm',
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
              'delta': {
                'stop_reason': requests.length == 1 ? 'pause_turn' : 'end_turn',
                'container': {'id': 'private-container'},
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
            request.response.write('data: ${jsonEncode(event)}\n\n');
          }
          await request.response.close();
        });
        final client = api.AnthropicNativeClient.withApiKey(
          apiKey: 'fixture',
          baseUrl: 'http://127.0.0.1:${server.port}',
        );
        AiAgent<void> agent() => AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          maxSteps: 1,
          outputSchema: {
            'type': 'object',
            'properties': {
              'answer': {'type': 'integer'},
            },
            'required': ['answer'],
          },
          model: client.chatModel(
            model: 'fixture',
            hostedTools: [
              api.AnthropicHostedTool(api.CodeExecutionBuiltInTool()),
            ],
          ),
        );
        try {
          final first = agent();
          final events = await first
              .run(
                ChatRequest(
                  threadId: 'paused-hosted',
                  runId: 'first',
                  messages: [ChatMessage.user('Compute', id: 'u')],
                ),
                ownerId: 'owner',
                context: null,
              )
              .toList();
          expect(events.last.json['code'], 'STEP_LIMIT');
          final saved = await first.store.load(
            ownerId: 'owner',
            threadId: 'paused-hosted',
          );
          expect(saved!['providerContinuationPending'], true);
          final fresh = agent();
          expect(
            await fresh.store.load(ownerId: 'other', threadId: 'paused-hosted'),
            isNull,
          );
          final rejected = await fresh
              .run(
                ChatRequest(
                  threadId: 'paused-hosted',
                  runId: 'invalid',
                  messages: [ChatMessage.user('New', id: 'new')],
                ),
                ownerId: 'owner',
                context: null,
              )
              .toList();
          expect(rejected.last.json['code'], 'INVALID_INPUT');
          expect(requests, hasLength(1));
          final result = await agent().generate(
            ChatRequest(threadId: 'paused-hosted', runId: 'continue'),
            ownerId: 'owner',
            context: null,
          );
          expect(result.output, {'answer': 42});
          expect(requests, hasLength(2));
          expect(requests.last['container'], 'private-container');
          expect(requests.last['tools'], requests.first['tools']);
          expect((requests.last['messages'] as List).last['content'], [call]);
          final finished = await agent().store.load(
            ownerId: 'owner',
            threadId: 'paused-hosted',
          );
          expect(finished!['providerContinuationPending'], isNull);
          final parts = (chatHydration(finished)['messages'] as List).expand(
            (m) => (m as Map)['parts'] as List,
          );
          expect(
            parts.singleWhere(
              (p) => (p as Map)['type'] == 'structured-output',
            )['data'],
            {'answer': 42},
          );
          expect(jsonEncode(finished), contains('OPAQUE'));
          expect(
            jsonEncode(chatHydration(finished)),
            isNot(contains('OPAQUE')),
          );
          expect(
            jsonEncode(chatHydration(finished)),
            isNot(contains('private-container')),
          );
        } finally {
          client.close();
          await server.close(force: true);
        }
      },
    );
  });
}
