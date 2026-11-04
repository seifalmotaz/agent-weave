import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';
import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod('OpenAI MCP PostgreSQL approval', (builder, _) {
    for (final approved in [true, false]) {
      test(
        'recreates and ${approved ? 'approves' : 'rejects'} privately',
        () async {
          final requests = <JsonObject>[];
          final nativeRequest = <String, Object?>{
            'type': 'mcp_approval_request',
            'id': 'PRIVATE-PROVIDER-ID',
            'server_label': 'docs',
            'name': 'write',
            'arguments': '{"text":"hello"}',
            'opaque': 'PRIVATE-OPAQUE',
          };
          AiAgent<void> agent({bool changed = false}) => AiAgent<void>(
            store: ServerpodRunStore(builder.build()),
            model: api.ResponsesProtocolModel.native(
              authorityBindingId: 'fixture-provider-account',
              model: 'fixture',
              mcpTools: [
                api.OpenAIMcpTool.fromJson({
                  'type': 'mcp',
                  'server_label': 'docs',
                  'server_url': changed
                      ? 'https://changed.example/mcp'
                      : 'https://example.com/mcp',
                  'require_approval': 'always',
                  'authorization': 'PRIVATE-CREDENTIAL',
                }, credentialBindingId: 'owner-binding'),
              ],
              transport: (body, _) async* {
                requests.add(immutableJson(body));
                yield {
                  'type': 'response.completed',
                  'response': {
                    'status': 'completed',
                    'model': 'fixture',
                    'output': requests.length == 1
                        ? [nativeRequest]
                        : [
                            {
                              'id': 'final-message',
                              'type': 'message',
                              'role': 'assistant',
                              'status': 'completed',
                              'content': [
                                {
                                  'type': 'output_text',
                                  'text': 'Done',
                                  'annotations': [],
                                },
                              ],
                            },
                          ],
                  },
                };
              },
            ),
          );
          final thread = 'mcp-$approved';
          final first = agent();
          final paused = await first.generate(
            ChatRequest(
              threadId: thread,
              runId: 'first',
              messages: [ChatMessage.user('Write', id: 'u')],
            ),
            ownerId: 'owner',
            context: null,
          );
          expect(paused.status, RunStatus.interrupted);
          expect(paused.interrupts, hasLength(1));
          final interrupt = paused.interrupts.single;
          expect(interrupt.call, isA<ProviderApprovalCall>());
          final answer = approved ? interrupt.approve() : interrupt.reject();
          final fresh = agent();
          expect(
            await fresh.store.load(ownerId: 'other', threadId: thread),
            isNull,
          );
          final foreign = await fresh
              .run(
                ChatRequest(
                  threadId: thread,
                  runId: 'foreign',
                  resume: [answer],
                ),
                ownerId: 'other',
                context: null,
              )
              .toList();
          expect(foreign.last.type, 'RUN_ERROR');
          final changed = await agent(changed: true)
              .run(
                ChatRequest(
                  threadId: thread,
                  runId: 'changed',
                  parentRunId: 'first',
                  resume: [answer],
                ),
                ownerId: 'owner',
                context: null,
              )
              .toList();
          expect(changed.last.type, 'RUN_ERROR');
          expect(requests, hasLength(1));
          final saved = (await fresh.store.load(
            ownerId: 'owner',
            threadId: thread,
          ))!;
          final public = jsonEncode(chatHydration(saved));
          final journal = await fresh.store.events(
            ownerId: 'owner',
            threadId: thread,
            runId: 'first',
          );
          for (final secret in [
            'PRIVATE-PROVIDER-ID',
            'PRIVATE-OPAQUE',
            'PRIVATE-CREDENTIAL',
          ]) {
            expect(public, isNot(contains(secret)));
            expect(jsonEncode(journal), isNot(contains(secret)));
          }
          expect(journal.first['type'], 'RUN_STARTED');
          expect(journal.last['type'], 'RUN_FINISHED');
          final result = await agent().generate(
            ChatRequest(
              threadId: thread,
              runId: 'resume',
              parentRunId: 'first',
              resume: [answer],
            ),
            ownerId: 'owner',
            context: null,
          );
          expect(result.status, RunStatus.completed);
          expect(requests, hasLength(2));
          final input = requests.last['input'] as List;
          final index = input.indexWhere(
            (item) => item['type'] == 'mcp_approval_request',
          );
          expect(index, greaterThanOrEqualTo(0));
          expect(input[index], nativeRequest);
          expect(input[index + 1], {
            'type': 'mcp_approval_response',
            'approval_request_id': 'PRIVATE-PROVIDER-ID',
            'approve': approved,
          });
          final completed = await agent().store.events(
            ownerId: 'owner',
            threadId: thread,
            runId: 'resume',
          );
          expect(completed.first['type'], 'RUN_STARTED');
          expect(completed.last['type'], 'RUN_FINISHED');
          final finalState = await agent().store.load(
            ownerId: 'owner',
            threadId: thread,
          );
          expect(
            jsonEncode(chatHydration(finalState)),
            isNot(contains('PRIVATE-CREDENTIAL')),
          );
        },
      );
    }
    test(
      'indeterminate provider execution survives recreation and blocks retry',
      () async {
        var requests = 0;
        AiAgent<void> agent() => AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          model: api.ResponsesProtocolModel.native(
            authorityBindingId: 'fixture-provider-account',
            model: 'fixture',
            mcpTools: [
              api.OpenAIMcpTool.fromJson({
                'type': 'mcp',
                'server_label': 'docs',
                'server_url': 'https://example.com/mcp',
                'require_approval': 'always',
              }),
            ],
            transport: (body, _) async* {
              requests++;
              throw StateError('offline fixture failure');
            },
          ),
        );
        final first = await agent()
            .run(
              ChatRequest(
                threadId: 'mcp-uncertain',
                runId: 'first',
                messages: [ChatMessage.user('Write', id: 'u')],
              ),
              ownerId: 'owner',
              context: null,
            )
            .toList();
        expect(first.last.type, 'RUN_ERROR');
        final fresh = agent();
        final saved = await fresh.store.load(
          ownerId: 'owner',
          threadId: 'mcp-uncertain',
        );
        expect(saved!['providerApprovalIndeterminate'], true);
        final retry = await fresh
            .run(
              ChatRequest(
                threadId: 'mcp-uncertain',
                runId: 'retry',
                parentRunId: 'first',
              ),
              ownerId: 'owner',
              context: null,
            )
            .toList();
        expect(retry.last.type, 'RUN_ERROR');
        expect(requests, 1);
      },
    );
  });
}
