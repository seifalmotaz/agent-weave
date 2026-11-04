import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

const customCall = <String, Object?>{
  'type': 'custom_tool_call',
  'id': 'custom-item',
  'call_id': 'custom-call',
  'name': 'execute',
  'namespace': 'sandbox',
  'input': 'α\nraw text',
  'status': 'completed',
  'caller': {'type': 'direct'},
  'opaque': 'PRIVATE-CUSTOM',
};
const functionCall = <String, Object?>{
  'type': 'function_call',
  'id': 'function-item',
  'call_id': 'function-call',
  'name': 'double',
  'arguments': '{"value":21}',
  'status': 'completed',
};
const privateReasoning = <String, Object?>{
  'type': 'reasoning',
  'id': 'reasoning-item',
  'summary': <Object?>[],
  'encrypted_content': 'PRIVATE-ENCRYPTED',
};

void main() {
  withServerpod('OpenAI custom tools PostgreSQL', (builder, _) {
    for (final mode in ['approve-text', 'approve-list', 'reject', 'cancel']) {
      test('recreated mixed approval: $mode', () async {
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => upstream.close(force: true));
        final requests = <JsonObject>[];
        upstream.listen((request) async {
          requests.add(
            Map<String, Object?>.from(
              jsonDecode(await utf8.decoder.bind(request).join()) as Map,
            ),
          );
          final output = requests.length == 1
              ? [privateReasoning, customCall, functionCall]
              : <JsonObject>[];
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.write(
            'data: ${jsonEncode({
              'type': 'response.completed',
              'response': {'status': 'completed', 'model': 'fixture', 'output': output},
            })}\n\ndata: [DONE]\n\n',
          );
          await request.response.close();
        });
        final client = api.OpenAIClient(
          config: api.OpenAIConfig(
            baseUrl: 'http://127.0.0.1:${upstream.port}/v1',
            authProvider: const api.ApiKeyProvider('fixture'),
          ),
        );
        addTearDown(client.close);
        var customEffects = 0, functionEffects = 0;
        AiAgent<void> agent() => AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          model: api.OpenAIResponsesModel(client: client, model: 'fixture'),
          tools: [
            api.OpenAICustomTool<void>(
              name: 'execute',
              localName: 'sandbox_execute',
              namespace: api.OpenAIToolNamespace(
                name: 'sandbox',
                description: 'Sandbox tools',
              ),
              bindingId: 'custom-binding',
              needsApproval: true,
              execute: (input, _) {
                customEffects++;
                expect(input, 'α\nraw text');
                return mode == 'approve-list'
                    ? api.OpenAICustomToolResult.content([
                        api.OpenAICustomToolContent.text('result list'),
                      ])
                    : api.OpenAICustomToolResult.text('raw\nresult');
              },
            ),
            Tool<int, int, void>(
              name: 'double',
              description: 'Double',
              needsApproval: true,
              inputSchema: const {
                'type': 'object',
                'properties': {
                  'value': {'type': 'integer'},
                },
                'required': ['value'],
              },
              outputSchema: const {'type': 'integer'},
              decode: (v) => v['value'] as int,
              encode: (v) => v,
              execute: (v, _) {
                functionEffects++;
                return v * 2;
              },
            ),
          ],
        );
        final thread = 'custom-$mode';
        final first = await agent().generate(
          ChatRequest(
            threadId: thread,
            runId: 'first',
            messages: [ChatMessage.user('Run', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(first.status, RunStatus.interrupted);
        final custom = first.interrupts.singleWhere(
          (i) => i.call.name == 'sandbox_execute',
        );
        final function = first.interrupts.singleWhere(
          (i) => i.call.name == 'double',
        );
        expect(custom.call.arguments, {'input': 'α\nraw text'});
        expect(customEffects, 0);
        expect(functionEffects, 0);
        expect(requests, hasLength(1));
        final stored = await agent().store.load(
          ownerId: 'owner',
          threadId: thread,
        );
        final journal = await agent().store.events(
          ownerId: 'owner',
          threadId: thread,
          runId: 'first',
        );
        expect(jsonEncode(stored), contains('PRIVATE-CUSTOM'));
        expect(jsonEncode(chatHydration(stored)), isNot(contains('"caller"')));
        expect(jsonEncode(journal), isNot(contains('"caller"')));
        for (final private in ['PRIVATE-CUSTOM', 'PRIVATE-ENCRYPTED']) {
          expect(jsonEncode(chatHydration(stored)), isNot(contains(private)));
          expect(jsonEncode(journal), isNot(contains(private)));
        }
        final decision = switch (mode) {
          'reject' => custom.reject(),
          'cancel' => custom.cancel(),
          _ => custom.approve(),
        };
        final result = await agent().generate(
          ChatRequest(
            threadId: thread,
            runId: 'resume',
            parentRunId: 'first',
            resume: [decision, function.approve()],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(result.status, RunStatus.completed);
        expect(customEffects, mode.startsWith('approve') ? 1 : 0);
        expect(functionEffects, 1);
        expect(requests, hasLength(2));
        final input = requests.last['input'] as List;
        expect(
          input.whereType<Map>().singleWhere(
            (v) => v['type'] == 'custom_tool_call',
          ),
          customCall,
        );
        expect(
          input.whereType<Map>().singleWhere((v) => v['type'] == 'reasoning'),
          privateReasoning,
        );
        final output = input.whereType<Map>().singleWhere(
          (v) => v['type'] == 'custom_tool_call_output',
        );
        expect(output['call_id'], 'custom-call');
        expect(output['output'], switch (mode) {
          'approve-text' => 'raw\nresult',
          'approve-list' => [
            {'type': 'input_text', 'text': 'result list'},
          ],
          'reject' => 'Tool call declined.',
          _ => 'Tool call cancelled.',
        });
        expect(
          input.whereType<Map>().singleWhere(
            (v) => v['type'] == 'function_call_output',
          )['call_id'],
          'function-call',
        );
      });
    }
    test(
      'function approval rejects changed custom binding or grammar before effects',
      () async {
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => upstream.close(force: true));
        final requests = <JsonObject>[];
        upstream.listen((request) async {
          requests.add(
            Map<String, Object?>.from(
              jsonDecode(await utf8.decoder.bind(request).join()) as Map,
            ),
          );
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );
          request.response.write(
            'data: ${jsonEncode({
              'type': 'response.completed',
              'response': {
                'status': 'completed',
                'output': requests.length == 1 ? [functionCall] : <JsonObject>[],
              },
            })}\n\ndata: [DONE]\n\n',
          );
          await request.response.close();
        });
        final client = api.OpenAIClient(
          config: api.OpenAIConfig(
            baseUrl: 'http://127.0.0.1:${upstream.port}/v1',
            authProvider: const api.ApiKeyProvider('fixture'),
          ),
        );
        addTearDown(client.close);
        var effects = 0;
        AiAgent<void> agent({String variation = 'same'}) => AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          model: api.OpenAIResponsesModel(client: client, model: 'fixture'),
          tools: [
            api.OpenAICustomTool<void>(
              name: 'execute',
              localName: 'sandbox_execute',
              namespace: api.OpenAIToolNamespace(
                name: 'sandbox',
                description: 'Sandbox tools',
              ),
              bindingId: variation == 'binding' ? 'changed' : 'original',
              format: api.OpenAICustomToolFormat.grammar(
                variation == 'grammar' ? '[a-z]+' : '[0-9]+',
                syntax: api.OpenAICustomGrammarSyntax.regex,
              ),
              execute: (_, _) => api.OpenAICustomToolResult.text('ok'),
            ),
            Tool<int, int, void>(
              name: 'double',
              description: 'Double',
              needsApproval: true,
              inputSchema: const {
                'type': 'object',
                'properties': {
                  'value': {'type': 'integer'},
                },
                'required': ['value'],
              },
              outputSchema: const {'type': 'integer'},
              decode: (v) => v['value'] as int,
              encode: (v) => v,
              execute: (v, _) {
                effects++;
                return v * 2;
              },
            ),
          ],
        );
        final first = await agent().generate(
          ChatRequest(
            threadId: 'custom-drift',
            runId: 'first',
            messages: [ChatMessage.user('Run', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(first.interrupts, hasLength(1));
        final answer = first.interrupts.single.approve();
        final original = await agent().store.load(
          ownerId: 'owner',
          threadId: 'custom-drift',
        );
        for (final variation in ['binding', 'grammar']) {
          await expectLater(
            agent(variation: variation).generate(
              ChatRequest(
                threadId: 'custom-drift',
                runId: 'bad-$variation',
                parentRunId: 'first',
                resume: [answer],
              ),
              ownerId: 'owner',
              context: null,
            ),
            throwsA(isA<AgentRunException>()),
          );
          expect(effects, 0);
          expect(requests, hasLength(1));
          expect(
            await agent().store.load(
              ownerId: 'owner',
              threadId: 'custom-drift',
            ),
            original,
          );
        }
        final done = await agent().generate(
          ChatRequest(
            threadId: 'custom-drift',
            runId: 'resume',
            parentRunId: 'first',
            resume: [answer],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(done.status, RunStatus.completed);
        expect(effects, 1);
        expect(requests, hasLength(2));
      },
    );
  });
}
