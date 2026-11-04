import 'dart:convert';
import 'dart:io';

import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final schema = jsonDecode(await apiSchema()) as Map<String, dynamic>;
  final properties =
      schema['components']['schemas']['ImageGenerationRequest']['properties']
          as Map;
  final input = api.OpenRouterImageRequest(
    model: 'fixture/model',
    prompt: 'Draw',
    n: 2,
    inputReferences: [
      {
        'type': 'image_url',
        'image_url': {'url': 'https://example.test/image.png'},
      },
    ],
    resolution: '2K',
    aspectRatio: '16:9',
    size: '2K',
    quality: 'high',
    background: 'auto',
    outputFormat: 'svg',
    outputCompression: 75,
    seed: 7,
    provider: api.OpenRouterImageProviderPreferences(
      order: ['vendor'],
      only: ['vendor'],
      ignore: ['other'],
      allowFallbacks: false,
      sort: {'by': 'price'},
      options: {
        'vendor': {'steps': 4},
      },
    ),
    sessionId: 'session',
    user: 'user',
    trace: {'trace_id': 'trace'},
    stream: false,
    extra: {
      'future_option': {'nested': true},
    },
  );
  final providerFields =
      schema['components']['schemas']['ImageGenerationProviderPreferences']['properties']
          as Map;
  final raw = input.toJson();
  check(
    providerFields.keys.every((raw['provider'] as Map).containsKey),
    'Image provider fields missing',
  );
  check(
    properties.keys.every(raw.containsKey) && raw['future_option'] is Map,
    'Image request fields missing',
  );
  final bodies = <Map<String, dynamic>>[];
  var call = 0;
  final client = api.OpenRouterClient.withApiKey(
    apiKey: 'fixture-key',
    httpClient: MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      call++;
      if (call == 1) {
        return http.Response(
          '{"created":1,"data":[{"b64_json":"PHN2Zy8+","media_type":"image/svg+xml"}]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (call == 2) {
        return http.Response(
          [
            'data: {"type":"image_generation.partial_image","partial_image_index":0,"b64_json":"YQ=="}\n\n',
            'data: {"data":{"type":"image_generation.text_chunk","phase":"content","text":"<svg/>"}}\n\n',
            'data: {"type":"image_generation.completed","created":2,"b64_json":"YQ=="}\n\n',
            'data: [DONE]\n\n',
          ].join(),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      if (call == 3) {
        return http.Response(
          'data: {"data":{"type":"error","error":{"message":"failed"}}}\n\ndata: [DONE]\n\n',
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      }
      return http.Response(
        '{"created":3,"data":[{"b64_json":"YQ=="},{"b64_json":"Yg=="}]}',
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  try {
    final model = api.OpenRouterImageModel(client: client);
    final generated = await model.generate(input);
    check(
      generated.data.single.mediaType == 'image/svg+xml',
      'Image MIME lost',
    );
    final stream = await model.stream(input).toList();
    check(
      stream.length == 3 &&
          stream[0] is api.OpenRouterImagePartial &&
          stream[1] is api.OpenRouterImageText &&
          stream[2] is api.OpenRouterImageCompleted,
      'Image stream union changed',
    );
    final errors = await model.stream(input).toList();
    check(
      errors.single is api.OpenRouterImageError,
      'Image stream error missing',
    );
    final fallback = await model.stream(input).toList();
    check(
      fallback.single is api.OpenRouterImageBuffered &&
          (fallback.single as api.OpenRouterImageBuffered)
                  .response
                  .data
                  .length ==
              2,
      'Buffered fallback changed',
    );
    check(
      bodies[0]['stream'] == false &&
          bodies.skip(1).every((b) => b['stream'] == true),
      'Stream ownership changed',
    );
    check(
      bodies.every(
        (body) =>
            properties.keys.every(body.containsKey) &&
            body['future_option'] is Map &&
            body['provider'] is Map,
      ),
      'Native request options lost',
    );
    print(
      'PASS OpenRouter Image API executable contract: 17 fields, buffered + four SSE variants + fallback; offline fixture.',
    );
  } finally {
    client.close();
  }
}

Future<String> apiSchema() async =>
    (await File('tool/contracts/openrouter/openapi.json').readAsString());
