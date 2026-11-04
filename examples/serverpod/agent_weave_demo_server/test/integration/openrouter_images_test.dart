import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

const png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';

void main() {
  withServerpod('OpenRouter image PostgreSQL approval', (builder, _) {
    test(
      'replays private images and tool call after recreated approval',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Map<String, dynamic>>[];
        final images = [
          {
            'image_url': {'url': png},
            'private_signature': 'PRIVATE-IMAGE',
          },
        ];
        final toolCall = {
          'id': 'call-1',
          'type': 'function',
          'function': {'name': 'double', 'arguments': '{"value":21}'},
        };
        server.listen((request) async {
          requests.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'id': 'fixture',
              'object': 'chat.completion',
              'created': 0,
              'model': 'fixture',
              'choices': [
                {
                  'index': 0,
                  'message': requests.length == 1
                      ? {
                          'role': 'assistant',
                          'content': 'Caption',
                          'images': images,
                          'tool_calls': [toolCall],
                        }
                      : {'role': 'assistant', 'content': '42'},
                  'finish_reason': requests.length == 1 ? 'tool_calls' : 'stop',
                },
              ],
            }),
          );
          await request.response.close();
        });
        final client = router.OpenRouterClient.withApiKey(
          apiKey: 'fixture',
          baseUrl: 'http://127.0.0.1:${server.port}',
        );
        var calls = 0;
        AiAgent<void> agent() => AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          model: router.OpenRouterChatModel(
            client: client,
            model: 'fixture',
            options: router.OpenRouterChatOptions(
              modalities: [
                router.OpenRouterOutputModality.text,
                router.OpenRouterOutputModality.image,
              ],
            ),
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
              needsApproval: true,
              decode: (json) => json['value'] as int,
              encode: (value) => value,
              execute: (value, _) {
                calls++;
                return value * 2;
              },
            ),
          ],
        );
        try {
          final paused = await agent().generate(
            ChatRequest(
              threadId: 'openrouter-image',
              runId: 'pause',
              messages: [ChatMessage.user('Draw and double', id: 'u')],
            ),
            ownerId: 'owner',
            context: null,
          );
          expect(paused.status, RunStatus.interrupted);
          expect(calls, 0);
          expect(requests, hasLength(1));
          final store = ServerpodRunStore(builder.build());
          expect(
            await store.load(ownerId: 'other', threadId: 'openrouter-image'),
            isNull,
          );
          final state = await store.load(
            ownerId: 'owner',
            threadId: 'openrouter-image',
          );
          expect(jsonEncode(state), contains('PRIVATE-IMAGE'));
          final hydration = jsonEncode(chatHydration(state));
          expect(hydration, contains(png));
          expect(hydration, isNot(contains('PRIVATE-IMAGE')));
          final resumed = await agent().generate(
            ChatRequest(
              threadId: 'openrouter-image',
              runId: 'resume',
              parentRunId: paused.runId,
              resume: [paused.interrupts.single.approve()],
            ),
            ownerId: 'owner',
            context: null,
          );
          expect(resumed.text, '42');
          expect(calls, 1);
          expect(requests, hasLength(2));
          final messages = (requests.last['messages'] as List).cast<Map>();
          final assistant = messages.singleWhere(
            (message) => message['role'] == 'assistant',
          );
          expect(assistant['images'], images);
          expect(assistant['tool_calls'], [toolCall]);
          final result = messages.singleWhere(
            (message) => message['role'] == 'tool',
          );
          expect(result['tool_call_id'], 'call-1');
          expect(result['content'], '42');
          final reloaded = await ServerpodRunStore(
            builder.build(),
          ).load(ownerId: 'owner', threadId: 'openrouter-image');
          final finalHydration = jsonEncode(chatHydration(reloaded));
          expect(finalHydration, contains(png));
          expect(finalHydration, contains('42'));
          expect(finalHydration, isNot(contains('PRIVATE-IMAGE')));
        } finally {
          client.close();
          await server.close(force: true);
        }
      },
    );
  });
}
