import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

Future<void> probe(
  String label,
  String code,
  Future<void> Function() run,
) async {
  try {
    await run();
    throw StateError('$label unexpectedly succeeded');
  } on AgentRunException catch (e) {
    if (e.code != code) {
      throw StateError('$label: expected $code got ${e.code} (${e.cause})');
    }
    print('PASS $label: ${e.code}, cause=${e.cause}, partial=${e.result.text}');
  }
}

final caps = ModelCapabilities(tools: true, structuredOutput: true);
const schema = {
  'type': 'object',
  'properties': <String, Object?>{},
  'additionalProperties': false,
};
Tool<Map<String, Object?>, String, void> failTool() => Tool(
  name: 'fail',
  description: 'fail',
  inputSchema: schema,
  outputSchema: const {'type': 'string'},
  decode: (j) => j,
  encode: (v) => v,
  execute: (v, c) => throw StateError('private tool detail'),
);
ScriptedChatModel calls() => ScriptedChatModel(
  capabilities: caps,
  steps: [
    [
      ToolCallReady(ToolCall(id: 'c', name: 'fail', arguments: {})),
      const ModelFinished(),
    ],
  ],
);
Future<void> main() async {
  await probe('no model terminal', 'MODEL_FAILED', () async {
    await generateText(
      model: ScriptedChatModel(
        steps: [
          [const TextDelta('partial')],
        ],
      ),
      prompt: 'hello',
    );
  });
  await probe('exhausted model', 'MODEL_FAILED', () async {
    await generateText(
      model: ScriptedChatModel(steps: []),
      prompt: 'hello',
    );
  });
  await probe('tool exception', 'TOOL_FAILED', () async {
    await AiAgent<void>(model: calls(), tools: [failTool()]).generate(
      ChatRequest(
        threadId: 't',
        runId: 'r',
        messages: [ChatMessage.user('go', id: 'm')],
      ),
      ownerId: 'o',
      context: null,
    );
  });
  await probe('step limit', 'STEP_LIMIT', () async {
    await AiAgent<void>(
      model: calls(),
      tools: [
        Tool<Map<String, Object?>, String, void>(
          name: 'fail',
          description: 'ok',
          inputSchema: schema,
          outputSchema: const {'type': 'string'},
          decode: (j) => j,
          encode: (v) => v,
          execute: (v, c) => 'ok',
        ),
      ],
      maxSteps: 1,
    ).generate(
      ChatRequest(
        threadId: 't',
        runId: 'r',
        messages: [ChatMessage.user('go', id: 'm')],
      ),
      ownerId: 'o',
      context: null,
    );
  });
}
