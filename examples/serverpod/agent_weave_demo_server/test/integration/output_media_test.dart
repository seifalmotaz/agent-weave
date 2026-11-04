import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

const png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aQAAAABJRU5ErkJggg==';

void main() {
  withServerpod('Output media PostgreSQL recreation', (builder, _) {
    test(
      'retains ordered media and private replay while isolating owners',
      () async {
        final first = AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          model: ScriptedChatModel(
            steps: [
              [
                const TextDelta('beforeafter'),
                ContentPartReady(const ImagePart(png), textOffset: 6),
                ProviderOutput(
                  provider: 'fixture.responses',
                  items: [
                    {
                      'type': 'image_generation_call',
                      'private': 'PRIVATE-REPLAY',
                    },
                  ],
                ),
                const ModelFinished(),
              ],
            ],
          ),
        );
        final events = await first
            .run(
              ChatRequest(
                threadId: 'media-thread',
                runId: 'first',
                messages: [ChatMessage.user('Draw', id: 'u')],
              ),
              ownerId: 'owner',
              context: null,
            )
            .toList();
        expect(
          jsonEncode(events.map((e) => e.json).toList()),
          isNot(contains('PRIVATE-REPLAY')),
        );
        final recreatedStore = ServerpodRunStore(builder.build());
        expect(
          await recreatedStore.load(ownerId: 'other', threadId: 'media-thread'),
          isNull,
        );
        final state = await recreatedStore.load(
          ownerId: 'owner',
          threadId: 'media-thread',
        );
        expect(jsonEncode(state), contains('PRIVATE-REPLAY'));
        final hydration = chatHydration(state);
        expect(jsonEncode(hydration), isNot(contains('PRIVATE-REPLAY')));
        final message = (hydration['messages'] as List).cast<Map>().singleWhere(
          (m) => (m['parts'] as List).any((p) => (p as Map)['type'] == 'image'),
        );
        final parts = message['parts'] as List;
        expect(parts.map((p) => (p as Map)['type']), ['text', 'image', 'text']);
        expect(parts[0]['content'], 'before');
        expect(parts[1]['source'], {'type': 'url', 'value': png});
        expect(parts[2]['content'], 'after');
        final followup = ScriptedChatModel(
          capabilities: const ModelCapabilities(imageInput: true),
          steps: [
            [const TextDelta('done'), const ModelFinished()],
          ],
        );
        await AiAgent<void>(store: recreatedStore, model: followup).generate(
          ChatRequest(
            threadId: 'media-thread',
            runId: 'second',
            messages: [ChatMessage.user('Continue', id: 'u2')],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(
          jsonEncode(
            followup.requests.single.messages.map((m) => m.toJson()).toList(),
          ),
          contains('PRIVATE-REPLAY'),
        );
      },
    );
  });
}
