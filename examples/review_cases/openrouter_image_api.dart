import 'dart:convert';

import 'package:agent_weave_openrouter/agent_weave_openrouter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  var requests = 0;
  final client = OpenRouterClient.withApiKey(
    apiKey: 'offline-fixture-key',
    httpClient: MockClient((request) async {
      requests++;
      check(request.url.path == '/api/v1/images', 'dedicated endpoint');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      check(body['model'] == 'fixture/image', 'model');
      if (body['prompt'] == 'stream') {
        return http.Response(
          'data: {"type":"image_generation.partial_image","partial_image_index":0,"b64_json":"eA=="}\n\n'
          'data: {"data":{"type":"image_generation.text_chunk","text":"draft","phase":"draft"}}\n\n'
          'data: {"data":{"type":"image_generation.completed","created":1,"b64_json":"eA=="}}\n\n'
          'data: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      return http.Response(
        '{"created":1,"data":[{"b64_json":"eA=="}]}',
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  try {
    final model = OpenRouterImageModel(client: client);
    final buffered = await model.generate(
      OpenRouterImageRequest(model: 'fixture/image', prompt: 'buffered'),
    );
    check(buffered.data.single.bytes.single == 120, 'buffered bytes');
    check(buffered.data.single.mediaType == null, 'unknown media type');
    final events = await model
        .stream(
          OpenRouterImageRequest(model: 'fixture/image', prompt: 'stream'),
        )
        .toList();
    check(events[0] is OpenRouterImagePartial, 'partial');
    check((events[1] as OpenRouterImageText).phase == 'draft', 'text phase');
    check(events[2] is OpenRouterImageCompleted, 'final');
    final fallback = await model
        .stream(
          OpenRouterImageRequest(model: 'fixture/image', prompt: 'fallback'),
        )
        .toList();
    check(fallback.single is OpenRouterImageBuffered, 'buffered fallback');
    check(requests == 3, 'one request per invocation');
    print('PASS dedicated image buffered, stream, and fallback');
  } finally {
    client.close();
  }
}
