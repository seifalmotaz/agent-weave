/// Vercel AI Gateway public compatible endpoints.
library;

import 'dart:async';
import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:http/http.dart' as http;

export 'package:agent_weave_http/agent_weave_http.dart'
    show JsonSseEvent, JsonSseData, JsonSseDone, JsonHttpException;

JsonObject _snapshot(JsonObject value) => snapshotJson(value);

JsonHttpException _safeError(
  JsonHttpException error,
  GatewayCredentials? credentials,
) {
  final secrets = <String>{if (credentials != null) credentials._token};
  void collect(Object? value) {
    if (value is String && value.isNotEmpty) {
      secrets.add(value);
    } else if (value is Map) {
      for (final entry in value.entries) {
        collect(entry.value);
      }
    } else if (value is List) {
      for (final item in value) {
        collect(item);
      }
    }
  }

  collect(credentials?._byok);
  final variants = <String>{};
  for (final secret in secrets) {
    if (secret.isEmpty) continue;
    variants.add(secret);
    final encoded = jsonEncode(secret);
    variants.add(encoded.substring(1, encoded.length - 1));
  }
  final sorted = variants.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  String redact(String value) {
    for (final secret in sorted) {
      value = value.replaceAll(secret, '[REDACTED]');
    }
    return value;
  }

  Object? clean(Object? value) => switch (value) {
    String text => redact(text),
    Map<String, Object?> map => <String, Object?>{
      for (final entry in map.entries) redact(entry.key): clean(entry.value),
    },
    List<Object?> list => list.map(clean).toList(),
    _ => value,
  };
  return JsonHttpException(
    'Gateway request failed',
    statusCode: error.statusCode,
    requestId: error.requestId == null ? null : redact(error.requestId!),
    details: error.details == null ? null : clean(error.details) as JsonObject,
    responseHeaders: {
      for (final entry in error.responseHeaders.entries)
        redact(entry.key): redact(entry.value),
    },
  );
}

void _checkPublicOptions(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase().replaceAll(
        RegExp('[^a-z]'),
        '',
      );
      if (key.contains('apikey') ||
          key.contains('authorization') ||
          key.contains('credential') ||
          key.contains('secret') ||
          {
            'token',
            'accesstoken',
            'refreshtoken',
            'bearertoken',
            'byok',
          }.contains(key)) {
        throw ArgumentError(
          'Credentials must be supplied by credentialResolver.',
        );
      }
      _checkPublicOptions(entry.value);
    }
  } else if (value is List) {
    for (final item in value) {
      _checkPublicOptions(item);
    }
  }
}

enum GatewayCaching { auto }

enum GatewayServiceTier { flex, priority }

enum GatewayProviderSort { cost, tps, ttft }

/// Gateway routing options. These values must not contain credentials.
final class GatewayOptions {
  final List<String>? models;
  final List<String>? order;
  final List<String>? only;
  final GatewayCaching? caching;
  final Map<String, int>? byokProviderTimeouts;
  final bool? disallowPromptTraining;
  final bool? zeroDataRetention;
  final List<String>? has;
  final String? quotaEntityId;
  final GatewayServiceTier? serviceTier;
  final GatewayProviderSort? sort;
  final List<String>? tags;
  final String? user;
  final JsonObject extra;

  GatewayOptions({
    List<String>? models,
    List<String>? order,
    List<String>? only,
    this.caching,
    Map<String, int>? byokProviderTimeouts,
    this.disallowPromptTraining,
    this.zeroDataRetention,
    List<String>? has,
    this.quotaEntityId,
    this.serviceTier,
    this.sort,
    List<String>? tags,
    this.user,
    JsonObject extra = const {},
  }) : extra = snapshotJson(extra),
       models = models == null ? null : List.unmodifiable(models),
       order = order == null ? null : List.unmodifiable(order),
       only = only == null ? null : List.unmodifiable(only),
       byokProviderTimeouts = byokProviderTimeouts == null
           ? null
           : Map.unmodifiable(byokProviderTimeouts),
       has = has == null ? null : List.unmodifiable(has),
       tags = tags == null ? null : List.unmodifiable(tags) {
    _checkPublicOptions(this.extra);
    const owned = {
      'byok',
      'models',
      'order',
      'only',
      'caching',
      'providerTimeouts',
      'disallowPromptTraining',
      'zeroDataRetention',
      'has',
      'quotaEntityId',
      'serviceTier',
      'sort',
      'tags',
      'user',
      'experimental_streamingImageDecoding',
    };
    if (extra.keys.any(owned.contains)) {
      throw ArgumentError(
        'Extra gateway options cannot replace typed options, credentials or SDK-only image decoding.',
      );
    }
    if (byokProviderTimeouts?.values.any(
          (value) => value < 1000 || value > 789000,
        ) ??
        false) {
      throw ArgumentError(
        'Provider timeout must be between 1000 and 789000 milliseconds.',
      );
    }
  }

  JsonObject toJson() => {
    ...extra,
    'models': ?models,
    'order': ?order,
    'only': ?only,
    'caching': ?caching?.name,
    if (byokProviderTimeouts != null)
      'providerTimeouts': {'byok': byokProviderTimeouts},
    'disallowPromptTraining': ?disallowPromptTraining,
    'zeroDataRetention': ?zeroDataRetention,
    'has': ?has,
    'quotaEntityId': ?quotaEntityId,
    'serviceTier': ?serviceTier?.name,
    'sort': ?sort?.name,
    'tags': ?tags,
    'user': ?user,
  };
}

/// Resolved separately for each request. Never serialize this object to logs.
final class GatewayCredentials {
  final String _token;
  final JsonObject? _byok;
  GatewayCredentials({required String token, JsonObject? byok})
    : _token = token,
      _byok = byok == null ? null : _snapshot(byok) {
    if (token.trim().isEmpty) {
      throw ArgumentError('Gateway token must not be empty.');
    }
    if (_byok != null &&
        _byok.values.any(
          (value) =>
              value is! List ||
              value.any((item) => item is! Map<String, Object?>),
        )) {
      throw ArgumentError(
        'BYOK must map provider names to arrays of credential objects.',
      );
    }
  }
  @override
  String toString() => 'GatewayCredentials(redacted)';
}

typedef GatewayCredentialResolver = FutureOr<GatewayCredentials> Function();

/// Parsed native JSON and HTTP metadata for one request.
final class GatewayResponse {
  final JsonObject data;
  final int statusCode;
  final Map<String, String> headers;
  GatewayResponse({
    required JsonObject data,
    required this.statusCode,
    required Map<String, String> headers,
  }) : data = _snapshot(data),
       headers = Map.unmodifiable(headers);
}

/// Backend-only client. The caller owns the supplied transport.
final class GatewayClient {
  final JsonHttpClient transport;
  final GatewayCredentialResolver credentialResolver;
  final bool _ownsTransport;

  GatewayClient({
    required this.credentialResolver,
    String baseUrl = 'https://ai-gateway.vercel.sh',
    Duration requestTimeout = const Duration(minutes: 2),
    http.Client? httpClient,
  }) : transport = JsonHttpClient(
         baseUrl: baseUrl,
         requestTimeout: requestTimeout,
         httpClient: httpClient,
       ),
       _ownsTransport = true;

  GatewayClient.withTransport({
    required this.transport,
    required this.credentialResolver,
  }) : _ownsTransport = false;

  factory GatewayClient.withApiKey({
    required String apiKey,
    String baseUrl = 'https://ai-gateway.vercel.sh',
    Duration requestTimeout = const Duration(minutes: 2),
    http.Client? httpClient,
  }) => GatewayClient(
    credentialResolver: () => GatewayCredentials(token: apiKey),
    baseUrl: baseUrl,
    requestTimeout: requestTimeout,
    httpClient: httpClient,
  );

  void close() {
    if (_ownsTransport) transport.close();
  }

  JsonHttpRequest _prepare(
    JsonObject body,
    GatewayOptions? options,
    JsonObject providerOptions,
    GatewayCredentials credentials,
  ) {
    final gateway = <String, Object?>{
      ...?options?.toJson(),
      'byok': ?credentials._byok,
    };
    return JsonHttpRequest(
      body: {
        ...body,
        if (providerOptions.isNotEmpty || gateway.isNotEmpty)
          'providerOptions': {
            ...providerOptions,
            if (gateway.isNotEmpty) 'gateway': gateway,
          },
      },
      headers: {'Authorization': 'Bearer ${credentials._token}'},
    );
  }

  (JsonObject, JsonObject) _body(JsonObject body) {
    final copy = Map<String, Object?>.from(_snapshot(body));
    final raw = copy.remove('providerOptions');
    if (raw != null && raw is! Map<String, Object?>) {
      throw ArgumentError('providerOptions must be an object.');
    }
    final providers = raw as Map<String, Object?>? ?? <String, Object?>{};
    if (providers.containsKey('gateway')) {
      throw ArgumentError(
        'Set gateway routing with GatewayOptions and credentials with credentialResolver.',
      );
    }
    _checkPublicOptions(providers);
    return (copy, providers);
  }

  Future<GatewayResponse> _create(
    String path,
    JsonObject body,
    GatewayOptions? options,
    CancellationToken? cancellation,
  ) async {
    final (request, providers) = _body(body);
    if (request['stream'] == true) {
      throw ArgumentError(
        'Use streamChat or streamResponse for streaming requests.',
      );
    }
    GatewayCredentials? credentials;
    try {
      final response = await transport.sendJson(
        path,
        cancellation: cancellation,
        prepare: () async {
          try {
            credentials = await credentialResolver();
          } catch (_) {
            throw JsonHttpException('Credential resolution failed');
          }
          return _prepare(request, options, providers, credentials!);
        },
      );
      Object? decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw const FormatException('Invalid gateway JSON response.');
      }
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Expected a JSON object response.');
      }
      return GatewayResponse(
        data: decoded,
        statusCode: response.statusCode,
        headers: response.headers,
      );
    } on JsonHttpException catch (error) {
      throw _safeError(error, credentials);
    }
  }

  Stream<JsonSseEvent> _stream(
    String path,
    JsonObject body,
    GatewayOptions? options,
    CancellationToken? cancellation,
  ) {
    final (request, providers) = _body({...body, 'stream': true});
    GatewayCredentials? credentials;
    var finished = false;
    var done = false;
    var failed = false;
    return transport
        .streamJson(
          path,
          cancellation: cancellation,
          prepare: () async {
            try {
              credentials = await credentialResolver();
            } catch (_) {
              throw JsonHttpException('Credential resolution failed');
            }
            return _prepare(request, options, providers, credentials!);
          },
        )
        .transform(
          StreamTransformer<JsonSseEvent, JsonSseEvent>.fromHandlers(
            handleData: (event, sink) {
              if (failed) return;
              if (event is JsonSseData) {
                final data = event.data;
                if (event.event == 'error' ||
                    data.containsKey('error') ||
                    data['type'] == 'error' ||
                    data['type'] == 'response.failed') {
                  failed = true;
                  sink.addError(
                    _safeError(
                      JsonHttpException(
                        'Gateway stream failed',
                        details: data,
                        responseHeaders: event.responseHeaders,
                        requestId:
                            event.responseHeaders['x-request-id'] ??
                            event.responseHeaders['request-id'],
                      ),
                      credentials,
                    ),
                  );
                  return;
                }
                if (path == '/v1/responses' &&
                    (data['type'] == 'response.completed' ||
                        data['type'] == 'response.incomplete')) {
                  finished = true;
                }
                if (path == '/v1/chat/completions' &&
                    data['choices'] is List &&
                    (data['choices'] as List).any(
                      (choice) =>
                          choice is Map && choice['finish_reason'] != null,
                    )) {
                  finished = true;
                }
              } else if (event is JsonSseDone) {
                done = true;
              }
              sink.add(event);
            },
            handleError: (error, stack, sink) {
              failed = true;
              if (error is JsonHttpException) {
                sink.addError(_safeError(error, credentials), stack);
              } else {
                sink.addError(error, stack);
              }
            },
            handleDone: (sink) {
              if (!failed &&
                  (!finished || (path == '/v1/chat/completions' && !done))) {
                sink.addError(
                  JsonHttpException('Gateway stream ended before completion'),
                );
              }
              sink.close();
            },
          ),
        );
  }

  Future<GatewayResponse> createChat(
    JsonObject body, {
    GatewayOptions? options,
    CancellationToken? cancellation,
  }) => _create('/v1/chat/completions', body, options, cancellation);
  Stream<JsonSseEvent> streamChat(
    JsonObject body, {
    GatewayOptions? options,
    CancellationToken? cancellation,
  }) => _stream('/v1/chat/completions', body, options, cancellation);
  Future<GatewayResponse> createResponse(
    JsonObject body, {
    GatewayOptions? options,
    CancellationToken? cancellation,
  }) => _create('/v1/responses', body, options, cancellation);
  Stream<JsonSseEvent> streamResponse(
    JsonObject body, {
    GatewayOptions? options,
    CancellationToken? cancellation,
  }) => _stream('/v1/responses', body, options, cancellation);
}

Stream<JsonObject> _data(Stream<JsonSseEvent> events) => events
    .where((event) => event is JsonSseData)
    .map((event) => (event as JsonSseData).data);

final class GatewayChatModel implements ChatModel {
  final GatewayClient client;
  final String model;
  final GatewayOptions? options;
  final JsonObject providerOptions;
  final api.ChatCompletionCreateRequest Function(
    api.ChatCompletionCreateRequest,
  )?
  configure;
  GatewayChatModel({
    required this.client,
    required this.model,
    this.options,
    JsonObject providerOptions = const {},
    this.configure,
  }) : providerOptions = _snapshot(providerOptions) {
    _checkPublicOptions(this.providerOptions);
  }
  api.ChatCompletionsProtocolModel get _delegate =>
      api.ChatCompletionsProtocolModel(
        model: model,
        configure: configure,
        transport: (request, cancellation) => _data(
          client.streamChat(
            {
              ...request.toJson(),
              if (providerOptions.isNotEmpty)
                'providerOptions': providerOptions,
            },
            options: options,
            cancellation: cancellation,
          ),
        ),
      );
  @override
  ModelCapabilities get capabilities => _delegate.capabilities;
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => _delegate.stream(request, cancellation: cancellation);
}

final class GatewayResponsesModel implements ChatModel {
  final GatewayClient client;
  final String model;
  final GatewayOptions? options;
  final JsonObject providerOptions;
  final api.CreateResponseRequest Function(api.CreateResponseRequest)?
  configure;
  GatewayResponsesModel({
    required this.client,
    required this.model,
    this.options,
    JsonObject providerOptions = const {},
    this.configure,
  }) : providerOptions = _snapshot(providerOptions) {
    _checkPublicOptions(this.providerOptions);
  }
  api.ResponsesProtocolModel get _delegate => api.ResponsesProtocolModel(
    model: model,
    configure: configure,
    providerDataKey: 'vercel.gateway.responses',
    fileIdProvider: null,
    transport: (request, cancellation) => _data(
      client.streamResponse(
        {
          ...request.toJson(),
          if (providerOptions.isNotEmpty) 'providerOptions': providerOptions,
        },
        options: options,
        cancellation: cancellation,
      ),
    ),
  );
  @override
  ModelCapabilities get capabilities => _delegate.capabilities;
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => _delegate.stream(request, cancellation: cancellation);
}
