import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:http/http.dart' as http;
import 'package:ollama_dart/ollama_dart.dart' as api;
import 'models.dart';

typedef OllamaCredentialResolver = FutureOr<String?> Function();

final class OllamaNativeResponse {
  final JsonObject data;
  final int statusCode;
  final Map<String, String> headers;
  OllamaNativeResponse({
    required JsonObject data,
    required this.statusCode,
    required Map<String, String> headers,
  }) : data = snapshotJson(data),
       headers = Map.unmodifiable(headers);
}

/// Native JSON and NDJSON. No model is pulled or downloaded automatically.
/// The caller closes this client; an injected HTTP client remains borrowed.
final class OllamaNativeClient {
  final JsonHttpClient _transport;
  final OllamaCredentialResolver? credentialResolver;
  final Map<String, String> headers;
  OllamaNativeClient({
    String baseUrl = 'http://localhost:11434',
    this.credentialResolver,
    Map<String, String> headers = const {},
    Duration requestTimeout = const Duration(minutes: 2),
    http.Client? httpClient,
  }) : _transport = JsonHttpClient(
         baseUrl: baseUrl,
         requestTimeout: requestTimeout,
         httpClient: httpClient,
       ),
       headers = _headers(headers);

  void close() => _transport.close();

  Future<Map<String, String>> _authenticate(
    Map<String, String> headers,
    void Function(String?) remember,
  ) async {
    String? key;
    try {
      key = await credentialResolver?.call();
    } catch (_) {
      throw JsonHttpException('Ollama credential resolution failed');
    }
    remember(key);
    if (key != null &&
        (key.trim().isEmpty || key.contains(RegExp(r'[\r\n\x00]')))) {
      throw JsonHttpException('Invalid Ollama credential');
    }
    return {...headers, if (key != null) 'authorization': 'Bearer $key'};
  }

  Future<OllamaNativeResponse> send(
    String path, {
    JsonObject? body,
    HttpMethod method = HttpMethod.post,
    Map<String, String> headers = const {},
    Map<String, List<String>> query = const {},
    CancellationToken? cancellation,
  }) async {
    final request = body == null ? null : snapshotJson(body);
    final requestHeaders = _headers({...this.headers, ...headers});
    String? secret;
    try {
      final response = await _transport.send(
        path,
        method: method,
        query: query,
        cancellation: cancellation,
        prepare: () async {
          final headers = await _authenticate(
            requestHeaders,
            (key) => secret = key,
          );
          return request == null
              ? EmptyHttpRequest(headers: headers)
              : JsonHttpRequest(body: request, headers: headers);
        },
      );
      final data = response.statusCode == 204
          ? <String, Object?>{}
          : jsonDecode(response.body);
      if (data is! Map<String, Object?>) {
        throw const FormatException('Expected JSON object');
      }
      if (data['error'] != null) {
        throw JsonHttpException('Ollama request failed', details: data);
      }
      return OllamaNativeResponse(
        data: data,
        statusCode: response.statusCode,
        headers: _cleanHeaders(response.headers, secret),
      );
    } on JsonHttpException catch (error) {
      throw _safeError(error, secret);
    } on http.ClientException {
      throw JsonHttpException('Ollama transport failed');
    } on FormatException {
      throw JsonHttpException('Invalid Ollama response');
    }
  }

  Future<OllamaNativeResponse> _create(
    String path,
    JsonObject body,
    CancellationToken? cancellation,
    Map<String, String> headers,
    Map<String, List<String>> query,
  ) {
    if (body['stream'] == true) {
      throw ArgumentError('Use the streaming method.');
    }
    return send(
      path,
      body: {...body, 'stream': false},
      cancellation: cancellation,
      headers: headers,
      query: query,
    );
  }

  Future<OllamaNativeResponse> createChat(
    JsonObject body, {
    CancellationToken? cancellation,
    Map<String, String> headers = const {},
    Map<String, List<String>> query = const {},
  }) => _create('/api/chat', body, cancellation, headers, query);
  Future<OllamaNativeResponse> createGenerate(
    JsonObject body, {
    CancellationToken? cancellation,
    Map<String, String> headers = const {},
    Map<String, List<String>> query = const {},
  }) => _create('/api/generate', body, cancellation, headers, query);
  Future<OllamaNativeResponse> embed(
    JsonObject body, {
    CancellationToken? cancellation,
    Map<String, String> headers = const {},
    Map<String, List<String>> query = const {},
  }) => send(
    '/api/embed',
    body: body,
    cancellation: cancellation,
    headers: headers,
    query: query,
  );
  Future<OllamaNativeResponse> show(
    JsonObject body, {
    CancellationToken? cancellation,
    Map<String, String> headers = const {},
    Map<String, List<String>> query = const {},
  }) => send(
    '/api/show',
    body: body,
    cancellation: cancellation,
    headers: headers,
    query: query,
  );

  Stream<JsonLineData> streamChat(
    JsonObject body, {
    CancellationToken? cancellation,
    Map<String, String> headers = const {},
    Map<String, List<String>> query = const {},
  }) => _stream('/api/chat', body, cancellation, headers, query);
  Stream<JsonLineData> streamGenerate(
    JsonObject body, {
    CancellationToken? cancellation,
    Map<String, String> headers = const {},
    Map<String, List<String>> query = const {},
  }) => _stream('/api/generate', body, cancellation, headers, query);

  Stream<JsonLineData> _stream(
    String path,
    JsonObject body,
    CancellationToken? cancellation,
    Map<String, String> headers,
    Map<String, List<String>> query,
  ) {
    final request = snapshotJson({...body, 'stream': true});
    final requestHeaders = _headers({...this.headers, ...headers});
    final requestQuery = Map<String, List<String>>.unmodifiable({
      for (final entry in query.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
    return (cancellation ?? CancellationToken()).bindStream(
      (token) => _events(path, request, requestHeaders, requestQuery, token),
    );
  }

  Stream<JsonLineData> _events(
    String path,
    JsonObject body,
    Map<String, String> headers,
    Map<String, List<String>> query,
    CancellationToken token,
  ) async* {
    String? secret;
    var done = false;
    try {
      await for (final event in _transport.streamJsonLines(
        path,
        query: query,
        cancellation: token,
        prepare: () async => JsonHttpRequest(
          body: body,
          headers: await _authenticate(headers, (key) => secret = key),
        ),
      )) {
        if (done) throw JsonHttpException('Data after Ollama completion');
        if (event.data['error'] != null) {
          throw JsonHttpException(
            'Ollama stream failed',
            details: event.data,
            responseHeaders: event.responseHeaders,
          );
        }
        done = event.data['done'] == true;
        yield JsonLineData(
          event.data,
          responseHeaders: _cleanHeaders(event.responseHeaders, secret),
        );
      }
      if (!done) {
        throw JsonHttpException('Ollama stream ended before completion');
      }
    } on JsonHttpException catch (error) {
      throw _safeError(error, secret);
    } on http.ClientException {
      throw JsonHttpException('Ollama transport failed');
    } on FormatException {
      throw JsonHttpException('Invalid Ollama stream');
    }
  }

  OllamaChatModel chatModel({
    required String model,
    api.ModelOptions? options,
    api.ThinkValue? think,
    api.KeepAlive? keepAlive,
    JsonObject Function(JsonObject)? configure,
  }) => OllamaChatModel(
    client: this,
    model: model,
    options: options,
    think: think,
    keepAlive: keepAlive,
    configure: configure,
  );
}

Map<String, String> _headers(Map<String, String> headers) {
  final result = <String, String>{};
  for (final entry in headers.entries) {
    final name = entry.key.toLowerCase();
    if ({
      'authorization',
      'proxy-authorization',
      'cookie',
      'x-api-key',
    }.contains(name)) {
      throw ArgumentError('Credentials are owned by credentialResolver.');
    }
    result[name] = entry.value;
  }
  return Map.unmodifiable(result);
}

String _redact(String value, String? secret) => secret == null || secret.isEmpty
    ? value
    : value
          .replaceAll(secret, '[REDACTED]')
          .replaceAll(
            jsonEncode(secret).substring(1, jsonEncode(secret).length - 1),
            '[REDACTED]',
          );
Object? _clean(Object? value, String? secret) => switch (value) {
  String s => _redact(s, secret),
  Map<String, Object?> m => <String, Object?>{
    for (final e in m.entries) _redact(e.key, secret): _clean(e.value, secret),
  },
  List<Object?> l => [for (final item in l) _clean(item, secret)],
  _ => value,
};
Map<String, String> _cleanHeaders(
  Map<String, String> headers,
  String? secret,
) => {
  for (final entry in headers.entries)
    if (!{
      'authorization',
      'proxy-authorization',
      'set-cookie',
      'cookie',
      'x-api-key',
    }.contains(entry.key.toLowerCase()))
      _redact(entry.key, secret): _redact(entry.value, secret),
};
JsonHttpException _safeError(JsonHttpException error, String? secret) =>
    JsonHttpException(
      'Ollama request failed',
      statusCode: error.statusCode,
      requestId: error.requestId == null
          ? null
          : _redact(error.requestId!, secret),
      details: error.details == null
          ? null
          : _clean(error.details, secret) as JsonObject,
      responseHeaders: _cleanHeaders(error.responseHeaders, secret),
    );
