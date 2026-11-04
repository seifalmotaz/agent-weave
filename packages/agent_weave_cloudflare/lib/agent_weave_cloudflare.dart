/// Cloudflare Workers AI and AI Gateway REST clients.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:http/http.dart' as http;

export 'package:agent_weave_http/agent_weave_http.dart'
    show JsonSseEvent, JsonSseData, JsonSseDone;

typedef CloudflareTokenResolver = FutureOr<String> Function();

/// Diagnostics are private backend data and never appear in [toString].
final class CloudflareException implements Exception {
  final String message;
  final int? statusCode;
  final String? requestId;
  final JsonObject? details;
  final Map<String, String> responseHeaders;
  CloudflareException(
    this.message, {
    this.statusCode,
    this.requestId,
    JsonObject? details,
    Map<String, String> responseHeaders = const {},
  }) : details = details == null ? null : snapshotJson(details),
       responseHeaders = Map.unmodifiable(responseHeaders);
  @override
  String toString() =>
      'CloudflareException: $message${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

String _redactText(String value, String token) {
  if (token.isEmpty) return value;
  final encoded = jsonEncode(token);
  final variants = {token, encoded.substring(1, encoded.length - 1)}.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final secret in variants) {
    value = value.replaceAll(secret, '[REDACTED]');
  }
  return value;
}

Object? _redact(Object? value, String token) => switch (value) {
  String s => _redactText(s, token),
  List<Object?> list => [for (final item in list) _redact(item, token)],
  Map<Object?, Object?> map => <String, Object?>{
    for (final e in map.entries)
      _redact(e.key.toString(), token) as String: _redact(e.value, token),
  },
  _ => value,
};

Map<String, String> _safeHeaders(Map<String, String> headers, String secret) =>
    {
      for (final entry in headers.entries)
        _redact(entry.key, secret) as String:
            _redact(entry.value, secret) as String,
    };

final class CloudflareResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bytes;
  final JsonObject? json;
  CloudflareResponse._(http.Response response, this.json)
    : statusCode = response.statusCode,
      headers = Map.unmodifiable(response.headers),
      bytes = Uint8List.fromList(response.bodyBytes).asUnmodifiableView();
  String? get cacheStatus => headers['cf-aig-cache-status'];
  String? get requestId => headers['cf-aig-request-id'];
  String? get logId => headers['cf-aig-log-id'];
  String? get step => headers['cf-aig-step'];
}

/// A client owns its transport only when it created it.
final class CloudflareClient {
  final String accountId;
  final CloudflareTokenResolver tokenResolver;
  final CloudflareGatewayOptions? gateway;
  final JsonHttpClient _transport;
  final bool _ownsTransport;
  CloudflareClient({
    required this.accountId,
    required this.tokenResolver,
    this.gateway,
    String baseUrl = 'https://api.cloudflare.com/client/v4',
    http.Client? httpClient,
    JsonHttpClient? transport,
    Duration requestTimeout = const Duration(minutes: 2),
  }) : _transport =
           transport ??
           JsonHttpClient(
             baseUrl: baseUrl,
             httpClient: httpClient,
             requestTimeout: requestTimeout,
           ),
       _ownsTransport = transport == null {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(accountId)) {
      throw ArgumentError('Invalid account ID.');
    }
    if (transport != null && httpClient != null) {
      throw ArgumentError('Choose transport or httpClient.');
    }
  }
  factory CloudflareClient.withApiToken({
    required String accountId,
    required String apiToken,
    CloudflareGatewayOptions? gateway,
    String baseUrl = 'https://api.cloudflare.com/client/v4',
    http.Client? httpClient,
    JsonHttpClient? transport,
    Duration requestTimeout = const Duration(minutes: 2),
  }) => CloudflareClient(
    accountId: accountId,
    tokenResolver: () => apiToken,
    gateway: gateway,
    baseUrl: baseUrl,
    httpClient: httpClient,
    transport: transport,
    requestTimeout: requestTimeout,
  );
  void close() {
    if (_ownsTransport) _transport.close();
  }

  Future<String> _resolveToken() async {
    final String token;
    try {
      token = await tokenResolver();
    } catch (_) {
      throw CloudflareException('Credential resolution failed');
    }
    if (token.trim().isEmpty || token.contains(RegExp(r'[\r\n\x00]'))) {
      throw ArgumentError('Invalid Cloudflare token.');
    }
    return token;
  }

  String get _prefix => '/accounts/$accountId/ai';
  String _modelPath(String model) {
    if (!RegExp(r'^[@A-Za-z0-9_.-]+(?:/[@A-Za-z0-9_.-]+)*$').hasMatch(model) ||
        model.split('/').any((s) => s == '.' || s == '..')) {
      throw ArgumentError('Invalid model name.');
    }
    return '$_prefix/run/$model';
  }

  Future<CloudflareResponse> _send(
    String path,
    HttpRequestData Function(Map<String, String>) make, {
    HttpMethod method = HttpMethod.post,
    Map<String, List<String>> query = const {},
    CancellationToken? cancellation,
    Map<String, String> headers = const {},
    bool requireJson = true,
  }) async {
    final data = make(headers);
    final frozenQuery = {
      for (final entry in query.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    };
    var secret = '';
    try {
      final response = await _transport.send(
        path,
        method: method,
        query: frozenQuery,
        cancellation: cancellation,
        prepare: () async {
          secret = await _resolveToken();
          final authorized = {
            ...?gateway?.headers,
            ...data.headers,
            'Authorization': 'Bearer $secret',
          };
          return switch (data) {
            JsonHttpRequest(:final body) => JsonHttpRequest(
              body: body,
              headers: authorized,
            ),
            BinaryHttpRequest(:final bytes, :final contentType) =>
              BinaryHttpRequest(
                bytes: bytes,
                contentType: contentType,
                headers: authorized,
              ),
            EmptyHttpRequest() => EmptyHttpRequest(headers: authorized),
          };
        },
      );
      JsonObject? value;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) value = snapshotJson(decoded);
      } on FormatException {
        /* Binary results are valid. */
      }
      if (requireJson && value == null) {
        throw CloudflareException(
          'Invalid JSON response',
          statusCode: response.statusCode,
          responseHeaders: _safeHeaders(response.headers, secret),
        );
      }
      if (value?['success'] == false) {
        throw CloudflareException(
          'Provider returned an error',
          statusCode: response.statusCode,
          requestId:
              _redact(
                    response.headers['cf-aig-request-id'] ??
                        response.headers['cf-ray'],
                    secret,
                  )
                  as String?,
          details: _redact(value, secret) as JsonObject,
          responseHeaders: _safeHeaders(response.headers, secret),
        );
      }
      return CloudflareResponse._(response, value);
    } on JsonHttpException catch (error) {
      throw CloudflareException(
        'Request failed',
        statusCode: error.statusCode,
        requestId:
            _redact(
                  error.responseHeaders['cf-aig-request-id'] ??
                      error.responseHeaders['cf-ray'] ??
                      error.requestId,
                  secret,
                )
                as String?,
        details: _redact(error.details, secret) as JsonObject?,
        responseHeaders: _safeHeaders(error.responseHeaders, secret),
      );
    }
  }

  Future<CloudflareResponse> runJson(
    String model,
    JsonObject input, {
    CancellationToken? cancellation,
  }) => _send(
    _modelPath(model),
    (headers) => JsonHttpRequest(body: input, headers: headers),
    cancellation: cancellation,
  );

  /// Allows a binary input and either a binary or JSON result.
  Future<CloudflareResponse> runBytes(
    String model,
    List<int> bytes, {
    String contentType = 'application/octet-stream',
    CancellationToken? cancellation,
  }) => _send(
    _modelPath(model),
    (headers) => BinaryHttpRequest(
      bytes: bytes,
      contentType: contentType,
      headers: headers,
    ),
    cancellation: cancellation,
    requireJson: false,
  );

  /// For models whose JSON input produces an image or other binary output.
  Future<CloudflareResponse> runJsonOrBytes(
    String model,
    JsonObject input, {
    CancellationToken? cancellation,
  }) => _send(
    _modelPath(model),
    (headers) => JsonHttpRequest(body: input, headers: headers),
    cancellation: cancellation,
    requireJson: false,
  );
  Future<CloudflareResponse> getModelSchema(
    String model, {
    CancellationToken? cancellation,
  }) => _send(
    '$_prefix/models/schema',
    (headers) => EmptyHttpRequest(headers: headers),
    method: HttpMethod.get,
    query: {
      'model': [model],
    },
    cancellation: cancellation,
  );
  Future<CloudflareResponse> listModels({
    Map<String, List<String>> query = const {},
    CancellationToken? cancellation,
  }) => _send(
    '$_prefix/models/search',
    (headers) => EmptyHttpRequest(headers: headers),
    method: HttpMethod.get,
    query: query,
    cancellation: cancellation,
  );
  Stream<JsonSseEvent> stream(
    String model,
    JsonObject input, {
    CancellationToken? cancellation,
  }) => _stream(
    _modelPath(model),
    snapshotJson({...input, 'stream': true}),
    cancellation: cancellation,
  );

  Stream<JsonSseEvent> _stream(
    String path,
    JsonObject input, {
    Map<String, String> headers = const {},
    CancellationToken? cancellation,
  }) => (cancellation ?? CancellationToken()).bindStream(
    (child) =>
        _streamEvents(path, input, headers: headers, cancellation: child),
  );

  Stream<JsonSseEvent> _streamEvents(
    String path,
    JsonObject input, {
    required Map<String, String> headers,
    required CancellationToken cancellation,
  }) async* {
    var secret = '';
    try {
      await for (final event in _transport.streamJson(
        path,
        cancellation: cancellation,
        prepare: () async {
          secret = await _resolveToken();
          return JsonHttpRequest(
            body: input,
            headers: {
              ...?gateway?.headers,
              ...headers,
              'Authorization': 'Bearer $secret',
            },
          );
        },
      )) {
        if (event is JsonSseData &&
            (event.data['success'] == false ||
                event.data.containsKey('error') ||
                event.event == 'error')) {
          throw CloudflareException(
            'Provider returned a stream error',
            details: _redact(event.data, secret) as JsonObject,
            requestId:
                _redact(
                      event.responseHeaders['cf-aig-request-id'] ??
                          event.responseHeaders['cf-ray'],
                      secret,
                    )
                    as String?,
            responseHeaders: _safeHeaders(event.responseHeaders, secret),
          );
        }
        yield event;
      }
    } on JsonHttpException catch (error) {
      throw CloudflareException(
        'Request failed',
        statusCode: error.statusCode,
        details: _redact(error.details, secret) as JsonObject?,
        responseHeaders: _safeHeaders(error.responseHeaders, secret),
      );
    }
  }
}

/// Per-request Gateway header overrides; custom fields cannot replace owned headers.
final class CloudflareGatewayOptions {
  final Map<String, String> headers;
  CloudflareGatewayOptions({
    String? gatewayId,
    String? cacheKey,
    int? cacheTtl,
    bool? skipCache,
    JsonObject? metadata,
    int? requestTimeoutMs,
    int? maxAttempts,
    String? backoff,
    int? retryDelay,
    Map<String, String> customHeaders = const {},
  }) : headers = Map.unmodifiable({
         ...customHeaders,
         'cf-aig-gateway-id': ?gatewayId,
         'cf-aig-cache-key': ?cacheKey,
         if (cacheTtl != null) 'cf-aig-cache-ttl': '$cacheTtl',
         if (skipCache != null) 'cf-aig-skip-cache': '$skipCache',
         if (metadata != null)
           'cf-aig-metadata': jsonEncode(snapshotJson(metadata)),
         if (requestTimeoutMs != null)
           'cf-aig-request-timeout': '$requestTimeoutMs',
         if (maxAttempts != null) 'cf-aig-max-attempts': '$maxAttempts',
         'cf-aig-backoff': ?backoff,
         if (retryDelay != null) 'cf-aig-retry-delay': '$retryDelay',
       }) {
    const owned = {
      'cf-aig-gateway-id',
      'cf-aig-cache-key',
      'cf-aig-cache-ttl',
      'cf-aig-skip-cache',
      'cf-aig-metadata',
      'cf-aig-request-timeout',
      'cf-aig-max-attempts',
      'cf-aig-backoff',
      'cf-aig-retry-delay',
    };
    if (customHeaders.keys.any(
      (k) =>
          !RegExp(r'^[A-Za-z0-9-]+$').hasMatch(k) ||
          !k.toLowerCase().startsWith('cf-aig-') ||
          owned.contains(k.toLowerCase()) ||
          k.toLowerCase() == 'cf-aig-authorization',
    )) {
      throw ArgumentError('Invalid custom Gateway header.');
    }
    if (headers.values.any((v) => v.contains(RegExp(r'[\r\n]')))) {
      throw ArgumentError('Invalid header value.');
    }
  }
}

final class CloudflareGatewayClient {
  final CloudflareClient client;
  CloudflareGatewayClient({required this.client});
  Future<CloudflareResponse> runJson(
    String model,
    JsonObject input, {
    JsonObject? options,
    CloudflareGatewayOptions? gateway,
    CancellationToken? cancellation,
  }) => _run(
    model,
    input,
    options: options,
    gateway: gateway,
    cancellation: cancellation,
    requireJson: true,
  );
  Future<CloudflareResponse> runJsonOrBytes(
    String model,
    JsonObject input, {
    JsonObject? options,
    CloudflareGatewayOptions? gateway,
    CancellationToken? cancellation,
  }) => _run(
    model,
    input,
    options: options,
    gateway: gateway,
    cancellation: cancellation,
    requireJson: false,
  );
  Future<CloudflareResponse> _run(
    String model,
    JsonObject input, {
    JsonObject? options,
    CloudflareGatewayOptions? gateway,
    CancellationToken? cancellation,
    required bool requireJson,
  }) {
    if (model.startsWith('@cf/') &&
        ((gateway ?? client.gateway)
                ?.headers['cf-aig-gateway-id']
                ?.isNotEmpty !=
            true)) {
      throw ArgumentError('@cf models require a gateway ID.');
    }
    return client._send(
      '${client._prefix}/run',
      (headers) => JsonHttpRequest(
        body: {'model': model, 'input': input, 'options': ?options},
        headers: headers,
      ),
      headers: gateway?.headers ?? const {},
      cancellation: cancellation,
      requireJson: requireJson,
    );
  }
}

enum CloudflarePooling { mean, cls }

final class CloudflareEmbeddingRequest {
  final List<String> text;
  final CloudflarePooling? pooling;
  final JsonObject extra;
  CloudflareEmbeddingRequest({
    required Iterable<String> text,
    this.pooling,
    JsonObject extra = const {},
  }) : text = List.unmodifiable(text),
       extra = snapshotJson(extra) {
    if (this.text.isEmpty ||
        this.text.length > 100 ||
        this.text.any((value) => value.trim().isEmpty)) {
      throw ArgumentError('Invalid embedding request.');
    }
    if (extra.containsKey('text') || extra.containsKey('pooling')) {
      throw ArgumentError('Embedding fields are owned by the request.');
    }
  }
}

/// Typed BGE fields and the complete unmodified provider response.
final class CloudflareEmbeddingResult {
  final CloudflareResponse response;
  final List<List<double>> vectors;
  final List<int> shape;
  final String? pooling;
  final JsonObject result;
  CloudflareEmbeddingResult._(
    this.response,
    this.vectors,
    this.shape,
    this.pooling,
    this.result,
  );
  factory CloudflareEmbeddingResult.fromResponse(CloudflareResponse response) {
    final value = response.json?['result'];
    if (value is! Map<String, dynamic> ||
        value['data'] is! List ||
        value['shape'] is! List ||
        (value['pooling'] != null && value['pooling'] is! String)) {
      throw CloudflareException('Invalid embedding result');
    }
    final data = value['data'] as List;
    final shape = value['shape'] as List;
    if (data.any((row) => row is! List || row.any((v) => v is! num)) ||
        shape.length != 2 ||
        shape.any((v) => v is! int || v < 0) ||
        shape[0] != data.length ||
        data.any((row) => (row as List).length != shape[1])) {
      throw CloudflareException('Invalid embedding result');
    }
    return CloudflareEmbeddingResult._(
      response,
      List.unmodifiable(
        data.map(
          (row) => List<double>.unmodifiable(
            (row as List).map((n) => (n as num).toDouble()),
          ),
        ),
      ),
      List<int>.unmodifiable(shape.cast<int>()),
      value['pooling'] as String?,
      snapshotJson(value),
    );
  }
}

final class CloudflareEmbeddingModel
    implements
        EmbeddingModel<CloudflareEmbeddingRequest, CloudflareEmbeddingResult> {
  final CloudflareClient client;
  final String model;
  CloudflareEmbeddingModel({
    required this.client,
    this.model = '@cf/baai/bge-base-en-v1.5',
  });
  @override
  Future<CloudflareEmbeddingResult> embed(
    CloudflareEmbeddingRequest request, {
    CancellationToken? cancellation,
  }) async => CloudflareEmbeddingResult.fromResponse(
    await client.runJson(model, {
      ...request.extra,
      'text': request.text,
      if (request.pooling != null) 'pooling': request.pooling!.name,
    }, cancellation: cancellation),
  );
}

sealed class CloudflareAudioInput {
  const CloudflareAudioInput();
  factory CloudflareAudioInput.bytes(List<int> bytes, {String contentType}) =
      CloudflareAudioBytes;
  factory CloudflareAudioInput.json(JsonObject input) = CloudflareAudioJson;
}

final class CloudflareAudioBytes extends CloudflareAudioInput {
  final List<int> bytes;
  final String contentType;
  CloudflareAudioBytes(
    List<int> bytes, {
    this.contentType = 'application/octet-stream',
  }) : bytes = List.unmodifiable(bytes);
}

final class CloudflareAudioJson extends CloudflareAudioInput {
  final JsonObject input;
  CloudflareAudioJson(JsonObject input) : input = snapshotJson(input);
}

final class CloudflareTranscriptionResult {
  final CloudflareResponse response;
  final JsonObject result;
  final String text;
  CloudflareTranscriptionResult._(this.response, this.result, this.text);
  factory CloudflareTranscriptionResult.fromResponse(
    CloudflareResponse response,
  ) {
    final value = response.json?['result'];
    if (value is! Map<String, dynamic> || value['text'] is! String) {
      throw CloudflareException('Invalid transcription result');
    }
    return CloudflareTranscriptionResult._(
      response,
      snapshotJson(value),
      value['text'] as String,
    );
  }
  int? get wordCount => result['word_count'] as int?;
  List<Object?>? get words => result['words'] as List<Object?>?;
  String? get vtt => result['vtt'] as String?;
}

final class CloudflareTranscriptionModel
    implements
        TranscriptionModel<
          CloudflareAudioInput,
          CloudflareTranscriptionResult
        > {
  final CloudflareClient client;
  final String model;
  CloudflareTranscriptionModel({
    required this.client,
    this.model = '@cf/openai/whisper',
  });
  @override
  Future<CloudflareTranscriptionResult> transcribe(
    CloudflareAudioInput request, {
    CancellationToken? cancellation,
  }) async {
    final response = await switch (request) {
      CloudflareAudioBytes(:final bytes, :final contentType) => client.runBytes(
        model,
        bytes,
        contentType: contentType,
        cancellation: cancellation,
      ),
      CloudflareAudioJson(:final input) => client.runJson(
        model,
        input,
        cancellation: cancellation,
      ),
    };
    return CloudflareTranscriptionResult.fromResponse(response);
  }
}

final class CloudflareImageResult {
  final CloudflareResponse response;
  final Uint8List imageBytes;
  final String contentType;
  CloudflareImageResult._(this.response, List<int> bytes, this.contentType)
    : imageBytes = Uint8List.fromList(bytes).asUnmodifiableView();
}

final class CloudflareImageModel
    implements ImageModel<JsonObject, CloudflareImageResult> {
  final CloudflareClient client;
  final String model;
  CloudflareImageModel({
    required this.client,
    this.model = '@cf/black-forest-labs/flux-1-schnell',
  });
  @override
  Future<CloudflareImageResult> generate(
    JsonObject request, {
    CancellationToken? cancellation,
  }) async {
    final response = await client.runJsonOrBytes(
      model,
      request,
      cancellation: cancellation,
    );
    final mime = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (mime != null && mime.startsWith('image/')) {
      return CloudflareImageResult._(response, response.bytes, mime);
    }
    final result = response.json?['result'];
    if (model == '@cf/black-forest-labs/flux-1-schnell' &&
        result is Map &&
        result['image'] is String) {
      try {
        final bytes = base64Decode(result['image'] as String);
        if (bytes.isEmpty) throw const FormatException('Empty image.');
        return CloudflareImageResult._(response, bytes, 'image/jpeg');
      } on FormatException {
        throw CloudflareException('Invalid image result');
      }
    }
    throw UnsupportedError(
      'Unknown image result format; use the raw client to inspect it.',
    );
  }
}

/// Traditional single-tool continuation as documented for Hermes 2 Pro.
/// Streaming uses a non-streamed inference; other models may use other formats.
final class CloudflareChatModel implements ChatModel {
  final CloudflareClient client;
  final String model;
  final JsonObject options;
  CloudflareChatModel({
    required this.client,
    required this.model,
    JsonObject options = const {},
  }) : options = snapshotJson(options) {
    if (options.keys.any(
      {
        'messages',
        'prompt',
        'raw',
        'chat_template',
        'template',
        'tools',
        'max_tokens',
        'max_completion_tokens',
        'stream',
        'response_format',
      }.contains,
    )) {
      throw ArgumentError('Request-owned option supplied.');
    }
  }
  @override
  ModelCapabilities get capabilities =>
      const ModelCapabilities(tools: true, structuredOutput: true);
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
    if (model != '@hf/nousresearch/hermes-2-pro-mistral-7b' &&
        (request.tools.isNotEmpty ||
            request.messages.any(
              (message) =>
                  message.toolCalls.isNotEmpty ||
                  message.role == MessageRole.tool,
            ))) {
      throw UnsupportedError(
        'Native tool continuation is only implemented for the documented Hermes profile.',
      );
    }
    final messages = <JsonObject>[
      if (request.instructions != null)
        {'role': 'system', 'content': request.instructions},
    ];
    for (final m in request.messages) {
      if (m.content.any((part) => part is! TextPart)) {
        throw UnsupportedError('Native chat adapter supports text only.');
      }
      if (m.role == MessageRole.assistant && m.toolCalls.isNotEmpty) {
        if (m.toolCalls.length != 1 || m.text.isNotEmpty) {
          throw UnsupportedError(
            'Native continuation supports one selected tool call.',
          );
        }
        final c = m.toolCalls.single;
        final replay = m.providerData['cloudflare.native'];
        final selected = replay?.length == 1
            ? replay!.single
            : {'name': c.name, 'arguments': c.arguments};
        messages.add({'role': 'assistant', 'content': jsonEncode(selected)});
      } else {
        messages.add({'role': m.role.name, 'content': m.text});
      }
    }
    final response = await client.runJson(model, {
      ...options,
      'messages': messages,
      'max_tokens': request.maxOutputTokens,
      if (request.tools.isNotEmpty)
        'tools': [
          for (final tool in request.tools)
            {
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.inputSchema,
            },
        ],
      if (request.outputSchema != null)
        'response_format': {
          'type': 'json_schema',
          'json_schema': request.outputSchema,
        },
    }, cancellation: cancellation);
    final result = response.json?['result'];
    if (result is! Map) throw CloudflareException('Invalid native result');
    final content = result['response'];
    if (content is String && content.isNotEmpty) yield TextDelta(content);
    if (content is Map || content is List) yield TextDelta(jsonEncode(content));
    final calls = result['tool_calls'];
    if (content == null && (calls is! List || calls.isEmpty)) {
      throw CloudflareException('Invalid native result');
    }
    if (content != null &&
        content is! String &&
        content is! Map &&
        content is! List) {
      throw CloudflareException('Invalid native result');
    }
    if (calls != null) {
      if (calls is! List || calls.length > 1) {
        throw UnsupportedError(
          'Native continuation supports one selected tool call.',
        );
      }
      if (calls.isNotEmpty) {
        final item = calls.single;
        if (item is! Map ||
            item['name'] is! String ||
            item['arguments'] is! Map) {
          throw CloudflareException('Invalid native tool call');
        }
        yield ProviderOutput(
          provider: 'cloudflare.native',
          items: [Map<String, Object?>.from(item)],
        );
        yield ToolCallReady(
          ToolCall(
            id: 'cloudflare-${request.messages.length}',
            name: item['name'] as String,
            arguments: Map<String, Object?>.from(item['arguments'] as Map),
          ),
        );
      }
    }
    yield ModelFinished(
      calls is List && calls.isNotEmpty ? 'tool_calls' : 'stop',
    );
  }
}

/// Token-bound field spelling differs across compatible models.
enum CloudflareChatTokenField { maxCompletionTokens, maxTokens }

/// Compatible endpoint client; model support and options depend on the provider.
final class CloudflareCompatibleClient {
  final CloudflareClient client;
  final CloudflareGatewayOptions? gateway;
  CloudflareCompatibleClient({required this.client, this.gateway});
  Future<CloudflareResponse> createChat(
    JsonObject body, {
    CancellationToken? cancellation,
  }) => client._send(
    '${client._prefix}/v1/chat/completions',
    (headers) => JsonHttpRequest(body: body, headers: headers),
    headers: gateway?.headers ?? const {},
    cancellation: cancellation,
  );
  Future<CloudflareResponse> createResponse(
    JsonObject body, {
    CancellationToken? cancellation,
  }) => client._send(
    '${client._prefix}/v1/responses',
    (headers) => JsonHttpRequest(body: body, headers: headers),
    headers: gateway?.headers ?? const {},
    cancellation: cancellation,
  );
  Stream<JsonSseEvent> streamChat(
    JsonObject body, {
    CancellationToken? cancellation,
  }) => client._stream(
    '${client._prefix}/v1/chat/completions',
    snapshotJson({...body, 'stream': true}),
    headers: gateway?.headers ?? const {},
    cancellation: cancellation,
  );
  Stream<JsonSseEvent> streamResponse(
    JsonObject body, {
    CancellationToken? cancellation,
  }) => client._stream(
    '${client._prefix}/v1/responses',
    snapshotJson({...body, 'stream': true}),
    headers: gateway?.headers ?? const {},
    cancellation: cancellation,
  );
}

JsonObject _compatibleOptions(JsonObject options) {
  const owned = {
    'model',
    'messages',
    'input',
    'tools',
    'tool_choice',
    'max_tokens',
    'max_completion_tokens',
    'max_output_tokens',
    'stream',
    'stream_options',
    'response_format',
    'text',
  };
  if (options.keys.any(owned.contains)) {
    throw ArgumentError('Runtime-owned compatible option supplied.');
  }
  return snapshotJson(options);
}

Stream<JsonObject> _data(Stream<JsonSseEvent> events) => events
    .where((event) => event is JsonSseData)
    .map((event) => (event as JsonSseData).data);

final class CloudflareCompatibleChatModel implements ChatModel {
  final CloudflareCompatibleClient client;
  final String model;
  final JsonObject options;
  final CloudflareChatTokenField tokenField;
  final api.ChatCompletionCreateRequest Function(
    api.ChatCompletionCreateRequest,
  )?
  configure;
  CloudflareCompatibleChatModel({
    required this.client,
    required this.model,
    JsonObject options = const {},
    this.tokenField = CloudflareChatTokenField.maxCompletionTokens,
    this.configure,
  }) : options = _compatibleOptions(options);
  api.ChatCompletionsProtocolModel get _delegate =>
      api.ChatCompletionsProtocolModel(
        model: model,
        configure: configure,
        transport: (request, cancellation) {
          final body = <String, Object?>{...request.toJson(), ...options};
          if (tokenField == CloudflareChatTokenField.maxTokens) {
            body['max_tokens'] = body.remove('max_completion_tokens');
          }
          return _data(client.streamChat(body, cancellation: cancellation));
        },
      );
  @override
  ModelCapabilities get capabilities => _delegate.capabilities;
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => _delegate.stream(request, cancellation: cancellation);
}

final class CloudflareCompatibleResponsesModel implements ChatModel {
  final CloudflareCompatibleClient client;
  final String model;
  final JsonObject options;
  final api.CreateResponseRequest Function(api.CreateResponseRequest)?
  configure;
  CloudflareCompatibleResponsesModel({
    required this.client,
    required this.model,
    JsonObject options = const {},
    this.configure,
  }) : options = _compatibleOptions(options);
  api.ResponsesProtocolModel get _delegate => api.ResponsesProtocolModel(
    model: model,
    configure: configure,
    providerDataKey: 'cloudflare.gateway.responses',
    fileIdProvider: null,
    includeEncryptedReasoning: false,
    transport: (request, cancellation) => _data(
      client.streamResponse({
        ...request.toJson(),
        ...options,
      }, cancellation: cancellation),
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
