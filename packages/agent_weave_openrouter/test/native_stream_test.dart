import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

String sse(List<Map<String, Object?>> events) =>
    '${events.map((event) => 'data: ${jsonEncode(event)}\n\n').join()}data: [DONE]\n\n';

void main() {
  test(
    'native stream uses OpenRouter SSE once and keeps provider data in result',
    () async {
      var requests = 0;
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'fixture',
        httpClient: MockClient((request) async {
          requests++;
          expect(request.url.path, '/api/v1/chat/completions');
          return http.Response(
            sse([
              {
                'model': 'actual/model',
                'provider': 'private-provider',
                'choices': [
                  {
                    'index': 0,
                    'delta': {
                      'content': 'Hello ',
                      'reasoning_details': [
                        {
                          'type': 'reasoning.encrypted',
                          'data': 'private-reasoning',
                        },
                      ],
                    },
                    'finish_reason': null,
                  },
                ],
              },
              {
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': 'world'},
                    'finish_reason': 'stop',
                  },
                ],
                'usage': {
                  'prompt_tokens': 3,
                  'completion_tokens': 2,
                  'cost': 0.0123,
                },
              },
            ]),
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      addTearDown(client.close);
      final updates = await streamText(
        model: router.OpenRouterChatModel(client: client, model: 'fixture'),
        prompt: 'hello',
      ).toList();
      expect(requests, 1);
      expect(
        updates.every(
          (update) =>
              update is AgentTextDelta ||
              update is AgentUsage ||
              update is AgentRunFinished,
        ),
        isTrue,
      );
      expect(
        updates.whereType<AgentTextDelta>().map((e) => e.text).join(),
        'Hello world',
      );
      final usage = updates.whereType<AgentUsage>().single.usage;
      expect(usage.inputTokens, 3);
      expect(usage.outputTokens, 2);
      expect(usage.model, 'actual/model');
      final result = (updates.last as AgentRunFinished).result;
      expect(result.text, 'Hello world');
      final data = result.responseMessages.single.providerData;
      expect(
        data['openrouter.chat.reasoning']!.single['data'],
        'private-reasoning',
      );
      expect(
        data['openrouter.chat.metadata']!.single['provider'],
        'private-provider',
      );
      expect(
        (data['openrouter.chat.metadata']!.single['usage'] as Map)['cost'],
        0.0123,
      );
      expect(
        updates.take(updates.length - 1).whereType<AgentRunFinished>(),
        isEmpty,
      );
    },
  );

  test(
    'approval resumes once and replays assistant call and tool result',
    () async {
      final bodies = <Map<String, dynamic>>[];
      var effects = 0;
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'fixture',
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (bodies.length == 1) {
            return http.Response(
              sse([
                {
                  'choices': [
                    {
                      'index': 0,
                      'delta': {
                        'tool_calls': [
                          {
                            'index': 0,
                            'id': 'call-1',
                            'type': 'function',
                            'function': {
                              'name': 'double',
                              'arguments': '{"count":2}',
                            },
                          },
                        ],
                      },
                      'finish_reason': 'tool_calls',
                    },
                  ],
                },
              ]),
              200,
            );
          }
          return http.Response(
            sse([
              {
                'choices': [
                  {
                    'index': 0,
                    'delta': {'content': 'done'},
                    'finish_reason': 'stop',
                  },
                ],
              },
            ]),
            200,
          );
        }),
      );
      addTearDown(client.close);
      final agent = AiAgent<void>(
        model: router.OpenRouterChatModel(client: client, model: 'fixture'),
        tools: [
          Tool<int, int, void>(
            name: 'double',
            description: 'Double',
            inputSchema: const {
              'type': 'object',
              'properties': {
                'count': {'type': 'integer'},
              },
              'required': ['count'],
            },
            outputSchema: const {'type': 'integer'},
            needsApproval: true,
            decode: (input) => input['count'] as int,
            encode: (value) => value,
            execute: (value, _) {
              effects++;
              return value * 2;
            },
          ),
        ],
      );
      final first = await agent
          .stream(
            ChatRequest(
              threadId: 'thread',
              runId: 'first',
              messages: [ChatMessage.user('double', id: 'user')],
            ),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      expect(first.whereType<AgentToolCallReady>().single.call.id, 'call-1');
      final paused = (first.last as AgentRunFinished).result;
      expect(paused.status, RunStatus.interrupted);
      expect(effects, 0);
      final next = await agent
          .stream(
            ChatRequest(
              threadId: 'thread',
              runId: 'next',
              parentRunId: 'first',
              resume: [paused.interrupts.single.approve()],
            ),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      expect(effects, 1);
      expect(bodies.length, 2);
      expect(next.whereType<AgentToolResult>().single.result, 4);
      expect((next.last as AgentRunFinished).result.text, 'done');
      final messages = bodies.last['messages'] as List;
      final assistant =
          messages.singleWhere((m) => m['role'] == 'assistant') as Map;
      final tool = messages.singleWhere((m) => m['role'] == 'tool') as Map;
      expect(assistant['tool_calls'][0]['id'], 'call-1');
      expect(
        assistant['tool_calls'][0]['function']['arguments'],
        '{"count":2}',
      );
      expect(tool['tool_call_id'], 'call-1');
      expect(tool['content'], '4');
    },
  );
}
