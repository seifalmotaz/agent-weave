import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave_demo_client/agent_weave_demo_client.dart'
    as backend;
import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart';
import 'native_chat.dart' show LocalDemoAuth;

/// Start and resume in different processes; the backend database owns the pause.
Future<void> main(List<String> args) async {
  if (args.length < 2 || !{'start', 'approve', 'reject'}.contains(args.first)) {
    throw ArgumentError(
      'Usage: dart run example/approval_workflow.dart <start|approve|reject> <thread> [server-url]',
    );
  }
  final thread = args[1];
  final client = backend.Client(
    args.length > 2 ? args[2] : 'http://localhost:8080/',
  )..authKeyProvider = const LocalDemoAuth();
  final chat = ChatClient(
    threadId: thread,
    persistence: const ChatPersistenceOptions.server(),
    connection: serverpodConnection(
      send: client.ai.chat,
      loadHistory: client.ai.history,
    ),
    tools: [
      ChatClientTool(
        name: 'greet',
        needsApproval: true,
        inputSchema: RawJsonSchema(const {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
          },
          'required': ['name'],
          'additionalProperties': false,
        }),
        outputSchema: RawJsonSchema(const {'type': 'string'}),
      ),
    ],
  );
  try {
    await chat.attach();
    if (chat.error != null) throw StateError(chat.error!);
    if (args.first == 'start') {
      if (chat.messages.isNotEmpty) {
        throw StateError('Use a new thread for start.');
      }
      await chat.sendText('Greet Ada with approval');
      if (chat.error != null) throw StateError(chat.error!);
      final pending = chat.getInterrupts();
      if (pending.isEmpty) {
        throw StateError('No pending approval exists for this thread.');
      }
      final interrupt = pending.single;
      if (!interrupt.canResolve ||
          interrupt.kind != 'tool-approval' ||
          interrupt.toolName != 'greet') {
        throw StateError('Tool schema does not match the server.');
      }
      stdout.writeln(
        'PAUSED $thread. This process can exit; approval is stored in PostgreSQL.',
      );
      stdout.writeln(
        'After a human decision, run approve or reject with the same thread.',
      );
    } else {
      final pending = chat.getInterrupts();
      if (pending.isEmpty) {
        throw StateError('No pending approval exists for this thread.');
      }
      final interrupt = pending.single;
      if (!interrupt.canResolve ||
          interrupt.kind != 'tool-approval' ||
          interrupt.toolName != 'greet') {
        throw StateError('Cannot bind the stored approval.');
      }
      final expected = args.first == 'approve'
          ? 'Hello Ada'
          : 'Greeting was declined.';
      final finished = Completer<void>();
      final subscription = chat.states.listen((_) {
        if (!finished.isCompleted &&
            (chat.error != null ||
                (!chat.isStreaming &&
                    chat.messages.isNotEmpty &&
                    chat.messages.last.answer == expected))) {
          finished.complete();
        }
      });
      try {
        interrupt.resolveApproval(args.first == 'approve');
        await finished.future.timeout(const Duration(seconds: 30));
        if (chat.error != null) throw StateError(chat.error!);
        final snapshot = jsonDecode(await client.ai.history(thread)) as Map;
        stdout.writeln('RESUMED $thread: ${chat.messages.last.answer}');
        stdout.writeln(
          'Stored UI messages: ${(snapshot['messages'] as List).length}',
        );
      } finally {
        await subscription.cancel();
      }
    }
  } finally {
    await chat.dispose();
    client.close();
  }
}
