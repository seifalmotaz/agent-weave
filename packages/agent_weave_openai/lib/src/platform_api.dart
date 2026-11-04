import 'dart:convert';
import 'dart:typed_data';
import 'package:agent_weave/agent_weave.dart';
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' as api;

enum OpenAIHttpMethod { get, post, put, patch, delete, head }

/// Access JSON operations not yet represented by a typed provider resource.
///
/// Uses the same authentication, error handling, and transport as [client].
/// Administration operations require appropriately scoped server credentials.
/// Prefer typed SDK resources when they cover the operation.
final class OpenAIPlatformApi {
  final api.OpenAIClient client;
  const OpenAIPlatformApi(this.client);

  /// Decode an object response. Use [requestJson] for other JSON root types.
  Future<JsonObject> request(
    String path, {
    OpenAIHttpMethod method = OpenAIHttpMethod.get,
    JsonObject? body,
    Map<String, String>? query,
    Map<String, List<String>>? repeatedQuery,
    Map<String, String>? headers,
    String? idempotencyKey,
    CancellationToken? cancellation,
  }) async {
    final value = await requestJson(
      path,
      method: method,
      body: body,
      query: query,
      repeatedQuery: repeatedQuery,
      headers: headers,
      idempotencyKey: idempotencyKey,
      cancellation: cancellation,
    );
    if (value == null) return const {};
    if (value is! Map<String, Object?>) {
      throw const FormatException(
        'Expected an object response. Use requestJson for other JSON values.',
      );
    }
    return value;
  }

  /// Preserve any JSON root type, including arrays, primitives and null.
  Future<Object?> requestJson(
    String path, {
    OpenAIHttpMethod method = OpenAIHttpMethod.get,
    Object? body,
    Map<String, String>? query,
    Map<String, List<String>>? repeatedQuery,
    Map<String, String>? headers,
    String? idempotencyKey,
    CancellationToken? cancellation,
  }) async {
    final response = await send(
      path,
      method: method,
      body: body,
      query: query,
      repeatedQuery: repeatedQuery,
      headers: headers,
      idempotencyKey: idempotencyKey,
      cancellation: cancellation,
    );
    if (response.statusCode == 204 || response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  Future<Uint8List> download(
    String path, {
    Map<String, String>? query,
    Map<String, List<String>>? repeatedQuery,
    Map<String, String>? headers,
    CancellationToken? cancellation,
  }) async => (await send(
    path,
    query: query,
    repeatedQuery: repeatedQuery,
    headers: headers,
    cancellation: cancellation,
  )).bodyBytes;

  /// Buffer the unmodified response, including headers, status and bytes.
  /// This method is not an SSE or multipart transport. Prefer typed SDK resources.
  /// Authentication remains owned by the client's auth provider.
  Future<http.Response> send(
    String path, {
    OpenAIHttpMethod method = OpenAIHttpMethod.get,
    Object? body,
    Map<String, String>? query,
    Map<String, List<String>>? repeatedQuery,
    Map<String, String>? headers,
    String? idempotencyKey,
    CancellationToken? cancellation,
  }) async {
    cancellation?.throwIfCancelled();
    final uri = Uri.parse(path);
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        uri.hasAuthority ||
        uri.hasScheme ||
        uri.hasQuery ||
        uri.hasFragment ||
        path
            .split('/')
            .map(Uri.decodeComponent)
            .any((part) => part == '..' || part == '.')) {
      throw ArgumentError.value(
        path,
        'path',
        'Expected a relative API path without query or fragment.',
      );
    }
    for (final name in headers?.keys ?? const <String>[]) {
      if (const {
        'authorization',
        'proxy-authorization',
        'host',
        'cookie',
        'content-length',
        'transfer-encoding',
      }.contains(name.toLowerCase())) {
        throw ArgumentError.value(
          name,
          'headers',
          'This header is owned by authentication or transport.',
        );
      }
    }
    final config = client.config;
    final base = Uri.parse(config.baseUrl);
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    final parameters = <String, Object?>{
      ...base.queryParametersAll,
      ...?query,
      ...?repeatedQuery,
    };
    final request =
        http.Request(
            method.name.toUpperCase(),
            base.replace(
              path: '$basePath$path',
              queryParameters: parameters.isEmpty ? null : parameters,
            ),
          )
          ..headers.addAll({
            'Content-Type': 'application/json',
            ...config.defaultHeaders,
            if (config.organization != null)
              'OpenAI-Organization': config.organization!,
            if (config.project != null) 'OpenAI-Project': config.project!,
            if (config.apiVersion != null) 'OpenAI-Version': config.apiVersion!,
            ...?headers,
            'Idempotency-Key': ?idempotencyKey,
          });
    if (body != null) request.body = jsonEncode(body);
    return client.interceptorChain.execute(
      request,
      abortTrigger: cancellation?.whenCancelled,
      allowRetries:
          method == OpenAIHttpMethod.get || method == OpenAIHttpMethod.head,
    );
  }
}
