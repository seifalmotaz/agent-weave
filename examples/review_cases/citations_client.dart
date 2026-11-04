import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart' as client;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final citation = TextCitation(
    start: 2,
    end: 4,
    source: UrlCitationSource(
      'https://example.com/plant',
      title: 'Plant guide',
    ),
    citedText: 'The source quotation differs from the generated answer.',
  );
  final store = MemoryRunStore();
  final agent = AiAgent<void>(
    store: store,
    model: ScriptedChatModel(
      steps: [
        [
          const TextDelta('A 🌿 grows.'),
          CitationReady(citation),
          ProviderOutput(
            provider: 'fixture.private',
            items: [
              {'encrypted_index': 'PRIVATE-CITATION'},
            ],
          ),
          const ModelFinished(),
        ],
      ],
    ),
  );
  Future<String> history() async => jsonEncode(
    chatHydration(await store.load(ownerId: 'owner', threadId: 'thread')),
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.method == 'GET') {
      request.response.headers.contentType = ContentType.json;
      request.response.write(await history());
    } else {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      await for (final event in agent.run(
        ChatRequest.fromJson(Map<String, Object?>.from(body)),
        ownerId: 'owner',
        context: null,
      )) {
        request.response.write(event.toSse());
      }
    }
    await request.response.close();
  });
  final url = 'http://127.0.0.1:${server.port}/chat';
  final events = <Map<String, dynamic>>[];
  final chat = client.ChatClient(
    connection: client.fetchServerSentEvents(url),
    threadId: 'thread',
    onCustomEvent: (event, _) {
      if (event['name'] == 'agent_weave:citation') events.add(event);
    },
  );
  final restored = client.ChatClient(
    connection: serverpodConnection(
      send: (_) => throw StateError('Hydration must not rerun the model.'),
      loadHistory: (_) => history(),
    ),
    threadId: 'thread',
    persistence: const client.ChatPersistenceOptions.server(),
  );
  try {
    await chat.sendText('Summarize');
    check(chat.error == null, 'stream failure: ${chat.error}');
    final live = chat.messages.singleWhere((m) => m.role == 'assistant');
    final annotations = live.metadata!['agent_weave']['citations'] as List;
    check(events.length == 1, 'expected one public citation event');
    check(
      (events.single['value'] as Map)['messageId'] == live.id,
      'message ID',
    );
    final decoded = TextCitation.fromJson(
      Map<String, Object?>.from(annotations.single as Map),
    );
    check(
      live.answer.substring(decoded.start, decoded.end) == '🌿',
      'UTF16 span',
    );
    check(jsonEquals(decoded.toJson(), citation.toJson()), 'citation data');
    await restored.attach();
    check(restored.error == null, 'hydration failure: ${restored.error}');
    final reloaded = restored.messages.singleWhere(
      (m) => m.role == 'assistant',
    );
    check(jsonEquals(live.metadata, reloaded.metadata), 'restored attribution');
    check(reloaded.answer == live.answer, 'restored text');
    check(
      !(await history()).contains('PRIVATE-CITATION'),
      'private replay leak',
    );
    print('PASS Dart SSE citations and Serverpod history hydration');
  } finally {
    await chat.dispose();
    await restored.dispose();
    await server.close(force: true);
  }
}
