import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('Model continuation PostgreSQL contracts', (builder, _) {
    test(
      'recreated local approval rejects provider drift before effects',
      () async {
        var requests = 0;
        var effects = 0;
        var token = 'PRIVATE-FIRST-TOKEN';
        final authorizations = <Object?>[];
        const nativeCall = <String, Object?>{
          'type': 'function_call',
          'id': 'item',
          'call_id': 'local-call',
          'name': 'escalate',
          'arguments': '{}',
          'status': 'completed',
        };
        AiAgent<void> agent({String variation = 'same'}) => AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          tools: [
            Tool<JsonObject, String, void>(
              name: 'escalate',
              description: 'Escalate a ticket',
              needsApproval: true,
              inputSchema: const {'type': 'object'},
              outputSchema: const {'type': 'string'},
              decode: (json) => json,
              encode: (value) => value,
              execute: (_, context) {
                expect(context.approved, true);
                effects++;
                return 'Escalated';
              },
            ),
          ],
          model: api.ResponsesProtocolModel.native(
            authorityBindingId: variation == 'authority'
                ? 'changed-provider-account'
                : 'fixture-provider-account',
            options: {'temperature': variation == 'options' ? 0.4 : 0.2},
            toolChoice: variation == 'choice' ? 'none' : 'auto',
            model: variation == 'model' ? 'different-model' : 'fixture',
            hostedTools: variation == 'hosted'
                ? [
                    api.OpenAIHostedTool.fromJson({'type': 'web_search'}),
                  ]
                : const [],
            mcpTools: [
              api.OpenAIMcpTool.fromJson(
                {
                  'type': 'mcp',
                  'server_label': 'support',
                  'server_url': variation == 'server'
                      ? 'https://changed.example.invalid/mcp'
                      : 'https://support.example.invalid/mcp',
                  'allowed_tools': [
                    variation == 'allowlist' ? 'write' : 'read',
                  ],
                  'require_approval': 'always',
                },
                credentialBindingId: variation == 'binding' ? 'other' : 'owner',
                credentials: () =>
                    api.OpenAIMcpCredentials(authorization: token),
              ),
            ],
            transport: (body, _) async* {
              requests++;
              authorizations.add(
                (body['tools'] as List).singleWhere(
                  (tool) => tool['type'] == 'mcp',
                )['authorization'],
              );
              yield {
                'type': 'response.completed',
                'response': {
                  'status': 'completed',
                  'output': requests == 1 ? [nativeCall] : <Object?>[],
                },
              };
            },
          ),
        );
        final first = await agent().generate(
          ChatRequest(
            threadId: 'local-mcp',
            runId: 'first',
            messages: [ChatMessage.user('Escalate', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(first.status, RunStatus.interrupted);
        final answer = first.interrupts.single.approve();
        final original = await agent().store.load(
          ownerId: 'owner',
          threadId: 'local-mcp',
        );
        for (final variation in [
          'server',
          'allowlist',
          'binding',
          'model',
          'hosted',
          'authority',
          'options',
          'choice',
        ]) {
          await expectLater(
            agent(variation: variation).generate(
              ChatRequest(
                threadId: 'local-mcp',
                runId: 'changed-$variation',
                parentRunId: 'first',
                resume: [answer],
              ),
              ownerId: 'owner',
              context: null,
            ),
            throwsA(isA<AgentRunException>()),
          );
          expect(effects, 0);
          expect(requests, 1);
          expect(
            await agent().store.load(ownerId: 'owner', threadId: 'local-mcp'),
            original,
          );
        }
        token = 'PRIVATE-ROTATED-TOKEN';
        final completed = await agent().generate(
          ChatRequest(
            threadId: 'local-mcp',
            runId: 'resume',
            parentRunId: 'first',
            resume: [answer],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(completed.status, RunStatus.completed);
        expect(effects, 1);
        expect(requests, 2);
        expect(authorizations, [
          'PRIVATE-FIRST-TOKEN',
          'PRIVATE-ROTATED-TOKEN',
        ]);
        final saved = await agent().store.load(
          ownerId: 'owner',
          threadId: 'local-mcp',
        );
        expect(jsonEncode(saved), isNot(contains('PRIVATE-')));
        expect(
          jsonEncode(chatHydration(saved)),
          isNot(contains('credential_binding_id')),
        );
      },
    );
  });
}
