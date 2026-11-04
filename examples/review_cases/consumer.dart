import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

const schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'answer': {'type': 'integer'},
  },
  'required': ['answer'],
  'additionalProperties': false,
};
const capabilities = ModelCapabilities(tools: true, structuredOutput: true);

Future<void> main() async {
  final text = await generateText(
    model: ScriptedChatModel(
      steps: [
        [
          const TextDelta('Hello, '),
          const TextDelta('Dart'),
          const TokenUsage(inputTokens: 3, outputTokens: 2),
          const ModelFinished(),
        ],
      ],
    ),
    prompt: 'Say hello',
  );
  check(text.text == 'Hello, Dart', 'Simple response was not reconstructed');
  check(text.usage?.inputTokens == 3, 'Usage is not typed');
  print('PASS simple generation, text and usage');

  final answer = await generateObject<int>(
    model: ScriptedChatModel(
      capabilities: capabilities,
      steps: [
        [const TextDelta('{"answer":42}'), const ModelFinished()],
      ],
    ),
    schema: schema,
    decode: (json) => (json as Map<String, Object?>)['answer'] as int,
    prompt: 'Answer the question',
  );
  check(answer.value == 42, 'Structured value differs');
  print('PASS typed structured output');

  var executed = 0;
  final store = MemoryRunStore();
  Tool<int, int, String> makeTool() => Tool(
    name: 'double',
    description: 'Double an integer',
    inputSchema: schema,
    outputSchema: const {'type': 'integer'},
    needsApproval: true,
    decode: (json) => json['answer'] as int,
    encode: (n) => n,
    execute: (n, context) {
      check(context.value == 'trusted-application-context', 'Context was lost');
      check(context.idempotencyKey.isNotEmpty, 'Idempotency key is missing');
      executed++;
      return n * 2;
    },
  );
  final first = AiAgent<String>(
    store: store,
    tools: [makeTool()],
    model: ScriptedChatModel(
      capabilities: capabilities,
      steps: [
        [
          ToolCallReady(
            ToolCall(
              id: 'double-call',
              name: 'double',
              arguments: {'answer': 21},
            ),
          ),
          const ModelFinished(),
        ],
      ],
    ),
  );
  final paused = await first.generate(
    ChatRequest(
      threadId: 'thread',
      runId: 'first',
      messages: [ChatMessage.user('Double 21', id: 'user-1')],
    ),
    ownerId: 'owner',
    context: 'trusted-application-context',
  );
  check(
    paused.status == RunStatus.interrupted && executed == 0,
    'Approval did not pause',
  );
  final secondModel = ScriptedChatModel(
    capabilities: capabilities,
    steps: [
      [const TextDelta('42'), const ModelFinished()],
      [const TextDelta('Again'), const ModelFinished()],
    ],
  );
  final recreated = AiAgent<String>(
    store: store,
    tools: [makeTool()],
    model: secondModel,
  );
  final resumed = await recreated.generate(
    ChatRequest(
      threadId: 'thread',
      runId: 'second',
      parentRunId: paused.runId,
      resume: [paused.interrupts.single.approve()],
    ),
    ownerId: 'owner',
    context: 'trusted-application-context',
  );
  check(executed == 1 && resumed.text == '42', 'Resume did not finish once');
  final next = await recreated.generate(
    ChatRequest(
      threadId: 'thread',
      runId: 'third',
      messages: [ChatMessage.user('Repeat', id: 'user-2')],
    ),
    ownerId: 'owner',
    context: 'trusted-application-context',
  );
  check(next.text == 'Again', 'Next turn did not finish');
  check(
    secondModel.requests.last.messages.any((m) => m.role == MessageRole.tool),
    'Stored tool history was lost',
  );
  check(resumed.text == '42', 'Prior result was mutated by the next turn');
  print(
    'PASS approval, recreated agent, typed context, stored history, next turn',
  );

  final local = await generateText(model: LocalEchoModel(), prompt: 'Cairo');
  check(local.text == 'Local: Cairo', 'Custom provider response differs');
  print('PASS custom offline provider');

  try {
    await generateObject<int>(
      model: ScriptedChatModel(
        capabilities: capabilities,
        steps: [
          [const TextDelta('{"answer":"bad"}'), const ModelFinished()],
        ],
      ),
      schema: schema,
      decode: (json) => (json as Map)['answer'] as int,
      prompt: 'Give an integer',
    );
    throw StateError('Invalid schema response did not throw');
  } on AgentRunException catch (error) {
    print(
      'PASS invalid structured response error: ${error.code}, cause=${error.cause.runtimeType}',
    );
  }
}

final class LocalEchoModel implements ChatModel {
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    yield TextDelta('Local: ${request.messages.last.text}');
    yield const ModelFinished();
  }
}
