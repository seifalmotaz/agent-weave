import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:test/test.dart';

void main() {
  final png = ImagePart('data:image/png;base64,aGVsbG8=');
  test(
    'complete media retains text order and reaches sanitized history',
    () async {
      final agent = AiAgent<void>(
        model: ScriptedChatModel(
          steps: [
            [
              const TextDelta('beforeafter'),
              ContentPartReady(png, textOffset: 6),
              ProviderOutput(
                provider: 'private',
                items: [
                  {'secret': true},
                ],
              ),
              const ModelFinished(),
            ],
          ],
        ),
      );
      final result = await agent.generate(
        ChatRequest(threadId: 't', runId: 'r'),
        ownerId: 'owner',
        context: null,
      );
      expect(result.responseMessages.single.content.map((p) => p.toJson()), [
        const TextPart('before').toJson(),
        png.toJson(),
        const TextPart('after').toJson(),
      ]);
      expect(result.images.single.url, png.url);
      expect(() => result.images.clear(), throwsUnsupportedError);
      final state = await agent.store.load(ownerId: 'owner', threadId: 't');
      final snapshot =
          (state!['events'] as List).singleWhere(
                (e) => (e as Map)['type'] == 'MESSAGES_SNAPSHOT',
              )
              as Map;
      expect(snapshot.toString(), isNot(contains('secret')));
      final parts =
          ((snapshot['messages'] as List).single as Map)['parts'] as List;
      expect(parts[1], {
        'type': 'image',
        'source': {'type': 'url', 'value': png.url},
      });
    },
  );
  test(
    'omitted offsets capture stream position including an image-only answer',
    () async {
      final result = await generateText(
        model: ScriptedChatModel(
          steps: [
            [
              ContentPartReady(png),
              const TextDelta('Caption'),
              ContentPartReady(png),
              const ModelFinished(),
            ],
          ],
        ),
        prompt: 'Draw',
      );
      expect(
        result.responseMessages.single.content.map((part) => part.runtimeType),
        [ImagePart, TextPart, ImagePart],
      );
    },
  );
  test(
    'media survives structured hydration without duplicating raw JSON text',
    () async {
      final result = await generateObject<int>(
        model: ScriptedChatModel(
          capabilities: const ModelCapabilities(structuredOutput: true),
          steps: [
            [
              const TextDelta('{"answer":42}'),
              ContentPartReady(png),
              const ModelFinished(),
            ],
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
        decode: (json) => (json as Map)['answer'] as int,
      );
      expect(result.value, 42);
      final hydrated = chatHydration({
        'messages': result.generation.messages.map((m) => m.toJson()).toList(),
      });
      final parts =
          ((hydrated['messages'] as List).last as Map)['parts'] as List;
      expect(parts.map((p) => (p as Map)['type']), [
        'structured-output',
        'image',
      ]);
    },
  );
  test(
    'invalid and reordered text offsets fail the provider invocation',
    () async {
      expect(
        () => ContentPartReady(const TextPart('wrong')),
        throwsArgumentError,
      );
      expect(() => ContentPartReady(png, textOffset: -1), throwsArgumentError);
      for (final offsets in [
        [2],
        [1, 0],
      ]) {
        final events =
            await AiAgent<void>(
                  model: ScriptedChatModel(
                    steps: [
                      [
                        const TextDelta('x'),
                        for (final offset in offsets)
                          ContentPartReady(png, textOffset: offset),
                        const ModelFinished(),
                      ],
                    ],
                  ),
                )
                .run(
                  ChatRequest(threadId: 't', runId: 'r'),
                  ownerId: 'owner',
                  context: null,
                )
                .toList();
        expect(events.last.json['code'], 'INVALID_OUTPUT');
      }
    },
  );
}
