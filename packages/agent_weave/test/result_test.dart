import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:test/test.dart';

ScriptedChatModel textModel() => ScriptedChatModel(
  steps: [
    [
      const TextDelta('Hello'),
      const TokenUsage(inputTokens: 2, outputTokens: 1),
      const ModelFinished(),
    ],
  ],
);
const schema = <String, Object?>{
  'type': 'object',
  'required': ['answer'],
  'properties': {
    'answer': {'type': 'integer'},
  },
  'additionalProperties': false,
};
void main() {
  test(
    'stateless generation returns typed text, usage and immutable messages',
    () async {
      final model = textModel();
      final result = await generateText(model: model, prompt: 'Hi');
      expect(result.text, 'Hello');
      expect(result.status, RunStatus.completed);
      expect(result.usage!.inputTokens, 2);
      expect(result.usage!.cachedInputTokens, isNull);
      expect(result.messages, hasLength(2));
      expect(result.responseMessages, hasLength(1));
      expect(model.requests.single.messages.single.text, 'Hi');
      expect(() => result.messages.clear(), throwsUnsupportedError);
      expect(() => model.requests.clear(), throwsUnsupportedError);
    },
  );
  test(
    'trusted stateless history supports assistant and tool messages',
    () async {
      final model = textModel();
      await generateText(
        model: model,
        messages: [
          ChatMessage.user('Before', id: 'u1'),
          ChatMessage(
            id: 'a1',
            role: MessageRole.assistant,
            content: [const TextPart('Previous')],
          ),
          ChatMessage.user('Now', id: 'u2'),
        ],
      );
      expect(model.requests.single.messages.map((m) => m.text), [
        'Before',
        'Previous',
        'Now',
      ]);
    },
  );
  test('structured output validates before the typed decoder', () async {
    final model = ScriptedChatModel(
      capabilities: const ModelCapabilities(structuredOutput: true),
      steps: [
        [const TextDelta('{"answer":42}'), const ModelFinished()],
      ],
    );
    final result = await generateObject<int>(
      model: model,
      prompt: 'Answer',
      schema: schema,
      decode: (json) => (json as Map)['answer'] as int,
    );
    expect(result.value, 42);
    expect(result.generation.output, {'answer': 42});
    expect(
      () => (result.generation.output as Map)['answer'] = 5,
      throwsUnsupportedError,
    );
  });
  test(
    'invalid structured output never reaches the application decoder',
    () async {
      var decoded = false;
      final model = ScriptedChatModel(
        capabilities: const ModelCapabilities(structuredOutput: true),
        steps: [
          [const TextDelta('{"answer":"wrong"}'), const ModelFinished()],
        ],
      );
      await expectLater(
        generateObject<int>(
          model: model,
          prompt: 'Answer',
          schema: schema,
          decode: (_) {
            decoded = true;
            return 1;
          },
        ),
        throwsA(isA<AgentRunException>()),
      );
      expect(decoded, isFalse);
      final invalid = ScriptedChatModel(
        capabilities: const ModelCapabilities(structuredOutput: true),
        steps: [
          [const TextDelta('not JSON'), const ModelFinished()],
        ],
      );
      await expectLater(
        generateObject<int>(
          model: invalid,
          prompt: 'Hi',
          schema: schema,
          decode: (_) => 0,
        ),
        throwsA(
          isA<AgentRunException>().having(
            (e) => e.code,
            'code',
            'INVALID_OUTPUT',
          ),
        ),
      );
    },
  );
  test(
    'provider errors are thrown with partial output and a private cause',
    () async {
      final agent = AiAgent<void>(
        model: ScriptedChatModel(
          steps: [
            [const TextDelta('Partial')],
          ],
        ),
      );
      try {
        await agent.generate(
          ChatRequest(
            threadId: 't',
            runId: 'r',
            messages: [ChatMessage.user('Hi', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        );
        fail('Expected an error');
      } on AgentRunException catch (error) {
        expect(error.result.text, 'Partial');
        expect(error.result.status, RunStatus.failed);
        expect(error.cause, isA<StateError>());
        expect(error.toString(), isNot(contains('terminal event')));
      }
    },
  );
  test('pre-cancelled generation sends no model request', () async {
    final model = textModel();
    await expectLater(
      generateText(
        model: model,
        prompt: 'Hi',
        cancellation: CancellationToken()..cancel(),
      ),
      throwsA(isA<RunCancelled>()),
    );
    expect(model.requests, isEmpty);
  });
  test(
    'a result remains its own snapshot after later persisted turns',
    () async {
      final model = ScriptedChatModel(
        steps: [
          [const TextDelta('First'), const ModelFinished()],
          [const TextDelta('Second'), const ModelFinished()],
        ],
      );
      final agent = AiAgent<void>(model: model);
      final first = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r1',
          messages: [ChatMessage.user('Hi', id: 'u1')],
        ),
        ownerId: 'o',
        context: null,
      );
      final second = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r2',
          messages: [ChatMessage.user('Again', id: 'u2')],
        ),
        ownerId: 'o',
        context: null,
      );
      expect(first.messages, hasLength(2));
      expect(first.text, 'First');
      expect(second.messages, hasLength(4));
      expect(second.text, 'Second');
      expect(second.responseMessages, hasLength(1));
    },
  );
  test(
    'typed approvals pause and resume with the same trusted context',
    () async {
      final model = ScriptedChatModel(
        capabilities: const ModelCapabilities(tools: true),
        steps: [
          [
            ToolCallReady(ToolCall(id: 'c', name: 'send', arguments: {})),
            const TokenUsage(inputTokens: 3, outputTokens: 2),
            const ModelFinished(),
          ],
          [
            const TextDelta('Done'),
            const TokenUsage(inputTokens: 4, outputTokens: 1),
            const ModelFinished(),
          ],
        ],
      );
      var called = 0;
      final agent = AiAgent<int>(
        model: model,
        tools: [
          Tool<int, int, int>(
            name: 'send',
            description: 'Send',
            inputSchema: const {'type': 'object'},
            needsApproval: true,
            decode: (_) => 1,
            encode: (n) => n,
            execute: (n, context) {
              called++;
              return context.value;
            },
          ),
        ],
      );
      final paused = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('Start', id: 'u')],
        ),
        ownerId: 'o',
        context: 42,
      );
      expect(paused.status, RunStatus.interrupted);
      expect(called, 0);
      final done = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'next',
          parentRunId: paused.runId,
          resume: [paused.interrupts.single.approve()],
        ),
        ownerId: 'o',
        context: 42,
      );
      expect(done.text, 'Done');
      expect(called, 1);
    },
  );
  test(
    'tool loops aggregate reported usage without inventing missing details',
    () async {
      final model = ScriptedChatModel(
        capabilities: const ModelCapabilities(tools: true),
        steps: [
          [
            ToolCallReady(ToolCall(id: 'c', name: 'double', arguments: {})),
            const TokenUsage(
              inputTokens: 3,
              outputTokens: 2,
              cachedInputTokens: 1,
            ),
            const ModelFinished(),
          ],
          [
            const TextDelta('Done'),
            const TokenUsage(inputTokens: 4, outputTokens: 1),
            const ModelFinished(),
          ],
        ],
      );
      final result = await generateText(
        model: model,
        prompt: 'Start',
        tools: [
          Tool<int, int, void>(
            name: 'double',
            description: 'Double',
            inputSchema: const {'type': 'object'},
            decode: (_) => 2,
            encode: (n) => n,
            execute: (n, _) => n * 2,
          ),
        ],
      );
      expect(result.usage!.inputTokens, 7);
      expect(result.usage!.outputTokens, 3);
      expect(result.usage!.cachedInputTokens, isNull);
      expect(result.usages, hasLength(2));
    },
  );
  test('no reported usage remains unknown', () async {
    final result = await generateText(
      model: ScriptedChatModel(
        steps: [
          [const ModelFinished()],
        ],
      ),
      prompt: 'Hi',
    );
    expect(result.usage, isNull);
  });
  test(
    'prompt and messages are mutually exclusive and cannot both be missing',
    () {
      expect(() => generateText(model: textModel()), throwsArgumentError);
      expect(
        () => generateText(model: textModel(), prompt: 'Hi', messages: []),
        throwsArgumentError,
      );
      expect(
        () => generateText(model: textModel(), messages: []),
        throwsArgumentError,
      );
    },
  );
  test(
    'request schema snapshots are isolated from provider and caller mutations',
    () {
      final mutable = <String, Object?>{'type': 'object'};
      final request = ModelRequest(
        messages: [],
        tools: [ModelTool(name: 't', description: '', inputSchema: mutable)],
        outputSchema: mutable,
      );
      mutable['type'] = 'string';
      expect(request.outputSchema!['type'], 'object');
      expect(request.tools.single.inputSchema['type'], 'object');
      expect(
        () => request.tools.single.inputSchema.clear(),
        throwsUnsupportedError,
      );
    },
  );
}
