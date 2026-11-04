import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart' as client;
import 'package:test/test.dart';

void main() {
  for (final decision in ['approve', 'reject', 'cancel']) {
    test('Dart client restores and resolves custom $decision', () async {
      final requests = <JsonObject>[];
      final events = <AgentEvent>[];
      var effects = 0;
      final store = MemoryRunStore();
      final model = openai.ResponsesProtocolModel.native(
        model: 'fixture',
        transport: (body, cancellation) async* {
          requests.add(body);
          if (requests.length == 1) {
            final call = <String, Object?>{
              'type': 'custom_tool_call',
              'id': 'PRIVATE-ITEM',
              'call_id': 'call-1',
              'name': 'lookup',
              'namespace': 'desk',
              'input': 'TICKET-42',
              'status': 'completed',
              'private_field': 'PRIVATE-REPLAY',
            };
            yield {
              'type': 'response.output_item.done',
              'sequence_number': 0,
              'output_index': 0,
              'item': call,
            };
            yield {
              'type': 'response.completed',
              'response': {
                'status': 'completed',
                'output': [call],
              },
            };
          } else {
            yield {'type': 'response.output_text.delta', 'delta': 'Done'};
            yield {
              'type': 'response.completed',
              'response': {'status': 'completed', 'output': <Object?>[]},
            };
          }
        },
      );
      AiAgent<void> agent() => AiAgent<void>(
        store: store,
        model: model,
        tools: [
          openai.OpenAICustomTool<void>(
            name: 'lookup',
            localName: 'desk_lookup',
            namespace: openai.OpenAIToolNamespace(
              name: 'desk',
              description: 'Support',
            ),
            bindingId: 'fixture-v1',
            needsApproval: true,
            execute: (input, context) {
              effects++;
              expect(input, 'TICKET-42');
              return openai.OpenAICustomToolResult.text('open');
            },
          ),
        ],
      );
      final connection = serverpodConnection(
        loadHistory: (threadId) async => jsonEncode(
          chatHydration(await store.load(ownerId: 'owner', threadId: threadId)),
        ),
        send: (raw) => agent()
            .run(
              ChatRequest.fromJson(
                Map<String, Object?>.from(jsonDecode(raw) as Map),
              ),
              ownerId: 'owner',
              context: null,
            )
            .map((event) {
              events.add(event);
              return jsonEncode(event.json);
            }),
      );
      client.ChatClient create() => client.ChatClient(
        threadId: 'thread',
        connection: connection,
        persistence: const client.ChatPersistenceOptions.server(),
      );
      var chat = create();
      try {
        await chat.attach();
        await chat.sendText('Lookup ticket');
        expect(chat.error, isNull);
        expect(requests, hasLength(1));
        expect(effects, 0);
        await chat.dispose();
        chat = create();
        await chat.attach();
        expect(chat.error, isNull);
        final interrupt = chat.getInterrupts().single;
        expect(interrupt.kind, 'generic');
        expect(interrupt.canResolve, isTrue);
        expect(interrupt.metadata!['toolName'], 'desk_lookup');
        expect(interrupt.metadata!['input'], {'input': 'TICKET-42'});
        if (decision == 'cancel') {
          interrupt.cancel();
        } else {
          interrupt.resolveInterrupt({'approved': decision == 'approve'});
        }
        for (
          var i = 0;
          i < 100 &&
              chat.error == null &&
              !chat.messages.any((m) => m.answer == 'Done');
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(chat.error, isNull);
        expect(chat.messages.last.answer, 'Done');
        expect(requests, hasLength(2));
        expect(effects, decision == 'approve' ? 1 : 0);
        final input = (requests.last['input'] as List)
            .whereType<Map<dynamic, dynamic>>()
            .toList();
        final native = input.singleWhere(
          (item) => item['type'] == 'custom_tool_call',
        );
        final result = input.singleWhere(
          (item) => item['type'] == 'custom_tool_call_output',
        );
        expect(native['private_field'], 'PRIVATE-REPLAY');
        expect(result['call_id'], 'call-1');
        expect(result['output'], switch (decision) {
          'approve' => 'open',
          'reject' => 'Tool call declined.',
          _ => 'Tool call cancelled.',
        });
        expect(
          input.any((item) => item['type'] == 'function_call_output'),
          isFalse,
        );
        final public = jsonEncode({
          'events': events.map((e) => e.json).toList(),
          'history': chatHydration(
            await store.load(ownerId: 'owner', threadId: 'thread'),
          ),
        });
        expect(public, isNot(contains('PRIVATE-ITEM')));
        expect(public, isNot(contains('PRIVATE-REPLAY')));
      } finally {
        await chat.dispose();
      }
    });
  }
}
