/// JSON HTTP and SSE transport for provider adapters. No agent protocol lives here.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:agent_weave/agent_weave.dart';
import 'package:http/http.dart' as http;

/// Validate and snapshot caller-owned JSON at a provider boundary.
JsonObject snapshotJson(JsonObject value) {
  final visiting = Set<Object>.identity();
  Object? copy(Object? item) {
    if (item == null ||
        item is String ||
        item is bool ||
        (item is num && item.isFinite)) {
      return item;
    }
    if (item is List || item is Map) {
      if (!visiting.add(item)) {
        throw ArgumentError('JSON values cannot contain cycles.');
      }
      try {
        if (item is List) return List<Object?>.unmodifiable(item.map(copy));
        final map = item as Map;
        if (map.keys.any((key) => key is! String)) {
          throw ArgumentError('JSON keys must be strings.');
        }
        return Map<String, Object?>.unmodifiable({
          for (final entry in map.entries)
            entry.key as String: copy(entry.value),
        });
      } finally {
        visiting.remove(item);
      }
    }
    throw ArgumentError('Expected JSON values.');
  }

  return copy(value) as JsonObject;
}

enum HttpMethod { get, post, put, patch, delete, head, options }

/// A request body variant. Its representation never prints headers or data.
sealed class HttpRequestData {
  final Map<String, String> headers;
  HttpRequestData._(Map<String, String> headers)
    : headers = Map.unmodifiable(headers) {
    for (final name in headers.keys) {
      if ({
        'host',
        'content-length',
        'transfer-encoding',
        'connection',
      }.contains(name.toLowerCase())) {
        throw ArgumentError('A transport-owned header was supplied.');
      }
    }
  }
  factory HttpRequestData.json({
    required JsonObject body,
    Map<String, String> headers = const {},
  }) => JsonHttpRequest(body: body, headers: headers);
  factory HttpRequestData.bytes({
    required List<int> bytes,
    String contentType = 'application/octet-stream',
    Map<String, String> headers = const {},
  }) => BinaryHttpRequest(
    bytes: bytes,
    contentType: contentType,
    headers: headers,
  );
  factory HttpRequestData.empty({Map<String, String> headers = const {}}) =>
      EmptyHttpRequest(headers: headers);
}

final class JsonHttpRequest extends HttpRequestData {
  final JsonObject body;
  JsonHttpRequest({
    required JsonObject body,
    Map<String, String> headers = const {},
  }) : body = snapshotJson(body),
       super._(headers);
}

final class BinaryHttpRequest extends HttpRequestData {
  final Uint8List bytes;
  final String contentType;
  BinaryHttpRequest({
    required List<int> bytes,
    this.contentType = 'application/octet-stream',
    Map<String, String> headers = const {},
  }) : bytes = _snapshotBytes(bytes),
       super._(headers) {
    if (contentType.trim().isEmpty ||
        contentType.contains(RegExp(r'[\r\n\x00]'))) {
      throw ArgumentError(
        'Expected a nonempty content type without control delimiters.',
      );
    }
  }
}

Uint8List _snapshotBytes(List<int> bytes) {
  if (bytes.any((byte) => byte < 0 || byte > 255)) {
    throw ArgumentError('Expected bytes between 0 and 255.');
  }
  return Uint8List.fromList(bytes).asUnmodifiableView();
}

final class EmptyHttpRequest extends HttpRequestData {
  EmptyHttpRequest({Map<String, String> headers = const {}}) : super._(headers);
}

/// Response diagnostics are private backend data and are omitted by toString.
class JsonHttpException implements Exception {
  final String message;
  final int? statusCode;
  final String? requestId;
  final JsonObject? details;
  final Map<String, String> responseHeaders;
  JsonHttpException(
    this.message, {
    this.statusCode,
    this.requestId,
    JsonObject? details,
    Map<String, String> responseHeaders = const {},
  }) : details = details == null ? null : snapshotJson(details),
       responseHeaders = Map.unmodifiable(responseHeaders);
  @override
  String toString() =>
      'JsonHttpException: $message${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

sealed class JsonSseEvent {
  const JsonSseEvent();
}

final class JsonSseData extends JsonSseEvent {
  final JsonObject data;
  final String? event;
  final String? id;
  final Map<String, String> responseHeaders;
  JsonSseData(
    JsonObject data, {
    this.event,
    this.id,
    Map<String, String> responseHeaders = const {},
  }) : data = snapshotJson(data),
       responseHeaders = Map.unmodifiable(responseHeaders);
}

final class JsonSseDone extends JsonSseEvent {
  final Map<String, String> responseHeaders;
  JsonSseDone({Map<String, String> responseHeaders = const {}})
    : responseHeaders = Map.unmodifiable(responseHeaders);
}

/// A JSON object from one NDJSON line and its response headers.
final class JsonLineData {
  final JsonObject data;
  final Map<String, String> responseHeaders;
  JsonLineData(
    JsonObject data, {
    Map<String, String> responseHeaders = const {},
  }) : data = snapshotJson(data),
       responseHeaders = Map.unmodifiable(responseHeaders);
}

final class _Scope {
  final CancellationToken cancellation;
  final abort = Completer<void>();
  late final Timer timer;
  late final StreamSubscription<void> registration;
  bool closed = false;
  bool timedOut = false;
  _Scope(this.cancellation, Duration timeout) {
    timer = Timer(timeout, () {
      timedOut = true;
      _abort();
    });
    registration = cancellation.onCancelled.listen((_) {
      if (!closed) _abort();
    });
  }
  void _abort() {
    if (!abort.isCompleted) abort.complete();
  }

  void check() {
    cancellation.throwIfCancelled();
    if (timedOut) throw JsonHttpException('Request timed out');
    if (closed) throw const RunCancelled();
  }

  Future<T> wait<T>(Future<T> future) => Future.any([
    future,
    abort.future.then<T>((_) {
      check();
      throw const RunCancelled();
    }),
  ]);
  void close() {
    closed = true;
    timer.cancel();
    unawaited(registration.cancel());
    _abort();
  }
}

/// Caller owns this client; an injected HTTP client remains caller-owned.
final class JsonHttpClient {
  final Uri baseUri;
  final Duration requestTimeout;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;
  final _scopes = Set<_Scope>.identity();
  JsonHttpClient({
    required String baseUrl,
    this.requestTimeout = const Duration(minutes: 2),
    http.Client? httpClient,
  }) : baseUri = Uri.parse(baseUrl),
       _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null {
    if (!{'http', 'https'}.contains(baseUri.scheme) ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasFragment) {
      throw ArgumentError(
        'Expected an HTTP(S) base URL without credentials or fragment.',
      );
    }
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError('requestTimeout must be positive.');
    }
  }
  void close() {
    _closed = true;
    for (final scope in _scopes.toList()) {
      _release(scope);
    }
    if (_ownsClient) _client.close();
  }

  _Scope _start(CancellationToken? cancellation) {
    if (_closed) throw StateError('The HTTP client is closed.');
    final scope = _Scope(cancellation ?? CancellationToken(), requestTimeout);
    _scopes.add(scope);
    return scope;
  }

  void _release(_Scope scope) {
    scope.close();
    _scopes.remove(scope);
  }

  Uri _uri(String path, Map<String, List<String>> query) {
    final uri = Uri.parse(path);
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment ||
        path
            .split('/')
            .map(Uri.decodeComponent)
            .any((part) => part == '.' || part == '..')) {
      throw ArgumentError(
        'Expected a relative API path without query or fragment.',
      );
    }
    return baseUri.replace(
      path: '${baseUri.path.replaceAll(RegExp(r'/+$'), '')}$path',
      queryParameters: {...baseUri.queryParametersAll, ...query},
    );
  }

  Future<http.StreamedResponse> _send(
    String path,
    FutureOr<HttpRequestData> Function() prepare,
    _Scope scope,
    Map<String, List<String>> query,
    HttpMethod method,
  ) async {
    if (_closed) throw StateError('The HTTP client is closed.');
    scope.check();
    final uri = _uri(path, query);
    final resolved = await scope.wait(Future.sync(prepare));
    scope.check();
    if ((method == HttpMethod.get || method == HttpMethod.head) &&
        resolved is! EmptyHttpRequest) {
      throw ArgumentError('GET and HEAD requests require an empty body.');
    }
    final request =
        http.AbortableRequest(
            method.name.toUpperCase(),
            uri,
            abortTrigger: scope.abort.future,
          )
          ..followRedirects = false
          ..headers.addAll(resolved.headers);
    switch (resolved) {
      case JsonHttpRequest(:final body):
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      case BinaryHttpRequest(:final bytes, :final contentType):
        request.headers['Content-Type'] = contentType;
        request.bodyBytes = bytes;
      case EmptyHttpRequest():
        break;
    }
    final response = await scope.wait(_client.send(request));
    scope.check();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final bytes = <int>[];
      var oversized = false;
      await for (final chunk in _bytes(response.stream, scope)) {
        if (bytes.length + chunk.length > 64 * 1024) {
          oversized = true;
          break;
        }
        bytes.addAll(chunk);
      }
      scope.check();
      JsonObject? details;
      try {
        if (!oversized) {
          final value = jsonDecode(utf8.decode(bytes));
          if (value is Map<String, dynamic>) details = value;
        }
      } on FormatException {
        /* Non-JSON error bodies have no structured details. */
      }
      throw JsonHttpException(
        'Request failed',
        statusCode: response.statusCode,
        requestId:
            response.headers['x-request-id'] ?? response.headers['request-id'],
        details: details,
        responseHeaders: response.headers,
      );
    }
    return response;
  }

  Stream<List<int>> _bytes(Stream<List<int>> source, _Scope scope) async* {
    final iterator = StreamIterator(source);
    try {
      while (await scope.wait(iterator.moveNext())) {
        scope.check();
        yield iterator.current;
      }
    } finally {
      await iterator.cancel();
    }
  }

  /// JSON POST convenience retained for existing provider adapters.
  Future<http.Response> sendJson(
    String path, {
    required FutureOr<JsonHttpRequest> Function() prepare,
    CancellationToken? cancellation,
    Map<String, List<String>> query = const {},
  }) => send(path, prepare: prepare, cancellation: cancellation, query: query);

  Future<http.Response> send(
    String path, {
    required FutureOr<HttpRequestData> Function() prepare,
    HttpMethod method = HttpMethod.post,
    CancellationToken? cancellation,
    Map<String, List<String>> query = const {},
  }) async {
    final scope = _start(cancellation);
    try {
      final response = await _send(path, prepare, scope, query, method);
      final result = await http.Response.fromStream(
        http.StreamedResponse(
          _bytes(response.stream, scope),
          response.statusCode,
          headers: response.headers,
          request: response.request,
          reasonPhrase: response.reasonPhrase,
          isRedirect: response.isRedirect,
          persistentConnection: response.persistentConnection,
        ),
      );
      scope.check();
      return result;
    } on http.RequestAbortedException {
      scope.check();
      rethrow;
    } finally {
      _release(scope);
    }
  }

  /// Streams newline-delimited JSON objects from a POST response.
  Stream<JsonLineData> streamJsonLines(
    String path, {
    required FutureOr<HttpRequestData> Function() prepare,
    CancellationToken? cancellation,
    Map<String, List<String>> query = const {},
  }) {
    _Scope? scope;
    StreamSubscription<JsonLineData>? source;
    late final StreamController<JsonLineData> controller;
    controller = StreamController<JsonLineData>(
      onListen: () {
        if (_closed) {
          controller.addError(StateError('The HTTP client is closed.'));
          unawaited(controller.close());
          return;
        }
        final active = _start(cancellation);
        scope = active;
        source = _streamLines(path, prepare, active, query).listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () {
        if (scope case final active?) _release(active);
        return source?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<JsonLineData> _streamLines(
    String path,
    FutureOr<HttpRequestData> Function() prepare,
    _Scope scope,
    Map<String, List<String>> query,
  ) async* {
    try {
      final response = await _send(
        path,
        prepare,
        scope,
        query,
        HttpMethod.post,
      );
      await for (final line in _bytes(
        response.stream,
        scope,
      ).transform(utf8.decoder).transform(const LineSplitter())) {
        scope.check();
        if (line.trim().isEmpty) continue;
        final Object? value;
        try {
          value = jsonDecode(line);
        } on FormatException {
          throw JsonHttpException('Invalid NDJSON JSON');
        }
        if (value is! Map<String, dynamic>) {
          throw JsonHttpException('Expected an NDJSON JSON object');
        }
        yield JsonLineData(value, responseHeaders: response.headers);
      }
      scope.check();
    } on RunCancelled {
      if (scope.closed) return;
      rethrow;
    } on http.RequestAbortedException {
      if (scope.closed) return;
      scope.check();
      rethrow;
    } finally {
      _release(scope);
    }
  }

  Stream<JsonSseEvent> streamJson(
    String path, {
    required FutureOr<HttpRequestData> Function() prepare,
    CancellationToken? cancellation,
    Map<String, List<String>> query = const {},
  }) {
    _Scope? scope;
    StreamSubscription<JsonSseEvent>? source;
    late final StreamController<JsonSseEvent> controller;
    controller = StreamController<JsonSseEvent>(
      onListen: () {
        if (_closed) {
          controller.addError(StateError('The HTTP client is closed.'));
          unawaited(controller.close());
          return;
        }
        final active = _start(cancellation);
        scope = active;
        source = _stream(path, prepare, active, query).listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () {
        if (scope case final active?) _release(active);
        return source?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<JsonSseEvent> _stream(
    String path,
    FutureOr<HttpRequestData> Function() prepare,
    _Scope scope,
    Map<String, List<String>> query,
  ) async* {
    try {
      final response = await _send(
        path,
        prepare,
        scope,
        query,
        HttpMethod.post,
      );
      final data = <String>[];
      String? event;
      String? id;
      var firstLine = true;
      await for (var line in _bytes(
        response.stream,
        scope,
      ).transform(utf8.decoder).transform(const LineSplitter())) {
        scope.check();
        if (firstLine) {
          firstLine = false;
          if (line.startsWith('\uFEFF')) line = line.substring(1);
        }
        if (line.isEmpty) {
          if (data.isNotEmpty) {
            final payload = data.join('\n');
            data.clear();
            if (payload == '[DONE]') {
              yield JsonSseDone(responseHeaders: response.headers);
              return;
            }
            Object? value;
            try {
              value = jsonDecode(payload);
            } on FormatException {
              throw JsonHttpException('Invalid SSE JSON');
            }
            if (value is! Map<String, dynamic>) {
              throw JsonHttpException('Expected an SSE JSON object');
            }
            yield JsonSseData(
              value,
              event: event,
              id: id,
              responseHeaders: response.headers,
            );
          }
          event = null;
        } else if (!line.startsWith(':')) {
          final colon = line.indexOf(':');
          final field = colon < 0 ? line : line.substring(0, colon);
          var value = colon < 0 ? '' : line.substring(colon + 1);
          if (value.startsWith(' ')) value = value.substring(1);
          switch (field) {
            case 'data':
              data.add(value);
            case 'event':
              event = value;
            case 'id':
              if (!value.contains('\x00')) id = value;
          }
        }
      }
      scope.check();
      if (data.isNotEmpty) throw JsonHttpException('Truncated SSE frame');
    } on RunCancelled {
      if (scope.closed) return;
      rethrow;
    } on http.RequestAbortedException {
      if (scope.closed) return;
      scope.check();
      rethrow;
    } finally {
      _release(scope);
    }
  }
}
