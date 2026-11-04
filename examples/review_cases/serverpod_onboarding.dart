import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart' as client;

const schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'ticket': {'type': 'integer'},
  },
  'required': ['ticket'],
  'additionalProperties': false,
};

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  var effects = 0;
  final store = MemoryRunStore();
  final model = ScriptedChatModel(
    capabilities: const ModelCapabilities(tools: true),
    steps: [
      [
        ToolCallReady(
          ToolCall(id: 'c1', name: 'escalate', arguments: {'ticket': 42}),
        ),
        const ModelFinished(),
      ],
      [const TextDelta('Ticket escalated.'), const ModelFinished()],
    ],
  );
  AiAgent<void> agent() => AiAgent<void>(
    model: model,
    store: store,
    tools: [
      Tool<int, String, void>(
        name: 'escalate',
        description: 'Escalate a ticket',
        inputSchema: schema,
        outputSchema: const {'type': 'string'},
        needsApproval: true,
        decode: (json) => json['ticket'] as int,
        encode: (value) => value,
        execute: (ticket, _) {
          effects++;
          return 'Escalated $ticket';
        },
      ),
    ],
  );
  final connection = serverpodConnection(
    loadHistory: (thread) async => jsonEncode(
      chatHydration(await store.load(ownerId: 'owner', threadId: thread)),
    ),
    send: (raw) => agent()
        .run(
          ChatRequest.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          ),
          ownerId: 'owner',
          context: null,
        )
        .map((event) => jsonEncode(event.json)),
  );
  client.ChatClient create() => client.ChatClient(
    threadId: 'support',
    connection: connection,
    persistence: const client.ChatPersistenceOptions.server(),
    tools: [
      client.ChatClientTool(
        name: 'escalate',
        needsApproval: true,
        inputSchema: client.RawJsonSchema(schema),
        outputSchema: client.RawJsonSchema(const {'type': 'string'}),
      ),
    ],
  );
  var chat = create();
  try {
    await chat.attach();
    await chat.sendText('Escalate ticket 42');
    check(
      chat.error == null && chat.getInterrupts().length == 1 && effects == 0,
      'Approval must pause before effects.',
    );
    await chat.dispose();
    chat = create();
    await chat.attach();
    final interrupt = chat.getInterrupts().single;
    check(
      interrupt.canResolve &&
          interrupt.kind == 'tool-approval' &&
          interrupt.toolName == 'escalate',
      'Restored approval did not bind.',
    );
    interrupt.resolveApproval(true);
    for (
      var i = 0;
      i < 100 &&
          chat.error == null &&
          !chat.messages.any((m) => m.answer == 'Ticket escalated.');
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    check(
      chat.error == null &&
          chat.messages.last.answer == 'Ticket escalated.' &&
          effects == 1,
      'Approval failed to complete exactly once.',
    );
    print(
      'Restored approval completed: ${chat.messages.last.answer}; effects=$effects',
    );
  } finally {
    await chat.dispose();
  }
}
