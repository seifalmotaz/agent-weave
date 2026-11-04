import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart' show snapshotJson;

/// Routing options for the dedicated Image API.
final class OpenRouterImageProviderPreferences {
  final JsonObject _json;
  OpenRouterImageProviderPreferences({
    List<String>? order,
    List<String>? only,
    List<String>? ignore,
    bool? allowFallbacks,
    Object? sort,
    JsonObject? options,
    JsonObject extra = const {},
  }) : this.fromJson({
         ...extra,
         'order': ?order,
         'only': ?only,
         'ignore': ?ignore,
         'allow_fallbacks': ?allowFallbacks,
         'sort': ?sort,
         'options': ?options,
       });
  OpenRouterImageProviderPreferences.fromJson(JsonObject json)
    : _json = snapshotJson(json) {
    for (final key in ['order', 'only', 'ignore']) {
      if (_json[key] != null && !_strings(_json[key])) {
        throw ArgumentError('Invalid image provider $key.');
      }
    }
    if ((_json['allow_fallbacks'] != null &&
            _json['allow_fallbacks'] is! bool) ||
        (_json['sort'] != null &&
            _json['sort'] is! String &&
            _json['sort'] is! Map) ||
        (_json['options'] != null && _json['options'] is! Map)) {
      throw ArgumentError('Invalid image provider preferences.');
    }
    if (_json['sort'] case final Map<Object?, Object?> sort) {
      if ((sort['by'] != null && sort['by'] is! String) ||
          (sort['partition'] != null && sort['partition'] is! String)) {
        throw ArgumentError('Invalid image provider sort.');
      }
    }
    if (_json['options'] case final Map<Object?, Object?> values) {
      if (values.values.any((value) => value is! Map)) {
        throw ArgumentError('Provider options must be objects.');
      }
    }
  }
  JsonObject toJson() => _json;
}

/// Native request for the OpenRouter dedicated Image API.
final class OpenRouterImageRequest {
  final JsonObject _json;
  OpenRouterImageRequest({
    required String model,
    required String prompt,
    int? n,
    List<JsonObject>? inputReferences,
    String? resolution,
    String? aspectRatio,
    String? size,
    String? quality,
    String? background,
    String? outputFormat,
    int? outputCompression,
    int? seed,
    OpenRouterImageProviderPreferences? provider,
    String? sessionId,
    String? user,
    JsonObject? trace,
    bool? stream,
    JsonObject extra = const {},
  }) : this.fromJson({
         ...extra,
         'model': model,
         'prompt': prompt,
         'n': ?n,
         'input_references': ?inputReferences,
         'resolution': ?resolution,
         'aspect_ratio': ?aspectRatio,
         'size': ?size,
         'quality': ?quality,
         'background': ?background,
         'output_format': ?outputFormat,
         'output_compression': ?outputCompression,
         'seed': ?seed,
         if (provider != null) 'provider': provider.toJson(),
         'session_id': ?sessionId,
         'user': ?user,
         'trace': ?trace,
         'stream': ?stream,
       });
  OpenRouterImageRequest.fromJson(JsonObject json)
    : _json = snapshotJson(json) {
    if (_json['model'] is! String ||
        (_json['model'] as String).trim().isEmpty ||
        _json['prompt'] is! String ||
        (_json['prompt'] as String).isEmpty) {
      throw ArgumentError('Image generation requires a model and prompt.');
    }
    for (final key in [
      'resolution',
      'aspect_ratio',
      'size',
      'quality',
      'background',
      'output_format',
      'session_id',
      'user',
    ]) {
      if (_json.containsKey(key) && _json[key] is! String) {
        throw ArgumentError('Invalid image $key.');
      }
    }
    for (final key in ['session_id', 'user']) {
      if (_json[key] is String && (_json[key] as String).length > 256) {
        throw ArgumentError('Image $key exceeds 256 characters.');
      }
    }
    if ((_json.containsKey('n') &&
            (_json['n'] is! int ||
                (_json['n'] as int) < 1 ||
                (_json['n'] as int) > 10)) ||
        (_json.containsKey('output_compression') &&
            (_json['output_compression'] is! int ||
                (_json['output_compression'] as int) < 0 ||
                (_json['output_compression'] as int) > 100)) ||
        (_json.containsKey('seed') && _json['seed'] is! int) ||
        (_json.containsKey('stream') && _json['stream'] is! bool)) {
      throw ArgumentError('Invalid image generation options.');
    }
    if (_json.containsKey('provider')) {
      OpenRouterImageProviderPreferences.fromJson(_obj(_json['provider']));
    }
    if (_json.containsKey('trace')) _obj(_json['trace']);
    if (_json.containsKey('input_references')) {
      final refs = _json['input_references'];
      if (refs is! List || refs.length > 16) {
        throw ArgumentError('Invalid image references.');
      }
      for (final raw in refs) {
        final ref = _obj(raw);
        final image = _obj(ref['image_url']);
        if (ref['type'] != 'image_url' ||
            image['url'] is! String ||
            (image['url'] as String).isEmpty) {
          throw ArgumentError('Invalid image reference.');
        }
      }
    }
  }
  String get model => _json['model'] as String;
  String get prompt => _json['prompt'] as String;
  int? get n => _json['n'] as int?;
  List<JsonObject>? get inputReferences => _json['input_references'] == null
      ? null
      : List.unmodifiable(
          (_json['input_references'] as List).map(_responseObj),
        );
  String? get resolution => _json['resolution'] as String?;
  String? get aspectRatio => _json['aspect_ratio'] as String?;
  String? get size => _json['size'] as String?;
  String? get quality => _json['quality'] as String?;
  String? get background => _json['background'] as String?;
  String? get outputFormat => _json['output_format'] as String?;
  int? get outputCompression => _json['output_compression'] as int?;
  int? get seed => _json['seed'] as int?;
  OpenRouterImageProviderPreferences? get provider => _json['provider'] == null
      ? null
      : OpenRouterImageProviderPreferences.fromJson(
          _responseObj(_json['provider']),
        );
  String? get sessionId => _json['session_id'] as String?;
  String? get user => _json['user'] as String?;
  JsonObject? get trace =>
      _json['trace'] == null ? null : _responseObj(_json['trace']);
  bool? get stream => _json['stream'] as bool?;
  JsonObject toJson() => _json;
}

/// Image bytes and optional provider-reported media type.
final class OpenRouterImage {
  final JsonObject raw;
  OpenRouterImage.fromJson(JsonObject json) : raw = snapshotJson(json) {
    if (raw['b64_json'] is! String ||
        (raw.containsKey('media_type') && raw['media_type'] is! String)) {
      throw const FormatException('Invalid generated image.');
    }
    try {
      base64.decode(raw['b64_json'] as String);
    } on FormatException {
      throw const FormatException('Invalid generated image base64.');
    }
  }
  String get b64Json => raw['b64_json'] as String;
  Uint8List get bytes => base64.decode(b64Json);
  String? get mediaType => raw['media_type'] as String?;
}

/// Usage retains provider cost and nested metadata without numeric coercion.
final class OpenRouterImageUsage {
  final JsonObject raw;
  OpenRouterImageUsage.fromJson(JsonObject json) : raw = snapshotJson(json) {
    for (final key in ['prompt_tokens', 'completion_tokens', 'total_tokens']) {
      if (raw[key] is! int) throw const FormatException('Invalid image usage.');
    }
    if (raw['cost'] != null && raw['cost'] is! num) {
      throw const FormatException('Invalid image usage cost.');
    }
  }
  int get promptTokens => raw['prompt_tokens'] as int;
  int get completionTokens => raw['completion_tokens'] as int;
  int get totalTokens => raw['total_tokens'] as int;
  num? get cost => raw['cost'] as num?;
}

/// A buffered Image API response.
final class OpenRouterImageResponse {
  final JsonObject raw;
  late final List<OpenRouterImage> data;
  late final OpenRouterImageUsage? usage;
  OpenRouterImageResponse.fromJson(JsonObject json) : raw = snapshotJson(json) {
    if (raw['created'] is! int || raw['data'] is! List) {
      throw const FormatException('Invalid image response.');
    }
    data = List.unmodifiable(
      (raw['data'] as List).map(
        (value) => OpenRouterImage.fromJson(_responseObj(value)),
      ),
    );
    usage = raw['usage'] == null
        ? null
        : OpenRouterImageUsage.fromJson(_responseObj(raw['usage']));
  }
  int get created => raw['created'] as int;
}

sealed class OpenRouterImageStreamEvent {
  const OpenRouterImageStreamEvent();
  factory OpenRouterImageStreamEvent.fromJson(JsonObject json) {
    final raw = snapshotJson(json);
    return switch (raw['type']) {
      'image_generation.partial_image' => OpenRouterImagePartial._(raw),
      'image_generation.text_chunk' => OpenRouterImageText._(raw),
      'image_generation.completed' => OpenRouterImageCompleted._(raw),
      'error' => OpenRouterImageError._(raw),
      _ => throw const FormatException('Unknown image stream event.'),
    };
  }
}

final class OpenRouterImagePartial extends OpenRouterImageStreamEvent {
  final JsonObject raw;
  late final OpenRouterImage image;
  OpenRouterImagePartial._(this.raw) {
    if (raw['partial_image_index'] is! int ||
        (raw['partial_image_index'] as int) < 0) {
      throw const FormatException('Invalid partial image index.');
    }
    image = OpenRouterImage.fromJson({'b64_json': raw['b64_json']});
  }
  int get index => raw['partial_image_index'] as int;
}

final class OpenRouterImageText extends OpenRouterImageStreamEvent {
  final JsonObject raw;
  OpenRouterImageText._(this.raw) {
    if (raw['text'] is! String || raw['phase'] is! String) {
      throw const FormatException('Invalid image text event.');
    }
  }
  String get text => raw['text'] as String;
  String get phase => raw['phase'] as String;
}

final class OpenRouterImageCompleted extends OpenRouterImageStreamEvent {
  final JsonObject raw;
  late final OpenRouterImage image;
  late final OpenRouterImageUsage? usage;
  OpenRouterImageCompleted._(this.raw) {
    if (raw['created'] is! int) {
      throw const FormatException('Invalid image completion.');
    }
    image = OpenRouterImage.fromJson({
      'b64_json': raw['b64_json'],
      if (raw.containsKey('media_type')) 'media_type': raw['media_type'],
    });
    usage = raw['usage'] == null
        ? null
        : OpenRouterImageUsage.fromJson(_responseObj(raw['usage']));
  }
  int get created => raw['created'] as int;
}

final class OpenRouterImageError extends OpenRouterImageStreamEvent {
  final JsonObject raw;
  late final JsonObject error;
  String get message => error['message'] as String;
  String? get code => error['code'] as String?;
  String? get param => error['param'] as String?;
  String? get errorType => error['type'] as String?;
  OpenRouterImageError._(this.raw) {
    error = _responseObj(raw['error']);
    if (error['message'] is! String) {
      throw const FormatException('Invalid image stream error.');
    }
    for (final key in ['code', 'param', 'type']) {
      if (error[key] != null && error[key] is! String) {
        throw const FormatException('Invalid image stream error.');
      }
    }
  }
}

/// Buffered fallback from a provider without native SSE support.
final class OpenRouterImageBuffered extends OpenRouterImageStreamEvent {
  final OpenRouterImageResponse response;
  const OpenRouterImageBuffered(this.response);
}

sealed class OpenRouterImageCapability {
  final JsonObject raw;
  const OpenRouterImageCapability(this.raw);
  factory OpenRouterImageCapability.fromJson(JsonObject input) {
    final raw = snapshotJson(input);
    return switch (raw['type']) {
      'enum' => OpenRouterImageEnumCapability._(raw),
      'range' => OpenRouterImageRangeCapability._(raw),
      'boolean' => OpenRouterImageBooleanCapability._(raw),
      String() => OpenRouterImageUnknownCapability._(raw),
      _ => throw const FormatException('Invalid image capability.'),
    };
  }
}

final class OpenRouterImageEnumCapability extends OpenRouterImageCapability {
  OpenRouterImageEnumCapability._(super.raw) {
    if (!_strings(raw['values'])) {
      throw const FormatException('Invalid enum capability.');
    }
  }
  List<String> get values =>
      List.unmodifiable((raw['values'] as List).cast<String>());
}

final class OpenRouterImageRangeCapability extends OpenRouterImageCapability {
  OpenRouterImageRangeCapability._(super.raw) {
    if (raw['min'] is! num || raw['max'] is! num) {
      throw const FormatException('Invalid range capability.');
    }
  }
  num get min => raw['min'] as num;
  num get max => raw['max'] as num;
}

final class OpenRouterImageBooleanCapability extends OpenRouterImageCapability {
  const OpenRouterImageBooleanCapability._(super.raw);
}

final class OpenRouterImageUnknownCapability extends OpenRouterImageCapability {
  const OpenRouterImageUnknownCapability._(super.raw);
}

Map<String, OpenRouterImageCapability> _capabilities(Object? value) =>
    Map.unmodifiable(
      _responseObj(value).map(
        (key, value) => MapEntry(
          key,
          OpenRouterImageCapability.fromJson(_responseObj(value)),
        ),
      ),
    );

final class OpenRouterImagePricing {
  final JsonObject raw;
  OpenRouterImagePricing.fromJson(JsonObject json) : raw = snapshotJson(json) {
    if (raw['billable'] is! String ||
        raw['unit'] is! String ||
        raw['cost_usd'] is! num ||
        (raw['variant'] != null && raw['variant'] is! String)) {
      throw const FormatException('Invalid image endpoint pricing.');
    }
  }
  String get billable => raw['billable'] as String;
  String get unit => raw['unit'] as String;
  num get costUsd => raw['cost_usd'] as num;
  String? get variant => raw['variant'] as String?;
}

final class OpenRouterImageEndpoint {
  final JsonObject raw;
  late final Map<String, OpenRouterImageCapability> supportedParameters;
  late final List<OpenRouterImagePricing> pricing;
  OpenRouterImageEndpoint.fromJson(JsonObject json) : raw = snapshotJson(json) {
    if (raw['provider_name'] is! String ||
        raw['provider_slug'] is! String ||
        !raw.containsKey('provider_tag') ||
        (raw['provider_tag'] != null && raw['provider_tag'] is! String) ||
        raw['supports_streaming'] is! bool ||
        !_strings(raw['allowed_passthrough_parameters']) ||
        raw['pricing'] is! List) {
      throw const FormatException('Invalid image endpoint.');
    }
    supportedParameters = _capabilities(raw['supported_parameters']);
    pricing = List.unmodifiable(
      (raw['pricing'] as List).map(
        (value) => OpenRouterImagePricing.fromJson(_responseObj(value)),
      ),
    );
  }
  String get providerName => raw['provider_name'] as String;
  String get providerSlug => raw['provider_slug'] as String;
  String? get providerTag => raw['provider_tag'] as String?;
  bool get supportsStreaming => raw['supports_streaming'] as bool;
  List<String> get allowedPassthroughParameters => List.unmodifiable(
    (raw['allowed_passthrough_parameters'] as List).cast<String>(),
  );
}

final class OpenRouterImageModelInfo {
  final JsonObject raw;
  late final Map<String, OpenRouterImageCapability> supportedParameters;
  OpenRouterImageModelInfo.fromJson(JsonObject json)
    : raw = snapshotJson(json) {
    if (raw['id'] is! String ||
        raw['name'] is! String ||
        raw['description'] is! String ||
        raw['created'] is! int ||
        raw['supports_streaming'] is! bool ||
        raw['endpoints'] is! String) {
      throw const FormatException('Invalid image model.');
    }
    final architecture = _responseObj(raw['architecture']);
    if (!_strings(architecture['input_modalities']) ||
        !_strings(architecture['output_modalities'])) {
      throw const FormatException('Invalid image architecture.');
    }
    supportedParameters = _capabilities(raw['supported_parameters']);
  }
  String get id => raw['id'] as String;
  String get name => raw['name'] as String;
  String get description => raw['description'] as String;
  int get created => raw['created'] as int;
  bool get supportsStreaming => raw['supports_streaming'] as bool;
  String get endpoints => raw['endpoints'] as String;
  JsonObject get architecture => _responseObj(raw['architecture']);
}

final class OpenRouterImageModels {
  final JsonObject raw;
  late final List<OpenRouterImageModelInfo> data;
  OpenRouterImageModels.fromJson(JsonObject json) : raw = snapshotJson(json) {
    if (raw['data'] is! List) {
      throw const FormatException('Invalid image model list.');
    }
    data = List.unmodifiable(
      (raw['data'] as List).map(
        (value) => OpenRouterImageModelInfo.fromJson(_responseObj(value)),
      ),
    );
  }
}

final class OpenRouterImageModelEndpoints {
  final JsonObject raw;
  late final List<OpenRouterImageEndpoint> endpoints;
  OpenRouterImageModelEndpoints.fromJson(JsonObject json)
    : raw = snapshotJson(json) {
    if (raw['id'] is! String || raw['endpoints'] is! List) {
      throw const FormatException('Invalid image model endpoints.');
    }
    endpoints = List.unmodifiable(
      (raw['endpoints'] as List).map(
        (value) => OpenRouterImageEndpoint.fromJson(_responseObj(value)),
      ),
    );
  }
  String get id => raw['id'] as String;
}

bool _strings(Object? value) =>
    value is List && value.every((v) => v is String);
JsonObject _obj(Object? value) {
  if (value is! Map<String, Object?>) {
    throw ArgumentError('Expected a JSON object.');
  }
  return value;
}

JsonObject _responseObj(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}
