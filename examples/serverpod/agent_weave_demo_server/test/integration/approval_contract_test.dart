import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

const minimum = 9007199254740992;
const changedMinimum = 9007199254740993;
const accepted = 9007199254740994;
const integerKey = '9007199254740993';

void main() {
  withServerpod('Approval contract PostgreSQL recreation', (builder, _) {
    for (final changedPart in ['input', 'output']) {
      test(
        'rejects changed $changedPart schema and preserves approval',
        () async {
          var executions = 0;
          JsonObject inputSchema(int value) => {
            'type': 'object',
            'properties': {
              'value': {'type': 'integer', 'minimum': value},
              integerKey: {'type': 'integer', 'const': accepted},
            },
            'required': ['value', integerKey],
          };
          JsonObject outputSchema(int value) => {
            'type': 'integer',
            'minimum': value,
          };
          ScriptedChatModel initial() => ScriptedChatModel(
            capabilities: const ModelCapabilities(tools: true),
            steps: [
              [
                ToolCallReady(
                  ToolCall(
                    id: 'call',
                    name: 'large',
                    arguments: {'value': accepted, integerKey: accepted},
                  ),
                ),
                const ModelFinished('tool_calls'),
              ],
            ],
          );
          ScriptedChatModel followup() => ScriptedChatModel(
            capabilities: const ModelCapabilities(tools: true),
            steps: [
              [const TextDelta('done'), const ModelFinished()],
            ],
          );
          AiAgent<void> agent(
            ChatModel model, {
            int input = minimum,
            int output = minimum,
          }) => AiAgent<void>(
            store: ServerpodRunStore(builder.build()),
            model: model,
            tools: [
              Tool<int, int, void>(
                name: 'large',
                description: 'Large integer fixture',
                inputSchema: inputSchema(input),
                outputSchema: outputSchema(output),
                needsApproval: true,
                decode: (json) => json['value'] as int,
                encode: (value) => value,
                execute: (value, _) {
                  executions++;
                  return value;
                },
              ),
            ],
          );
          final thread = 'contract-$changedPart';
          final paused = await agent(initial()).generate(
            ChatRequest(
              threadId: thread,
              runId: 'pause',
              messages: [ChatMessage.user('start', id: 'u')],
            ),
            ownerId: 'owner',
            context: null,
          );
          expect(paused.status, RunStatus.interrupted);
          expect(executions, 0);
          final saved = await ServerpodRunStore(
            builder.build(),
          ).load(ownerId: 'owner', threadId: thread);
          final pending = (saved!['pending'] as List).single as Map;
          final contract = pending['toolContract'];
          expect(contract, isNotNull);
          final encoded = jsonEncode(contract);
          expect(encoded, contains('"minimum":$minimum'));
          expect(encoded, contains('"$integerKey"'));
          expect(encoded, contains('"const":$accepted'));
          expect((jsonDecode(encoded) as Map).toString(), contains(integerKey));
          ChatRequest resume(String runId) => ChatRequest(
            threadId: thread,
            runId: runId,
            parentRunId: paused.runId,
            resume: [paused.interrupts.single.approve()],
          );
          final rejectedModel = followup();
          await expectLater(
            agent(
              rejectedModel,
              input: changedPart == 'input' ? changedMinimum : minimum,
              output: changedPart == 'output' ? changedMinimum : minimum,
            ).generate(resume('reject'), ownerId: 'owner', context: null),
            throwsA(
              isA<AgentRunException>()
                  .having((error) => error.code, 'code', 'INVALID_INPUT')
                  .having(
                    (error) => error.cause,
                    'cause',
                    isA<FormatException>(),
                  )
                  .having(
                    (error) => error.message,
                    'message',
                    'Execution configuration changed. Start a new conversation.',
                  ),
            ),
          );
          expect(executions, 0);
          expect(rejectedModel.requests, isEmpty);
          final after = await ServerpodRunStore(
            builder.build(),
          ).load(ownerId: 'owner', threadId: thread);
          expect((after!['pending'] as List), hasLength(1));
          expect((after['pending'] as List).single['toolContract'], contract);
          final finalModel = followup();
          final result = await agent(
            finalModel,
          ).generate(resume('resume'), ownerId: 'owner', context: null);
          expect(result.text, 'done');
          expect(executions, 1);
          expect(finalModel.requests, hasLength(1));
        },
      );
    }
  });
}
