/// OpenRouter native JSON transport and AgentWeave models.
library;

import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:http/http.dart' as http;

export 'package:agent_weave_http/agent_weave_http.dart'
    show
        JsonSseEvent,
        JsonSseData,
        JsonSseDone,
        JsonHttpException,
        JsonHttpClient;

enum OpenRouterReasoningEffort { max, xhigh, high, medium, low, minimal, none }

enum OpenRouterProviderSort { price, throughput, latency, exacto }

enum OpenRouterDataCollection { allow, deny }

/// Provider routing preferences. Unknown fields can be supplied in [extra].
final class OpenRouterProviderPreferences {
  final JsonObject _json;
  OpenRouterProviderPreferences({
    List<String>? order,
    List<String>? only,
    List<String>? ignore,
    bool? allowFallbacks,
    bool? requireParameters,
    bool? enforceDistillableText,
    JsonObject? maxPrice,
    JsonObject? options,
    Object? preferredMaxLatency,
    Object? preferredMinThroughput,
    bool? zdr,
    OpenRouterDataCollection? dataCollection,
    OpenRouterProviderSort? sort,
    List<String>? quantizations,
    JsonObject extra = const {},
  }) : _json = snapshotJson({
         ...extra,
         'order': ?order,
         'only': ?only,
         'ignore': ?ignore,
         'allow_fallbacks': ?allowFallbacks,
         'require_parameters': ?requireParameters,
         'enforce_distillable_text': ?enforceDistillableText,
         'max_price': ?maxPrice,
         'options': ?options,
         'preferred_max_latency': ?_routingThreshold(preferredMaxLatency),
         'preferred_min_throughput': ?_routingThreshold(preferredMinThroughput),
         'zdr': ?zdr,
         'data_collection': ?dataCollection?.name,
         'sort': ?sort?.name,
         'quantizations': ?quantizations,
       });
  JsonObject toJson() => _json;
}

Object? _routingThreshold(Object? value) {
  if (value != null && value is! num && value is! Map<String, Object?>) {
    throw ArgumentError(
      'Routing thresholds must be a number or percentile object.',
    );
  }
  return value;
}

final class OpenRouterReasoning {
  final JsonObject _json;
  OpenRouterReasoning({
    OpenRouterReasoningEffort? effort,
    int? maxTokens,
    bool? enabled,
    bool? exclude,
    String? summary,
    JsonObject extra = const {},
  }) : _json = snapshotJson({
         ...extra,
         'effort': ?effort?.name,
         'max_tokens': ?maxTokens,
         'enabled': ?enabled,
         'exclude': ?exclude,
         'summary': ?summary,
       });
  JsonObject toJson() => _json;
}

final class OpenRouterPlugin {
  final JsonObject _json;
  OpenRouterPlugin({required String id, JsonObject extra = const {}})
    : _json = snapshotJson({...extra, 'id': id});
  JsonObject toJson() => _json;
}

final class OpenRouterCacheControl {
  final JsonObject _json;
  OpenRouterCacheControl({
    String type = 'ephemeral',
    String? ttl,
    JsonObject extra = const {},
  }) : _json = snapshotJson({...extra, 'type': type, 'ttl': ?ttl});
  JsonObject toJson() => _json;
}

const _owned = {
  'model',
  'messages',
  'input',
  'instructions',
  'tools',
  'tool_choice',
  'response_format',
  'text',
  'max_tokens',
  'max_completion_tokens',
  'max_output_tokens',
  'stream',
  'stream_options',
  'store',
  'previous_response_id',
  'n',
  'modalities',
  'audio',
  'functions',
  'function_call',
};

final class OpenRouterChatOptions {
  final JsonObject _json;
  OpenRouterChatOptions({
    OpenRouterProviderPreferences? provider,
    List<String>? fallbackModels,
    String? route,
    OpenRouterReasoning? reasoning,
    List<OpenRouterPlugin>? plugins,
    OpenRouterCacheControl? cacheControl,
    JsonObject extra = const {},
  }) : _json = _options({
         ...extra,
         'provider': ?provider?.toJson(),
         'models': ?fallbackModels,
         'route': ?route,
         'reasoning': ?reasoning?.toJson(),
         if (plugins != null)
           'plugins': [for (final plugin in plugins) plugin.toJson()],
         'cache_control': ?cacheControl?.toJson(),
       });
  JsonObject toJson() => _json;
}

final class OpenRouterResponsesOptions {
  final JsonObject _json;
  OpenRouterResponsesOptions({
    OpenRouterProviderPreferences? provider,
    OpenRouterReasoning? reasoning,
    List<OpenRouterPlugin>? plugins,
    JsonObject extra = const {},
  }) : _json = _options({
         ...extra,
         'provider': ?provider?.toJson(),
         'reasoning': ?reasoning?.toJson(),
         if (plugins != null)
           'plugins': [for (final plugin in plugins) plugin.toJson()],
       });
  JsonObject toJson() => _json;
}

JsonObject _options(JsonObject options) {
  if (options.keys.any(_owned.contains)) {
    throw ArgumentError('Native options cannot replace runtime-owned fields.');
  }
  final provider = options['provider'];
  if (provider is Map && provider['options'] is Map) {
    for (final value in (provider['options'] as Map).values) {
      if (value is Map && value.keys.any(_owned.contains)) {
        throw ArgumentError(
          'Provider options cannot replace runtime-owned fields.',
        );
      }
    }
  }
  return snapshotJson(options);
}

typedef OpenRouterCredentialResolver = FutureOr<String> Function();

final class OpenRouterResponse {
  final JsonObject data;
  final int statusCode;
  final Map<String, String> headers;
  OpenRouterResponse({
    required JsonObject data,
    required this.statusCode,
    required Map<String, String> headers,
  }) : data = snapshotJson(data),
       headers = Map.unmodifiable(headers);
}

final class OpenRouterClient {
  final JsonHttpClient transport;
  final OpenRouterCredentialResolver credentialResolver;
  final Map<String, String> headers;
  final bool _ownsTransport;
  OpenRouterClient({
    required this.credentialResolver,
    String baseUrl = 'https://openrouter.ai/api/v1',
    Duration requestTimeout = const Duration(minutes: 2),
    http.Client? httpClient,
    String? siteUrl,
    String? appName,
    String? sessionId,
    Map<String, String> headers = const {},
  }) : transport = JsonHttpClient(
         baseUrl: baseUrl,
         requestTimeout: requestTimeout,
         httpClient: httpClient,
       ),
       headers = _headers(headers, siteUrl, appName, sessionId),
       _ownsTransport = true;
  OpenRouterClient.withTransport({
    required this.transport,
    required this.credentialResolver,
    String? siteUrl,
    String? appName,
    String? sessionId,
    Map<String, String> headers = const {},
  }) : headers = _headers(headers, siteUrl, appName, sessionId),
       _ownsTransport = false;
  factory OpenRouterClient.withApiKey({
    required String apiKey,
    String baseUrl = 'https://openrouter.ai/api/v1',
    Duration requestTimeout = const Duration(minutes: 2),
    http.Client? httpClient,
    String? siteUrl,
    String? appName,
    String? sessionId,
    Map<String, String> headers = const {},
  }) => OpenRouterClient(
    credentialResolver: () => apiKey,
    baseUrl: baseUrl,
    requestTimeout: requestTimeout,
    httpClient: httpClient,
    siteUrl: siteUrl,
    appName: appName,
    sessionId: sessionId,
    headers: headers,
  );
  void close() {
    if (_ownsTransport) transport.close();
  }

  Future<OpenRouterResponse> _create(
    String path,
    JsonObject body,
    CancellationToken? cancellation,
  ) async {
    final request = snapshotJson(body);
    if (request['stream'] == true) {
      throw ArgumentError('Use the streaming method.');
    }
    String? secret;
    try {
      final response = await transport.sendJson(
        path,
        cancellation: cancellation,
        prepare: () async {
          try {
            secret = await credentialResolver();
          } catch (_) {
            throw JsonHttpException('Credential resolution failed');
          }
          if (secret!.trim().isEmpty ||
              secret!.contains(RegExp(r'[\r\n\x00]'))) {
            throw JsonHttpException('Invalid credential');
          }
          return JsonHttpRequest(
            body: request,
            headers: {...headers, 'Authorization': 'Bearer $secret'},
          );
        },
      );
      Object? data;
      try {
        data = jsonDecode(response.body);
      } on FormatException {
        throw JsonHttpException('Invalid JSON response');
      }
      if (data is! Map<String, Object?>) {
        throw JsonHttpException('Expected a JSON object');
      }
      return OpenRouterResponse(
        data: data,
        statusCode: response.statusCode,
        headers: _cleanHeaders(response.headers, secret),
      );
    } on JsonHttpException catch (error) {
      throw _safeError(error, secret);
    } on http.ClientException {
      throw JsonHttpException('OpenRouter transport failed');
    } on FormatException {
      throw JsonHttpException('OpenRouter response format invalid');
    }
  }

  Stream<JsonSseEvent> _stream(
    String path,
    JsonObject body,
    CancellationToken? cancellation,
  ) {
    final request = snapshotJson({...body, 'stream': true});
    return (cancellation ?? CancellationToken()).bindStream(
      (child) => _streamEvents(path, request, child),
    );
  }

  Stream<JsonSseEvent> _streamEvents(
    String path,
    JsonObject request,
    CancellationToken cancellation,
  ) async* {
    String? secret;
    var terminal = false;
    var done = false;
    try {
      await for (final event in transport.streamJson(
        path,
        cancellation: cancellation,
        prepare: () async {
          try {
            secret = await credentialResolver();
          } catch (_) {
            throw JsonHttpException('Credential resolution failed');
          }
          if (secret!.trim().isEmpty ||
              secret!.contains(RegExp(r'[\r\n\x00]'))) {
            throw JsonHttpException('Invalid credential');
          }
          return JsonHttpRequest(
            body: request,
            headers: {...headers, 'Authorization': 'Bearer $secret'},
          );
        },
      )) {
        if (event is JsonSseData) {
          final data = event.data;
          if (event.event == 'error' ||
              data.containsKey('error') ||
              data['type'] == 'error' ||
              data['type'] == 'response.failed') {
            throw JsonHttpException(
              'OpenRouter stream failed',
              details: data,
              responseHeaders: event.responseHeaders,
            );
          }
          if (path == '/responses') {
            terminal =
                terminal ||
                data['type'] == 'response.completed' ||
                data['type'] == 'response.incomplete';
          } else {
            terminal =
                terminal ||
                ((data['choices'] as List?)?.any(
                      (c) => c is Map && c['finish_reason'] != null,
                    ) ??
                    false);
          }
          yield JsonSseData(
            data,
            event: event.event,
            id: event.id,
            responseHeaders: _cleanHeaders(event.responseHeaders, secret),
          );
        } else if (event is JsonSseDone) {
          done = true;
          yield JsonSseDone(
            responseHeaders: _cleanHeaders(event.responseHeaders, secret),
          );
        }
      }
      if (!terminal || (path == '/chat/completions' && !done)) {
        throw JsonHttpException('OpenRouter stream ended before completion');
      }
    } on JsonHttpException catch (error) {
      throw _safeError(error, secret);
    } on http.ClientException {
      throw JsonHttpException('OpenRouter transport failed');
    } on FormatException {
      throw JsonHttpException('OpenRouter response format invalid');
    }
  }

  Future<OpenRouterResponse> createChat(
    JsonObject body, {
    CancellationToken? cancellation,
  }) => _create('/chat/completions', body, cancellation);
  Stream<JsonSseEvent> streamChat(
    JsonObject body, {
    CancellationToken? cancellation,
  }) => _stream('/chat/completions', body, cancellation);
  Future<OpenRouterResponse> createResponse(
    JsonObject body, {
    CancellationToken? cancellation,
  }) => _create('/responses', body, cancellation);
  Stream<JsonSseEvent> streamResponse(
    JsonObject body, {
    CancellationToken? cancellation,
  }) => _stream('/responses', body, cancellation);
}

Map<String, String> _headers(
  Map<String, String> headers,
  String? siteUrl,
  String? appName,
  String? sessionId,
) {
  if (headers.keys.any((key) => key.toLowerCase() == 'authorization')) {
    throw ArgumentError('Authorization is owned by credentialResolver.');
  }
  return Map.unmodifiable({
    ...headers,
    'HTTP-Referer': ?siteUrl,
    'X-Title': ?appName,
    'X-Session-Id': ?sessionId,
  });
}

String _redact(String value, String? secret) => secret == null || secret.isEmpty
    ? value
    : value
          .replaceAll(secret, '[REDACTED]')
          .replaceAll(
            jsonEncode(secret).substring(1, jsonEncode(secret).length - 1),
            '[REDACTED]',
          );
Map<String, String> _cleanHeaders(
  Map<String, String> headers,
  String? secret,
) => {
  for (final e in headers.entries)
    if (!{
      'authorization',
      'set-cookie',
      'proxy-authorization',
      'x-api-key',
      'cookie',
    }.contains(e.key.toLowerCase()))
      _redact(e.key, secret): _redact(e.value, secret),
};
Object? _clean(Object? value, String? secret) => switch (value) {
  String s => _redact(s, secret),
  Map<String, Object?> m => <String, Object?>{
    for (final e in m.entries) _redact(e.key, secret): _clean(e.value, secret),
  },
  List<Object?> l => [for (final x in l) _clean(x, secret)],
  _ => value,
};
JsonHttpException _safeError(JsonHttpException e, String? secret) =>
    JsonHttpException(
      'OpenRouter request failed',
      statusCode: e.statusCode,
      requestId: e.requestId == null ? null : _redact(e.requestId!, secret),
      details: e.details == null
          ? null
          : _clean(e.details, secret) as JsonObject,
      responseHeaders: _cleanHeaders(e.responseHeaders, secret),
    );

final class OpenRouterChatModel implements ChatModel {
  final OpenRouterClient client;
  final String model;
  final OpenRouterChatOptions? options;
  final api.ChatCompletionCreateRequest Function(
    api.ChatCompletionCreateRequest,
  )?
  configure;
  const OpenRouterChatModel({
    required this.client,
    required this.model,
    this.options,
    this.configure,
  });
  @override
  ModelCapabilities get capabilities => api.ChatCompletionsProtocolModel(
    model: model,
    transport: (_, _) => const Stream.empty(),
  ).capabilities;
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) =>
      cancellation.bindStream((child) => _stream(request, cancellation: child));

  Stream<ModelEvent> _stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    final details = <JsonObject>[];
    final reasoningText = StringBuffer();
    final metadata = <String, Object?>{};
    final delegate = api.ChatCompletionsProtocolModel(
      model: model,
      configure: configure,
      transport: (params, token) async* {
        final body = params.toJson();
        final messages = (body['messages'] as List)
            .cast<Map<String, dynamic>>();
        final offset = request.instructions == null ? 0 : 1;
        for (var i = 0; i < request.messages.length; i++) {
          final replay =
              request.messages[i].providerData['openrouter.chat.reasoning'];
          if (request.messages[i].role == MessageRole.assistant &&
              replay != null &&
              replay.isNotEmpty) {
            messages[i + offset]['reasoning_details'] = replay;
          } else if (request.messages[i].role == MessageRole.assistant) {
            final text = request
                .messages[i]
                .providerData['openrouter.chat.reasoning_text'];
            if (text?.length == 1 && text!.single['text'] is String) {
              messages[i + offset]['reasoning'] = text.single['text'];
            }
          }
        }
        await for (final event in client.streamChat({
          ...body,
          ...?options?.toJson(),
        }, cancellation: token)) {
          if (event is JsonSseData) {
            final json = event.data;
            for (final choice in json['choices'] as List? ?? []) {
              if (choice is Map && choice['index'] == 0) {
                final choiceMetadata = <String, Object?>{
                  for (final entry in choice.entries)
                    if (entry.key is String && entry.key != 'delta')
                      entry.key as String: entry.value,
                };
                if (choiceMetadata.isNotEmpty) {
                  metadata['choice'] = choiceMetadata;
                }
                final delta = choice['delta'];
                if (delta is Map && delta['reasoning'] is String) {
                  reasoningText.write(delta['reasoning']);
                }
                if (delta is Map && delta['reasoning_details'] is List) {
                  details.addAll(
                    (delta['reasoning_details'] as List).map(
                      (e) => Map<String, Object?>.from(e as Map),
                    ),
                  );
                }
              }
            }
            for (final entry in json.entries) {
              if (entry.key != 'choices') metadata[entry.key] = entry.value;
            }
            yield json;
          }
        }
      },
    );
    await for (final event in delegate.stream(
      request,
      cancellation: cancellation,
    )) {
      if (event is ModelFinished) {
        if (details.isNotEmpty) {
          yield ProviderOutput(
            provider: 'openrouter.chat.reasoning',
            items: details,
          );
        }
        if (details.isEmpty && reasoningText.isNotEmpty) {
          yield ProviderOutput(
            provider: 'openrouter.chat.reasoning_text',
            items: [
              {'text': reasoningText.toString()},
            ],
          );
        }
        if (metadata.isNotEmpty) {
          yield ProviderOutput(
            provider: 'openrouter.chat.metadata',
            items: [metadata],
          );
        }
      }
      yield event;
    }
  }
}

final class OpenRouterResponsesModel implements ChatModel {
  final OpenRouterClient client;
  final String model;
  final OpenRouterResponsesOptions? options;
  final api.CreateResponseRequest Function(api.CreateResponseRequest)?
  configure;
  const OpenRouterResponsesModel({
    required this.client,
    required this.model,
    this.options,
    this.configure,
  });
  @override
  ModelCapabilities get capabilities => api.ResponsesProtocolModel(
    model: model,
    transport: (_, _) => const Stream.empty(),
  ).capabilities;
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) =>
      cancellation.bindStream((child) => _stream(request, cancellation: child));

  Stream<ModelEvent> _stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    final metadata = <JsonObject>[];
    final delegate = api.ResponsesProtocolModel(
      model: model,
      providerDataKey: 'openrouter.responses',
      fileIdProvider: null,
      includeEncryptedReasoning: false,
      configure: configure,
      transport: (params, token) async* {
        final body = params.toJson();
        if (body['store'] == true || body['previous_response_id'] != null) {
          throw ArgumentError(
            'OpenRouter Responses requires stateless full history.',
          );
        }
        await for (final event in client.streamResponse({
          ...body,
          ...?options?.toJson(),
        }, cancellation: token)) {
          if (event is JsonSseData) {
            if (event.data['type'] == 'response.completed' ||
                event.data['type'] == 'response.incomplete') {
              final response = event.data['response'];
              metadata.add({
                ...event.data,
                if (response is Map<String, Object?>)
                  'response': {
                    for (final entry in response.entries)
                      if (entry.key != 'output') entry.key: entry.value,
                  },
              });
            }
            yield event.data;
          }
        }
      },
    );
    await for (final event in delegate.stream(
      request,
      cancellation: cancellation,
    )) {
      if (event is ModelFinished && metadata.isNotEmpty) {
        yield ProviderOutput(
          provider: 'openrouter.responses.metadata',
          items: metadata,
        );
      }
      yield event;
    }
  }
}
