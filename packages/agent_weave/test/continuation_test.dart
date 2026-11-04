import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'continuations checkpoint opaque state, count usage and finish once',
    () async {
      final store = MemoryRunStore();
      final model = ScriptedChatModel(
        steps: [
          [
            ProviderOutput(
              provider: 'fixture',
              items: [
                {'opaque': 'state'},
              ],
            ),
            const TextDelta('Working'),
            const TokenUsage(inputTokens: 2, outputTokens: 3),
            const ModelFinished.continuation('provider_pause'),
          ],
          [
            const TextDelta('Done'),
            const TokenUsage(inputTokens: 4, outputTokens: 5),
            const ModelFinished(),
          ],
        ],
      );
      final result = await AiAgent<void>(model: model, store: store).generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('Go', id: 'u')],
        ),
        ownerId: 'owner',
        context: null,
      );
      expect(model.requests, hasLength(2));
      expect(
        model
            .requests
            .last
            .messages
            .last
            .providerData['fixture']!
            .single['opaque'],
        'state',
      );
      expect(result.responseMessages.map((m) => m.text), ['Working', 'Done']);
      expect(result.usage!.inputTokens, 6);
      expect(result.usage!.outputTokens, 8);
      expect(
        ((await store.load(ownerId: 'owner', threadId: 't'))!['events'] as List)
            .where((e) => (e as Map)['type'] == 'RUN_FINISHED'),
        hasLength(1),
      );
      expect(
        (await store.load(
          ownerId: 'owner',
          threadId: 't',
        ))!['providerContinuationPending'],
        isNull,
      );
    },
  );

  test(
    'a paused step limit can resume but cannot accept a new user message',
    () async {
      final store = MemoryRunStore();
      final paused = AiAgent<void>(
        store: store,
        maxSteps: 1,
        model: ScriptedChatModel(
          capabilities: const ModelCapabilities(tools: true),
          steps: [
            [const ModelFinished.continuation()],
          ],
        ),
      );
      final events = await paused
          .run(
            ChatRequest(threadId: 't', runId: 'one'),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      expect(events.last.json['code'], 'STEP_LIMIT');
      final before = await store.load(ownerId: 'owner', threadId: 't');
      expect(before!['providerContinuationPending'], true);
      final model = ScriptedChatModel(
        steps: [
          [const TextDelta('Done'), const ModelFinished()],
        ],
      );
      final continued = AiAgent<void>(store: store, model: model);
      final invalid = await continued
          .run(
            ChatRequest(
              threadId: 't',
              runId: 'invalid',
              messages: [ChatMessage.user('New', id: 'new')],
            ),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      expect(invalid.last.json['code'], 'INVALID_INPUT');
      expect(model.requests, isEmpty);
      expect(
        (await store.load(ownerId: 'owner', threadId: 't'))!['messages'],
        before['messages'],
      );
      final result = await continued.generate(
        ChatRequest(threadId: 't', runId: 'two'),
        ownerId: 'owner',
        context: null,
      );
      expect(result.text, 'Done');
      expect(model.requests, hasLength(1));
    },
  );

  test(
    'structured output validates the final response after a pause',
    () async {
      final result = await generateObject<int>(
        model: ScriptedChatModel(
          capabilities: const ModelCapabilities(structuredOutput: true),
          steps: [
            [
              const TextDelta('Not JSON yet'),
              const ModelFinished.continuation(),
            ],
            [const TextDelta('{"answer":42}'), const ModelFinished()],
          ],
        ),
        prompt: 'Answer',
        schema: {
          'type': 'object',
          'properties': {
            'answer': {'type': 'integer'},
          },
          'required': ['answer'],
        },
        decode: (value) => (value as Map)['answer'] as int,
      );
      expect(result.value, 42);
    },
  );

  test(
    'continuation with local calls fails without executing any tool',
    () async {
      var effects = 0;
      final agent = AiAgent<void>(
        model: ScriptedChatModel(
          capabilities: const ModelCapabilities(tools: true),
          steps: [
            [
              ToolCallReady(
                ToolCall(id: 'call', name: 'effect', arguments: {}),
              ),
              const ModelFinished.continuation(),
            ],
          ],
        ),
        tools: [
          Tool<void, int, void>(
            name: 'effect',
            description: 'Effect',
            inputSchema: {'type': 'object'},
            decode: (_) {},
            encode: (v) => v,
            execute: (_, _) => ++effects,
          ),
        ],
      );
      final events = await agent
          .run(
            ChatRequest(threadId: 't', runId: 'r'),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      expect(events.last.json['code'], 'MODEL_FAILED');
      expect(effects, 0);
    },
  );
  test(
    'structured messages round-trip typed history without private replay',
    () async {
      final model = ScriptedChatModel(
        capabilities: const ModelCapabilities(structuredOutput: true),
        steps: [
          [const TextDelta('{"answer":42}'), const ModelFinished()],
          [const TextDelta('Progress'), const ModelFinished.continuation()],
          [const TextDelta('{"answer":43}'), const ModelFinished()],
        ],
      );
      final store = MemoryRunStore();
      final agent = AiAgent<void>(
        model: model,
        store: store,
        outputSchema: {
          'type': 'object',
          'properties': {
            'answer': {'type': 'integer'},
          },
          'required': ['answer'],
        },
      );
      await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'one',
          messages: [ChatMessage.user('First', id: 'u1')],
        ),
        ownerId: 'owner',
        context: null,
      );
      final events = await agent
          .run(
            ChatRequest(
              threadId: 't',
              runId: 'two',
              messages: [ChatMessage.user('Second', id: 'u2')],
            ),
            ownerId: 'owner',
            context: null,
          )
          .toList();
      final snapshot = events
          .singleWhere((e) => e.type == 'MESSAGES_SNAPSHOT')
          .json;
      final during = (snapshot['messages'] as List)
          .expand((m) => (m as Map)['parts'] as List)
          .where((p) => (p as Map)['type'] == 'structured-output');
      expect(during.single['data'], {'answer': 42});
      final hydrated = chatHydration(
        await store.load(ownerId: 'owner', threadId: 't'),
      );
      final outputs = (hydrated['messages'] as List)
          .expand((m) => (m as Map)['parts'] as List)
          .where((p) => (p as Map)['type'] == 'structured-output');
      expect(outputs.map((p) => p['data']), [
        {'answer': 42},
        {'answer': 43},
      ]);
      expect(
        model.requests.last.messages
            .where((m) => m.structuredOutput != null)
            .single
            .text,
        '{"answer":42}',
      );
    },
  );

  test(
    'structured metadata handles null, immutable JSON and legacy messages',
    () {
      for (final raw in [
        'null',
        '42',
        'true',
        '"text"',
        '[1,2]',
        '{"nested":[1]}',
      ]) {
        final output = StructuredMessageOutput(raw);
        final message = ChatMessage(
          id: 'a',
          role: MessageRole.assistant,
          content: [TextPart(raw)],
          structuredOutput: output,
        );
        final decoded = ChatMessage.fromJson(message.toJson());
        expect(decoded.structuredOutput!.data, output.data);
      }
      final output = StructuredMessageOutput('{"nested":[1]}');
      expect(
        () => ((output.data as Map)['nested'] as List).add(2),
        throwsUnsupportedError,
      );
      expect(() => StructuredMessageOutput('not JSON'), throwsFormatException);
      expect(() => StructuredMessageOutput.fromJson({}), throwsFormatException);
      expect(
        () => ChatMessage(
          id: 'u',
          role: MessageRole.user,
          structuredOutput: output,
        ),
        throwsArgumentError,
      );
      expect(
        ChatMessage.fromJson(
          ChatMessage.user('Legacy', id: 'u').toJson(),
        ).structuredOutput,
        isNull,
      );
    },
  );
}
