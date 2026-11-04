// Run from the workspace root with: dart --enable-asserts run examples/review_cases/documents.dart
// Offline fixtures only; no provider credentials are required.
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> main() async {
  final parts = [
    DocumentPart.url('https://example.com/a.pdf', filename: 'a.pdf'),
    DocumentPart.bytes(
      utf8.encode('hello'),
      mimeType: 'text/plain',
      filename: 'note.txt',
    ),
    DocumentPart.fileId('file-123', provider: 'openai'),
  ];
  final message = ChatMessage(id: 'u', role: MessageRole.user, content: parts);
  final restored = ChatMessage.fromJson(
    Map<String, Object?>.from(jsonDecode(jsonEncode(message.toJson())) as Map),
  );
  assert(jsonEncode(restored.toJson()) == jsonEncode(message.toJson()));
  final hydration = chatHydration({
    'messages': [message.toJson()],
    'events': [],
  });
  final wireParts = ((hydration['messages'] as List).single as Map)['parts'];
  final sources = (wireParts as List)
      .map((part) => (part as Map)['source'] as Map)
      .toList();
  assert(sources[0]['value'] == 'https://example.com/a.pdf');
  assert(sources[1]['value'] == 'aGVsbG8=');
  assert(sources[2]['value'] == 'file-123');
  final roundTrip = ChatRequest.fromJson({
    'threadId': 't',
    'runId': 'r',
    'messages': [
      {'id': 'u', 'role': 'user', 'parts': wireParts},
    ],
  });
  assert(
    jsonEncode(roundTrip.messages.single.toJson()) ==
        jsonEncode(message.toJson()),
  );
  assert(
    jsonEncode(hydration).contains('aGVsbG8='),
  ); // hydration exposes stored content to the caller
  for (final invalid in [
    () => DocumentPart.url('file:///private/a'),
    () => DocumentPart.base64('%%%', mimeType: 'application/pdf'),
    () => DocumentPart.fileId('', provider: 'openai'),
  ]) {
    try {
      invalid();
      throw StateError('expected validation failure');
    } on ArgumentError catch (_) {}
  }
  final transport = MockClient((http.Request request) async {
    final body = jsonDecode(request.body) as Map;
    if (request.url.host.contains('anthropic')) {
      final content =
          ((body['messages'] as List).single as Map)['content'] as List;
      assert(
        (content[0] as Map)['source']['url'] == 'https://example.com/a.pdf',
      );
      assert((content[1] as Map)['source']['data'] == 'hello');
      assert((content[2] as Map)['source']['data'] == 'JVBERg==');
      assert((content[2] as Map)['source']['media_type'] == 'application/pdf');
    } else {
      final content =
          ((body['input'] as List).single as Map)['content'] as List;
      assert((content[0] as Map)['file_url'] == 'https://example.com/a.pdf');
      assert(
        (content[1] as Map)['file_data'] == 'data:text/plain;base64,aGVsbG8=',
      );
      assert((content[2] as Map)['file_id'] == 'file-123');
    }
    if (request.url.host.contains('anthropic')) {
      return http.Response(
        'event: message_start\ndata: ${jsonEncode({
          'type': 'message_start',
          'message': {
            'id': 'm',
            'type': 'message',
            'role': 'assistant',
            'model': 'fixture',
            'content': <Object?>[],
            'usage': {'input_tokens': 1, 'output_tokens': 0},
          },
        })}\n\nevent: message_delta\ndata: ${jsonEncode({
          'type': 'message_delta',
          'delta': {'stop_reason': 'end_turn', 'stop_sequence': null},
          'usage': {'output_tokens': 1},
        })}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    return http.Response(
      'data: ${jsonEncode({
        'type': 'response.completed',
        'sequence_number': 0,
        'response': {
          'id': 'r',
          'object': 'response',
          'created_at': 0,
          'status': 'completed',
          'model': 'fixture',
          'output': <Object?>[],
          'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2},
        },
      })}\n\ndata: [DONE]\n\n',
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  });
  final oc = openai.OpenAIClient(
    config: const openai.OpenAIConfig(
      authProvider: openai.ApiKeyProvider('fixture'),
      retryPolicy: openai.RetryPolicy(maxRetries: 0),
    ),
    httpClient: transport,
    streamClientFactory: () => transport,
  );
  final ac = anthropic.AnthropicClient.withApiKey(
    'fixture',
    httpClient: transport,
  );
  Future<void> run(ChatModel model, List<ContentPart> content) => model
      .stream(
        ModelRequest(
          messages: [
            ChatMessage(id: 'u', role: MessageRole.user, content: content),
          ],
        ),
        cancellation: CancellationToken(),
      )
      .drain<void>();
  try {
    await run(openai.OpenAIResponsesModel(client: oc, model: 'fixture'), parts);
    try {
      await run(openai.OpenAIResponsesModel(client: oc, model: 'fixture'), [
        DocumentPart.fileId('other', provider: 'anthropic'),
      ]);
      throw StateError('expected provider mismatch');
    } on ArgumentError catch (e) {
      print('Expected: $e');
    }
    await run(anthropic.AnthropicChatModel(client: ac, model: 'fixture'), [
      ...parts.take(2),
      DocumentPart.base64('JVBERg==', mimeType: 'application/pdf'),
    ]);
    try {
      await run(anthropic.AnthropicChatModel(client: ac, model: 'fixture'), [
        parts.last,
      ]);
      throw StateError('expected unsupported');
    } on UnsupportedError catch (e) {
      print('Expected: $e');
    }
    try {
      await run(anthropic.AnthropicChatModel(client: ac, model: 'fixture'), [
        DocumentPart.base64('aGVsbG8=', mimeType: 'application/zip'),
      ]);
      throw StateError('expected unsupported');
    } on UnsupportedError catch (e) {
      print('Expected: $e');
    }
    print('Document consumer round-trip and provider probes OK');
  } finally {
    oc.close();
    ac.close();
    transport.close();
  }
}
