import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:http/http.dart' as http;
import 'protocol.dart';
import 'hosted_tool.dart';

export 'package:agent_weave_http/agent_weave_http.dart'
    show JsonHttpException, JsonSseEvent, JsonSseData, JsonSseDone, HttpMethod;

typedef AnthropicCredentialResolver = FutureOr<String> Function();

/// Original JSON and response headers. Treat both as private backend data.
final class AnthropicNativeResponse {
  final JsonObject data;
  final int statusCode;
  final Map<String, String> headers;
  AnthropicNativeResponse({
    required JsonObject data,
    required this.statusCode,
    required Map<String, String> headers,
  }) : data = snapshotJson(data),
       headers = Map.unmodifiable(headers);
}

/// Native JSON/SSE access with request-scoped cancellation and no automatic retries.
/// The application closes this client; an injected HTTP client remains borrowed.
final class AnthropicNativeClient {
  final JsonHttpClient _transport;
  final AnthropicCredentialResolver credentialResolver;
  final Map<String, String> headers;

  AnthropicNativeClient({
    required this.credentialResolver,
    String baseUrl = 'https://api.anthropic.com',
    String apiVersion = '2023-06-01',
    List<String> betas = const [],
    String? workspaceId,
    String? userProfileId,
    Map<String, String> headers = const {},
    Duration requestTimeout = const Duration(minutes: 2),
    http.Client? httpClient,
  }) : _transport = JsonHttpClient(
         baseUrl: baseUrl,
         requestTimeout: requestTimeout,
         httpClient: httpClient,
       ),
       headers = _headers({
         'anthropic-version': apiVersion,
         if (betas.isNotEmpty) 'anthropic-beta': betas.join(','),
         'anthropic-workspace-id': ?workspaceId,
         'anthropic-user-profile-id': ?userProfileId,
         ...headers,
       });

  factory AnthropicNativeClient.withApiKey({
    required String apiKey,
    String baseUrl = 'https://api.anthropic.com',
    String apiVersion = '2023-06-01',
    List<String> betas = const [],
    String? workspaceId,
    String? userProfileId,
    Map<String, String> headers = const {},
    Duration requestTimeout = const Duration(minutes: 2),
    http.Client? httpClient,
  }) => AnthropicNativeClient(
    credentialResolver: () => apiKey,
    baseUrl: baseUrl,
    apiVersion: apiVersion,
    betas: betas,
    workspaceId: workspaceId,
    userProfileId: userProfileId,
    headers: headers,
    requestTimeout: requestTimeout,
    httpClient: httpClient,
  );

  void close() => _transport.close();

  Future<JsonHttpRequest> _prepare(
    JsonObject body,
    Map<String, String> headers,
    void Function(String) remember,
  ) async {
    String key;
    try {
      key = await credentialResolver();
    } catch (_) {
      throw JsonHttpException('Anthropic credential resolution failed');
    }
    remember(key);
    if (key.trim().isEmpty || key.contains(RegExp(r'[\r\n\x00]'))) {
      throw JsonHttpException('Invalid Anthropic credential');
    }
    return JsonHttpRequest(body: body, headers: {...headers, 'x-api-key': key});
  }

  /// Send native JSON without a typed decoder dropping unknown fields.
  Future<AnthropicNativeResponse> send(
    String path, {
    JsonObject? body,
    HttpMethod method = HttpMethod.post,
    Map<String, List<String>> query = const {},
    Map<String, String> headers = const {},
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
          final prepared = await _prepare(
            request ?? {},
            requestHeaders,
            (key) => secret = key,
          );
          return request == null
              ? EmptyHttpRequest(headers: prepared.headers)
              : prepared;
        },
      );
      final data = jsonDecode(response.body);
      if (data is! Map<String, Object?>) {
        throw const FormatException('Expected JSON object');
      }
      return AnthropicNativeResponse(
        data: data,
        statusCode: response.statusCode,
        headers: _cleanHeaders(response.headers, secret),
      );
    } on JsonHttpException catch (error) {
      throw _safeError(error, secret);
    } on http.ClientException {
      throw JsonHttpException('Anthropic transport failed');
    } on FormatException {
      throw JsonHttpException('Invalid Anthropic JSON response');
    }
  }

  Future<AnthropicNativeResponse> createMessage(
    JsonObject body, {
    CancellationToken? cancellation,
    Map<String, String> headers = const {},
    Map<String, List<String>> query = const {},
  }) {
    if (body['stream'] == true) throw ArgumentError('Use streamMessages.');
    return send(
      '/v1/messages',
      body: body,
      cancellation: cancellation,
      headers: headers,
      query: query,
    );
  }

  Future<AnthropicNativeResponse> countTokens(
    JsonObject body, {
    CancellationToken? cancellation,
    Map<String, String> headers = const {},
    Map<String, List<String>> query = const {},
  }) => send(
    '/v1/messages/count_tokens',
    body: body,
    cancellation: cancellation,
    headers: headers,
    query: query,
  );

  Stream<JsonSseEvent> streamMessages(
    JsonObject body, {
    CancellationToken? cancellation,
    Map<String, String> headers = const {},
    Map<String, List<String>> query = const {},
  }) {
    final request = snapshotJson({...body, 'stream': true});
    final requestHeaders = _headers({...this.headers, ...headers});
    final requestQuery = Map<String, List<String>>.unmodifiable({
      for (final entry in query.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
    return (cancellation ?? CancellationToken()).bindStream(
      (token) => _stream(request, requestHeaders, requestQuery, token),
    );
  }

  Stream<JsonSseEvent> _stream(
    JsonObject request,
    Map<String, String> headers,
    Map<String, List<String>> query,
    CancellationToken token,
  ) async* {
    String? secret;
    var stopped = false;
    try {
      await for (final event in _transport.streamJson(
        '/v1/messages',
        cancellation: token,
        query: query,
        prepare: () => _prepare(request, headers, (key) => secret = key),
      )) {
        if (event is! JsonSseData) continue;
        if (event.data['type'] == 'error') {
          throw JsonHttpException(
            'Anthropic stream failed',
            details: event.data,
            requestId: event.responseHeaders['request-id'],
            responseHeaders: event.responseHeaders,
          );
        }
        if (stopped) {
          throw JsonHttpException('Event after Anthropic message_stop');
        }
        stopped = event.data['type'] == 'message_stop';
        yield JsonSseData(
          event.data,
          event: event.event,
          id: event.id,
          responseHeaders: _cleanHeaders(event.responseHeaders, secret),
        );
      }
      if (!stopped) {
        throw JsonHttpException('Anthropic stream ended before message_stop');
      }
    } on JsonHttpException catch (error) {
      throw _safeError(error, secret);
    } on http.ClientException {
      throw JsonHttpException('Anthropic transport failed');
    } on FormatException {
      throw JsonHttpException('Invalid Anthropic stream');
    }
  }

  AnthropicProtocolModel chatModel({
    required String model,
    JsonObject Function(JsonObject)? configure,
    List<AnthropicHostedTool> hostedTools = const [],
  }) => AnthropicProtocolModel(
    model: model,
    configure: configure,
    hostedTools: List.unmodifiable(hostedTools),
    transport: (body, token) async* {
      await for (final event in streamMessages(body, cancellation: token)) {
        if (event is JsonSseData) yield event.data;
      }
    },
  );
}

Map<String, String> _headers(Map<String, String> headers) {
  final normalized = <String, String>{};
  for (final entry in headers.entries) {
    final key = entry.key.toLowerCase();
    if ({
      'x-api-key',
      'authorization',
      'proxy-authorization',
      'cookie',
    }.contains(key)) {
      throw ArgumentError(
        'Anthropic credentials are owned by credentialResolver.',
      );
    }
    normalized[key] = entry.value;
  }
  return Map.unmodifiable(normalized);
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
      'x-api-key',
      'authorization',
      'proxy-authorization',
      'set-cookie',
      'cookie',
    }.contains(entry.key.toLowerCase()))
      _redact(entry.key, secret): _redact(entry.value, secret),
};
JsonHttpException _safeError(JsonHttpException error, String? secret) =>
    JsonHttpException(
      'Anthropic request failed',
      statusCode: error.statusCode,
      requestId: error.requestId == null
          ? null
          : _redact(error.requestId!, secret),
      details: error.details == null
          ? null
          : _clean(error.details, secret) as JsonObject,
      responseHeaders: _cleanHeaders(error.responseHeaders, secret),
    );
