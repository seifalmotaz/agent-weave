import 'dart:convert';
import 'dart:typed_data';
import 'package:agent_weave/agent_weave.dart';
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart' as api;

enum OpenAIHttpMethod { get, post, patch, delete }

/// Access JSON operations not yet represented by a typed provider resource.
///
/// Uses the same authentication, error handling, and transport as [client].
/// Administration operations require appropriately scoped server credentials.
/// Prefer typed SDK resources when they cover the operation.
final class OpenAIPlatformApi {
  final api.OpenAIClient client;
  const OpenAIPlatformApi(this.client);

  Future<JsonObject> request(
    String path, {
    OpenAIHttpMethod method = OpenAIHttpMethod.get,
    JsonObject? body,
    Map<String, String>? query,
    Map<String, List<String>>? repeatedQuery,
    String? idempotencyKey,
    CancellationToken? cancellation,
  }) async {
    final response = await _send(
      path,
      method: method,
      body: body,
      query: query,
      repeatedQuery: repeatedQuery,
      idempotencyKey: idempotencyKey,
      cancellation: cancellation,
    );
    if (response.statusCode == 204 || response.body.isEmpty) return const {};
    return Map<String, Object?>.from(jsonDecode(response.body) as Map);
  }

  Future<Uint8List> download(
    String path, {
    Map<String, String>? query,
    CancellationToken? cancellation,
  }) async => (await _send(
    path,
    method: OpenAIHttpMethod.get,
    query: query,
    cancellation: cancellation,
  )).bodyBytes;

  Future<http.Response> _send(
    String path, {
    required OpenAIHttpMethod method,
    JsonObject? body,
    Map<String, String>? query,
    Map<String, List<String>>? repeatedQuery,
    String? idempotencyKey,
    CancellationToken? cancellation,
  }) {
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
            'Idempotency-Key': ?idempotencyKey,
          });
    if (body != null) request.body = jsonEncode(body);
    return client.interceptorChain.execute(
      request,
      abortTrigger: cancellation?.whenCancelled,
      allowRetries: method == OpenAIHttpMethod.get,
    );
  }
}
