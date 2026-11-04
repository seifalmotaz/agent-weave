import 'dart:convert';

import 'package:agent_weave_openrouter/src/image_types.dart';
import 'package:test/test.dart';

void main() {
  test('request snapshots all native options and preserves future values', () {
    final extra = <String, Object?>{
      'future': {
        'nested': [1],
      },
    };
    final providerOptions = <String, Object?>{
      'vendor': {'steps': 20},
    };
    final request = OpenRouterImageRequest(
      model: 'vendor/model',
      prompt: 'Draw',
      n: 2,
      inputReferences: [
        {
          'type': 'image_url',
          'image_url': {'url': 'https://example.com/a'},
        },
      ],
      resolution: 'future-tier',
      aspectRatio: '16:9',
      size: '2K',
      quality: 'high',
      background: 'transparent',
      outputFormat: 'webp',
      outputCompression: 80,
      seed: 123,
      provider: OpenRouterImageProviderPreferences(
        only: ['vendor'],
        order: ['vendor'],
        ignore: ['other'],
        allowFallbacks: false,
        sort: {'by': 'price', 'partition': 'model'},
        options: providerOptions,
      ),
      sessionId: 'session',
      user: 'user',
      trace: {'trace_id': 't', 'custom': true},
      stream: true,
      extra: extra,
    );
    (extra['future'] as Map)['nested'] = <int>[];
    (providerOptions['vendor'] as Map)['steps'] = 1;
    expect(
      request.toJson().keys,
      containsAll([
        'model',
        'prompt',
        'n',
        'input_references',
        'resolution',
        'aspect_ratio',
        'size',
        'quality',
        'background',
        'output_format',
        'output_compression',
        'seed',
        'provider',
        'session_id',
        'user',
        'trace',
        'stream',
        'future',
      ]),
    );
    expect((request.toJson()['future'] as Map)['nested'], [1]);
    expect(
      ((request.provider!.toJson()['options'] as Map)['vendor']
          as Map)['steps'],
      20,
    );
    expect(request.resolution, 'future-tier');
    expect(
      OpenRouterImageRequest.fromJson(request.toJson()).toJson(),
      request.toJson(),
    );
    expect(
      () => ((request.toJson()['future'] as Map)['nested'] as List).clear(),
      throwsUnsupportedError,
    );
  });
  test('request rejects malformed known fields and declared bounds', () {
    final good = <String, Object?>{'model': 'm', 'prompt': 'p'};
    for (final patch in <Map<String, Object?>>[
      {'model': ''},
      {'prompt': ''},
      {'n': 0},
      {'n': 11},
      {'n': null},
      {'seed': 'bad'},
      {'output_compression': 101},
      {'stream': 'true'},
      {
        'input_references': [
          {
            'type': 'image_url',
            'image_url': {'url': 1},
          },
        ],
      },
      {
        'input_references': List.filled(17, {
          'type': 'image_url',
          'image_url': {'url': 'x'},
        }),
      },
      {
        'provider': {
          'order': [1],
        },
      },
      {'session_id': 'x' * 257},
    ]) {
      expect(
        () => OpenRouterImageRequest.fromJson({...good, ...patch}),
        throwsArgumentError,
        reason: '$patch',
      );
    }
  });
  test('buffered response retains unknown mime, SVG bytes and usage', () {
    final svg = base64Encode(utf8.encode('<svg/>'));
    final input = <String, Object?>{
      'created': 1,
      'data': [
        {'b64_json': svg, 'media_type': 'image/svg+xml'},
        {'b64_json': 'YQ=='},
      ],
      'usage': {
        'prompt_tokens': 1,
        'completion_tokens': 2,
        'total_tokens': 3,
        'cost': 0.25,
        'cost_details': {'upstream': 9},
      },
    };
    final result = OpenRouterImageResponse.fromJson(input);
    expect(utf8.decode(result.data.first.bytes), '<svg/>');
    expect(result.data.first.mediaType, 'image/svg+xml');
    expect(result.data.last.mediaType, isNull);
    expect(result.usage!.cost, 0.25);
    expect((result.usage!.raw['cost_details'] as Map)['upstream'], 9);
    expect(
      () => OpenRouterImageResponse.fromJson({
        'created': 1,
        'data': [
          {'b64_json': '***'},
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => OpenRouterImageResponse.fromJson({
        'created': 1,
        'data': <Object?>[],
        'usage': {'cost': 2},
      }),
      throwsFormatException,
    );
  });
  test(
    'stream event variants keep native fields and buffered fallback intact',
    () {
      final partial =
          OpenRouterImageStreamEvent.fromJson({
                'type': 'image_generation.partial_image',
                'partial_image_index': 1,
                'b64_json': 'YQ==',
              })
              as OpenRouterImagePartial;
      expect(partial.index, 1);
      final text =
          OpenRouterImageStreamEvent.fromJson({
                'type': 'image_generation.text_chunk',
                'phase': 'future',
                'text': '<svg>',
              })
              as OpenRouterImageText;
      expect(text.phase, 'future');
      final completed =
          OpenRouterImageStreamEvent.fromJson({
                'type': 'image_generation.completed',
                'created': 5,
                'b64_json': 'YQ==',
                'usage': {
                  'prompt_tokens': 0,
                  'completion_tokens': 1,
                  'total_tokens': 1,
                },
              })
              as OpenRouterImageCompleted;
      expect(completed.image.mediaType, isNull);
      expect(completed.usage!.totalTokens, 1);
      final error =
          OpenRouterImageStreamEvent.fromJson({
                'type': 'error',
                'error': {'message': 'bad', 'code': null, 'future': 1},
              })
              as OpenRouterImageError;
      expect(error.error['future'], 1);
      final response = OpenRouterImageResponse.fromJson({
        'created': 8,
        'data': [
          {'b64_json': 'YQ=='},
          {'b64_json': 'Yg=='},
        ],
      });
      expect(OpenRouterImageBuffered(response).response.data, hasLength(2));
      expect(
        () => OpenRouterImageStreamEvent.fromJson({'type': 'future'}),
        throwsFormatException,
      );
      expect(
        () => OpenRouterImageStreamEvent.fromJson({
          'type': 'image_generation.partial_image',
          'partial_image_index': -1,
          'b64_json': 'YQ==',
        }),
        throwsFormatException,
      );
    },
  );
  test('discovery exposes endpoint-specific capability unions and pricing', () {
    final caps = <String, Object?>{
      'resolution': {
        'type': 'enum',
        'values': ['1K', '2K'],
      },
      'compression': {'type': 'range', 'min': 0, 'max': 100},
      'seed': {'type': 'boolean'},
      'future': {
        'type': 'future',
        'nested': {'a': 1},
      },
    };
    final models = OpenRouterImageModels.fromJson({
      'data': [
        {
          'id': 'v/m',
          'name': 'Name',
          'description': 'desc',
          'created': 1,
          'architecture': {
            'input_modalities': ['text'],
            'output_modalities': ['image'],
          },
          'supported_parameters': caps,
          'supports_streaming': true,
          'endpoints': '/api/v1/images/models/v/m/endpoints',
        },
      ],
    });
    expect(
      models.data.single.supportedParameters['future'],
      isA<OpenRouterImageUnknownCapability>(),
    );
    final endpoints = OpenRouterImageModelEndpoints.fromJson({
      'id': 'v/m',
      'endpoints': [
        {
          'provider_name': 'Vendor',
          'provider_slug': 'v',
          'provider_tag': null,
          'supported_parameters': caps,
          'allowed_passthrough_parameters': ['steps'],
          'supports_streaming': true,
          'pricing': [
            {'billable': 'output_image', 'unit': 'image', 'cost_usd': 0.05},
          ],
        },
      ],
    });
    final endpoint = endpoints.endpoints.single;
    expect(
      (endpoint.supportedParameters['resolution']
              as OpenRouterImageEnumCapability)
          .values,
      ['1K', '2K'],
    );
    expect(
      (endpoint.supportedParameters['compression']
              as OpenRouterImageRangeCapability)
          .max,
      100,
    );
    expect(
      endpoint.supportedParameters['seed'],
      isA<OpenRouterImageBooleanCapability>(),
    );
    expect(endpoint.pricing.single.costUsd, 0.05);
    expect(endpoint.allowedPassthroughParameters, ['steps']);
    (caps['future'] as Map)['nested'] = {'a': 2};
    expect(
      ((endpoint.supportedParameters['future']!.raw['nested'] as Map)['a']),
      1,
    );
    expect(
      () => OpenRouterImageCapability.fromJson({'type': 'range', 'min': 0}),
      throwsFormatException,
    );
  });
}
