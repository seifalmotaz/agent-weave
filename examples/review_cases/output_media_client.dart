import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart' as client;

const png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aQAAAABJRU5ErkJggg==';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

List<Map<String, dynamic>> mediaParts(client.ChatClient chat) => chat.messages
    .singleWhere((message) => message.parts.any((part) => part.type == 'image'))
    .parts
    .map((part) => part.toJson())
    .toList();

void checkParts(List<Map<String, dynamic>> parts) {
  check(
    parts.length == 3 &&
        parts[0]['type'] == 'text' &&
        parts[0]['content'] == 'before' &&
        parts[1]['type'] == 'image' &&
        (parts[1]['source'] as Map)['value'] == png &&
        parts[2]['type'] == 'text' &&
        parts[2]['content'] == 'after',
    'media order: $parts',
  );
  check(
    !jsonEncode(parts).contains('PRIVATE-REPLAY'),
    'private data in client parts',
  );
}

Future<void> main() async {
  final store = MemoryRunStore();
  final agent = AiAgent<void>(
    store: store,
    model: ScriptedChatModel(
      steps: [
        [
          const TextDelta('beforeafter'),
          ContentPartReady(const ImagePart(png), textOffset: 6),
          ProviderOutput(
            provider: 'fixture.responses',
            items: [
              {'type': 'image_generation_call', 'private': 'PRIVATE-REPLAY'},
            ],
          ),
          const ModelFinished(),
        ],
      ],
    ),
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final liveWire = StringBuffer();
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
        final line = 'data: ${jsonEncode(event.json)}\n\n';
        liveWire.write(line);
        request.response.write(line);
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
    await chat.sendText('Draw');
    check(chat.error == null, 'live error: ${chat.error}');
    checkParts(mediaParts(chat));
    check(
      !liveWire.toString().contains('PRIVATE-REPLAY'),
      'private provider data on SSE',
    );
    final state = await store.load(ownerId: 'owner', threadId: 'thread');
    check(
      jsonEncode(state).contains('PRIVATE-REPLAY'),
      'private replay missing from store',
    );
    check(
      !jsonEncode(chatHydration(state)).contains('PRIVATE-REPLAY'),
      'private replay in hydration',
    );
    check(
      await store.load(ownerId: 'other', threadId: 'thread') == null,
      'other owner read history',
    );
    restored = client.ChatClient(
      connection: client.fetchServerSentEvents(url),
      threadId: 'thread',
      persistence: const client.ChatPersistenceOptions.server(),
    );
    await restored.attach();
    check(restored.error == null, 'hydration error: ${restored.error}');
    checkParts(mediaParts(restored));
    print('PASS native Dart SSE media ordering, privacy and hydration');
  } finally {
    await chat.dispose();
    await restored?.dispose();
    await server.close(force: true);
  }
}
