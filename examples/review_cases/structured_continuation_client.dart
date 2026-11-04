import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart' as client;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

List<Map<String, dynamic>> outputs(client.ChatClient chat) => [
  for (final message in chat.messages)
    for (final part in message.parts)
      if (part.type == 'structured-output') part.toJson(),
];

Future<void> main() async {
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
    outputSchema: const {
      'type': 'object',
      'properties': {
        'answer': {'type': 'integer'},
      },
      'required': ['answer'],
    },
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var snapshots = 0;
  server.listen((request) async {
    if (request.method == 'GET') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(
          chatHydration(await store.load(ownerId: 'owner', threadId: 'thread')),
        ),
      );
    } else {
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      await for (final event in agent.run(
        ChatRequest.fromJson(body),
        ownerId: 'owner',
        context: null,
      )) {
        if (event.type == 'MESSAGES_SNAPSHOT') snapshots++;
        request.response.write('data: ${jsonEncode(event.json)}\n\n');
      }
    }
    await request.response.close();
  });
  final url = 'http://127.0.0.1:${server.port}/chat';
  final chat = client.ChatClient(
    connection: client.fetchServerSentEvents(url),
    threadId: 'thread',
  );
  client.ChatClient? restored;
  try {
    await chat.sendText('First');
    check(chat.error == null, 'first client error: ${chat.error}');
    await chat.sendText('Second');
    check(chat.error == null, 'second client error: ${chat.error}');
    check(snapshots == 1, 'expected structured pause snapshot');
    final live = outputs(chat);
    check(
      live.length == 2 && live.every((p) => p['status'] == 'complete'),
      'live outputs: $live',
    );
    check(
      jsonEncode(live.map((p) => p['data']).toList()) ==
          '[{"answer":42},{"answer":43}]',
      'live values: $live',
    );
    restored = client.ChatClient(
      connection: client.fetchServerSentEvents(url),
      threadId: 'thread',
      persistence: const client.ChatPersistenceOptions.server(),
    );
    await restored.attach();
    check(restored.error == null, 'hydration error: ${restored.error}');
    final hydrated = outputs(restored);
    check(
      hydrated.length == 2 && hydrated.every((p) => p['status'] == 'complete'),
      'hydrated outputs: $hydrated',
    );
    check(
      jsonEncode(hydrated.map((p) => p['data']).toList()) ==
          '[{"answer":42},{"answer":43}]',
      'hydrated values: $hydrated',
    );
    print('PASS Dart client structured pause, snapshot and hydration over SSE');
  } finally {
    await chat.dispose();
    await restored?.dispose();
    await server.close(force: true);
  }
}
