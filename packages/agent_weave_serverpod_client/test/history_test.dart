import 'dart:convert';
import 'package:agent_weave/agent_weave.dart' as core;
import 'package:agent_weave/testing.dart' as fixtures;
import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart';
import 'package:test/test.dart';

void main() {
  for (final (persistent, registered) in [
    (false, true),
    (true, false),
    (true, true),
  ]) {
    test(
      'restores real pending tool: server=$persistent registered=$registered',
      () async {
        const schema = <String, Object?>{
          'type': 'object',
          'properties': {
            'n': {'type': 'integer'},
          },
          'required': ['n'],
          'additionalProperties': false,
        };
        final agent = core.AiAgent<void>(
          model: fixtures.ScriptedChatModel(
            capabilities: const core.ModelCapabilities(tools: true),
            steps: [
              [
                core.ToolCallReady(
                  core.ToolCall(
                    id: 'call',
                    name: 'double',
                    arguments: {'n': 21},
                  ),
                ),
                const core.ModelFinished(),
              ],
            ],
          ),
          tools: [
            core.Tool<int, int, void>(
              name: 'double',
              description: 'Double',
              needsApproval: true,
              inputSchema: schema,
              outputSchema: const {'type': 'integer'},
              decode: (json) => json['n'] as int,
              encode: (n) => n,
              execute: (n, _) => n * 2,
            ),
          ],
        );
        await agent.generate(
          core.ChatRequest(
            threadId: 'thread',
            runId: 'paused',
            messages: [core.ChatMessage.user('Start', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        );
        final raw = jsonEncode(
          core.chatHydration(
            await agent.store.load(ownerId: 'owner', threadId: 'thread'),
          ),
        );
        var reads = 0;
        final chat = ChatClient(
          threadId: 'thread',
          persistence: persistent
              ? const ChatPersistenceOptions.server()
              : const ChatPersistenceOptions.ephemeral(),
          connection: serverpodConnection(
            send: (_) => const Stream.empty(),
            loadHistory: (_) async {
              reads++;
              return raw;
            },
          ),
          tools: registered
              ? [
                  const ChatClientTool(
                    name: 'double',
                    needsApproval: true,
                    inputSchema: RawJsonSchema(schema),
                    outputSchema: RawJsonSchema({'type': 'integer'}),
                  ),
                ]
              : [],
        );
        addTearDown(chat.dispose);
        await chat.attach();
        expect(chat.error, isNull);
        expect(reads, persistent ? 1 : 0);
        if (!persistent) {
          expect(chat.getInterrupts(), isEmpty);
          return;
        }
        final restored = chat.getInterrupts().single;
        expect(restored.kind, registered ? 'tool-approval' : 'generic');
        expect(restored.canResolve, isTrue);
        if (registered) expect(restored.toolName, 'double');
      },
    );
  }

  test(
    'native history loader preserves stored tool bindings and paging metadata',
    () async {
      final json = {
        'messages': [
          {'id': 'm', 'role': 'user', 'parts': <Object?>[]},
        ],
        'activeRun': {'runId': 'active'},
        'interrupts': {
          'runId': 'paused',
          'pending': [
            {
              'id': 'i',
              'metadata': {'binding': 'original'},
            },
          ],
        },
        'page': {'truncated': true, 'cursor': 'older'},
      };
      final connection = serverpodConnection(
        send: (_) => const Stream.empty(),
        loadHistory: (id) async {
          expect(id, 'thread');
          return jsonEncode(json);
        },
      );
      final result = await connection.hydrate!('thread');
      expect(result.messages.single['id'], 'm');
      expect(result.activeRun!.runId, 'active');
      expect(result.interrupts!.pending.single['metadata'], {
        'binding': 'original',
      });
      expect(result.page.cursor, 'older');
    },
  );
  test('explicit hydration callback and native loader cannot conflict', () {
    expect(
      () => serverpodConnection(
        send: (_) => const Stream.empty(),
        hydrate: (_, {options}) async =>
            const ChatHydrationResult(messages: []),
        loadHistory: (_) async => '{}',
      ),
      throwsArgumentError,
    );
  });
  test(
    'full snapshot loader rejects unsupported paging instead of losing history',
    () async {
      var called = false;
      final connection = serverpodConnection(
        send: (_) => const Stream.empty(),
        loadHistory: (_) async {
          called = true;
          return '{"messages":[]}';
        },
      );
      await expectLater(
        connection.hydrate!('t', options: const ChatHydrateOptions(limit: 5)),
        throwsUnsupportedError,
      );
      expect(called, isFalse);
    },
  );
  for (final invalid in [
    '[]',
    '{}',
    '{"messages":{}}',
    '{"messages":[null]}',
    '{"messages":[],"activeRun":{}}',
    '{"messages":[],"interrupts":{"pending":[]}}',
    '{"messages":[],"interrupts":{"runId":"r","pending":{}}}',
    '{"messages":[],"page":{"truncated":"yes"}}',
  ]) {
    test('malformed history fails clearly: $invalid', () {
      expect(() => decodeServerpodHistory(invalid), throwsFormatException);
    });
  }
  test('empty server snapshot has no fabricated resume state', () {
    final result = decodeServerpodHistory(
      '{"messages":[],"activeRun":null,"interrupts":null}',
    );
    expect(result.messages, isEmpty);
    expect(result.activeRun, isNull);
    expect(result.interrupts, isNull);
    expect(result.page.truncated, isFalse);
  });
}
