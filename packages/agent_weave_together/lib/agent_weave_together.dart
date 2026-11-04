/// Native Together Chat Completions transport and AgentWeave adapter.
library;

import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:http/http.dart' as http;

/// Typed tool selection for registered function tools.
final class TogetherToolChoice {
  final Object _value;
  const TogetherToolChoice._(this._value);
  static const none = TogetherToolChoice._('none');
  static const auto = TogetherToolChoice._('auto');
  static const required = TogetherToolChoice._('required');
  factory TogetherToolChoice.function(String name) {
    if (name.trim().isEmpty) {
      throw ArgumentError('A function name is required.');
    }
    return TogetherToolChoice._(
      _snapshot({
        'type': 'function',
        'function': {'name': name},
      }),
    );
  }
  Object toJson() => _value;
}

JsonObject _snapshot(JsonObject value) {
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

enum TogetherCompliance { hipaa }

enum TogetherContextLengthBehavior { truncate, error }

enum TogetherReasoningEffort { low, medium, high }

/// Options supported by the pinned Together chat create API.
final class TogetherChatOptions {
  final JsonObject _json;
  TogetherChatOptions({
    Object? chatTemplateKwargs,
    TogetherCompliance? compliance,
    TogetherContextLengthBehavior? contextLengthExceededBehavior,
    bool? echo,
    double? frequencyPenalty,
    Map<String, num>? logitBias,
    int? logprobs,
    double? minP,
    double? presencePenalty,
    bool? reasoningEnabled,
    TogetherReasoningEffort? reasoningEffort,
    double? repetitionPenalty,
    String? safetyModel,
    int? seed,
    List<String>? stop,
    double? temperature,
    TogetherToolChoice? toolChoice,
    int? topK,
    double? topP,
  }) : _json = _snapshot({
         'chat_template_kwargs': ?chatTemplateKwargs,
         'compliance': ?compliance?.name,
         'context_length_exceeded_behavior':
             ?contextLengthExceededBehavior?.name,
         'echo': ?echo,
         'frequency_penalty': ?frequencyPenalty,
         'logit_bias': ?logitBias,
         'logprobs': ?logprobs,
         'min_p': ?minP,
         'presence_penalty': ?presencePenalty,
         if (reasoningEnabled != null)
           'reasoning': {'enabled': reasoningEnabled},
         'reasoning_effort': ?reasoningEffort?.name,
         'repetition_penalty': ?repetitionPenalty,
         'safety_model': ?safetyModel,
         'seed': ?seed,
         'stop': ?stop,
         'temperature': ?temperature,
         if (toolChoice != null) 'tool_choice': toolChoice.toJson(),
         'top_k': ?topK,
         'top_p': ?topP,
       }) {
    if (logprobs != null && (logprobs < 0 || logprobs > 20)) {
      throw ArgumentError.value(logprobs, 'logprobs');
    }
  }
  JsonObject toJson() => _json;
}

Object? _decode(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    throw TogetherException('Invalid JSON');
  }
}

/// Diagnostic details are for trusted backend code and are omitted by toString.
final class TogetherException implements Exception {
  final String message;
  final int? statusCode;
  final String? requestId;
  final JsonObject? details;
  TogetherException(
    this.message, {
    this.statusCode,
    this.requestId,
    JsonObject? details,
  }) : details = details == null ? null : _snapshot(details);
  @override
  String toString() =>
      'TogetherException: $message${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

final class _RequestScope {
  final CancellationToken cancellation;
  final Completer<void> abort = Completer<void>();
  late final Timer timer;
  bool timedOut = false;
  bool closed = false;
  _RequestScope(this.cancellation, Duration timeout) {
    timer = Timer(timeout, () {
      timedOut = true;
      _abort();
    });
    cancellation.whenCancelled.then((_) {
      if (!closed) _abort();
    });
  }
  void _abort() {
    if (!abort.isCompleted) abort.complete();
  }

  void check() {
    cancellation.throwIfCancelled();
    if (timedOut) throw TogetherException('Request timed out');
  }

  void close() {
    closed = true;
    timer.cancel();
    _abort();
  }
}

/// Raw native JSON API. The caller owns this client and must close it.
final class TogetherClient {
  final String apiKey;
  final Uri baseUri;
  final Map<String, String> headers;
  final Map<String, String> query;
  final Duration requestTimeout;
  final http.Client _client;
  final bool _ownsClient;
  TogetherClient({
    required this.apiKey,
    String baseUrl = 'https://api.together.ai/v1',
    Map<String, String> headers = const {},
    Map<String, String> query = const {},
    http.Client? httpClient,
    this.requestTimeout = const Duration(minutes: 2),
  }) : baseUri = Uri.parse(baseUrl),
       headers = Map.unmodifiable(headers),
       query = Map.unmodifiable(query),
       _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError('requestTimeout must be positive.');
    }
    if (!{'http', 'https'}.contains(baseUri.scheme) ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasFragment) {
      throw ArgumentError(
        'Expected an HTTP(S) base URL without credentials or fragment.',
      );
    }
    if (headers.keys.any(
      (key) => {
        'authorization',
        'proxy-authorization',
        'host',
        'cookie',
        'content-length',
        'transfer-encoding',
      }.contains(key.toLowerCase()),
    )) {
      throw ArgumentError('A transport-owned header was supplied.');
    }
  }
  void close() {
    if (_ownsClient) _client.close();
  }

  Uri get _uri => baseUri.replace(
    path: '${baseUri.path.replaceAll(RegExp(r'/+$'), '')}/chat/completions',
    queryParameters: {...baseUri.queryParameters, ...query},
  );
  Future<http.StreamedResponse> _send(
    JsonObject request,
    _RequestScope scope,
  ) async {
    scope.check();
    final message =
        http.AbortableRequest('POST', _uri, abortTrigger: scope.abort.future)
          ..headers.addAll({
            ...headers,
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          })
          ..body = jsonEncode(request);
    try {
      final response = await _client.send(message);
      scope.check();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        // Bound error diagnostics; a provider error body is untrusted input.
        final bytes = <int>[];
        var oversized = false;
        await for (final chunk in response.stream) {
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
          // Non-JSON, malformed or oversized bodies have no structured details.
        }
        throw TogetherException(
          'Request failed',
          statusCode: response.statusCode,
          requestId:
              response.headers['x-request-id'] ??
              response.headers['request-id'],
          details: details,
        );
      }
      return response;
    } on http.RequestAbortedException {
      scope.check();
      rethrow;
    }
  }

  Future<JsonObject> createChat(
    JsonObject request, {
    CancellationToken? cancellation,
  }) async {
    final token = cancellation ?? CancellationToken();
    if (request['stream'] == true) {
      throw ArgumentError('createChat requires a non-streaming request.');
    }
    final scope = _RequestScope(token, requestTimeout);
    try {
      final response = await _send(request, scope);
      final body = await response.stream.bytesToString();
      scope.check();
      final decoded = _decode(body);
      if (decoded is! Map<String, dynamic>) {
        throw TogetherException('Invalid JSON response');
      }
      if (decoded.containsKey('error')) {
        throw TogetherException(
          'Provider returned an error',
          requestId:
              response.headers['x-request-id'] ??
              response.headers['request-id'],
          details: decoded,
        );
      }
      return Map<String, Object?>.from(decoded);
    } on http.RequestAbortedException {
      scope.check();
      rethrow;
    } finally {
      scope.close();
    }
  }

  /// Streams unmodified native JSON events; [DONE] is consumed by the client.
  /// Cancelling the subscription also aborts its pending HTTP request.
  Stream<JsonObject> streamChat(
    JsonObject request, {
    CancellationToken? cancellation,
  }) {
    _RequestScope? scope;
    StreamSubscription<JsonObject>? source;
    late final StreamController<JsonObject> controller;
    controller = StreamController<JsonObject>(
      onListen: () {
        final active = _RequestScope(
          cancellation ?? CancellationToken(),
          requestTimeout,
        );
        scope = active;
        source = _streamChat(request, active).listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () {
        scope?.close();
        return source?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<JsonObject> _streamChat(
    JsonObject request,
    _RequestScope scope,
  ) async* {
    var done = false;
    final finished = <int>{};
    final n = request['n'] is int ? request['n'] as int : 1;
    final data = <String>[];
    try {
      final response = await _send({...request, 'stream': true}, scope);
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        scope.check();
        if (line.isEmpty) {
          if (data.isEmpty) continue;
          final payload = data.join('\n');
          data.clear();
          if (payload == '[DONE]') {
            done = true;
            break;
          }
          final value = _decode(payload);
          if (value is! Map<String, dynamic>) {
            throw TogetherException('Invalid stream event');
          }
          if (value.containsKey('error')) {
            throw TogetherException(
              'Provider returned a stream error',
              requestId:
                  response.headers['x-request-id'] ??
                  response.headers['request-id'],
              details: value,
            );
          }
          final choices = value['choices'];
          if (choices is List) {
            for (final choice in choices) {
              if (choice is Map &&
                  choice['finish_reason'] != null &&
                  choice['index'] is int) {
                finished.add(choice['index'] as int);
              }
            }
          }
          yield Map<String, Object?>.from(value);
        } else if (line.startsWith('data:')) {
          var value = line.substring(5);
          if (value.startsWith(' ')) value = value.substring(1);
          data.add(value);
        }
      }
      scope.check();
      if (data.isNotEmpty || (!done && finished.length < n)) {
        throw TogetherException('Truncated stream');
      }
    } on http.RequestAbortedException {
      if (scope.closed) return;
      scope.check();
      rethrow;
    } finally {
      scope.close();
    }
  }
}

/// AgentWeave owns the tool loop. Multimedia support depends on the model.
final class TogetherChatModel implements ChatModel {
  final TogetherClient client;
  final String model;
  final TogetherChatOptions options;
  TogetherChatModel({
    required this.client,
    required this.model,
    TogetherChatOptions? options,
  }) : options = options ?? TogetherChatOptions();
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
    tools: true,
    structuredOutput: true,
    imageInput: true,
    audioInput: true,
    videoInput: true,
  );

  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    final choice = options.toJson()['tool_choice'];
    if (choice == 'required' && request.tools.isEmpty) {
      throw ArgumentError('Required toolChoice needs registered tools.');
    }
    if (choice case {
      'type': 'function',
      'function': {'name': final String name},
    }) {
      if (!request.tools.any((tool) => tool.name == name)) {
        throw ArgumentError('toolChoice must select a registered tool.');
      }
    }
    final messages = <JsonObject>[
      if (request.instructions != null)
        {'role': 'system', 'content': request.instructions},
      for (final message in request.messages) _message(message),
    ];
    final body = <String, Object?>{
      ...options.toJson(),
      'model': model,
      'messages': messages,
      'max_tokens': request.maxOutputTokens,
      'n': 1,
      'stream': true,
      if (request.tools.isNotEmpty)
        'tools': [
          for (final tool in request.tools)
            {
              'type': 'function',
              'function': {
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.inputSchema,
              },
            },
        ],
      if (request.outputSchema != null)
        'response_format': {
          'type': 'json_schema',
          'json_schema': {'name': 'result', 'schema': request.outputSchema},
        },
    };
    final calls = <int, _Call>{};
    final reasoning = StringBuffer();
    String? actualModel;
    String? finish;
    await for (final event in client.streamChat(
      body,
      cancellation: cancellation,
    )) {
      actualModel = event['model'] as String? ?? actualModel;
      if (event['usage'] case final Map<String, dynamic> usage) {
        yield TokenUsage(
          inputTokens: (usage['prompt_tokens'] as num).toInt(),
          outputTokens: (usage['completion_tokens'] as num).toInt(),
          model: actualModel ?? model,
          cachedInputTokens:
              (usage['prompt_tokens_details'] as Map?)?['cached_tokens']
                  as int?,
          reasoningTokens:
              (usage['completion_tokens_details'] as Map?)?['reasoning_tokens']
                  as int?,
        );
      }
      for (final choice in event['choices'] as List? ?? const []) {
        if ((choice as Map)['index'] != 0) {
          throw TogetherException('Unexpected choice index');
        }
        final delta = choice['delta'] as Map? ?? const {};
        if (delta['function_call'] != null ||
            choice['finish_reason'] == 'function_call') {
          throw UnsupportedError(
            'Legacy function_call is not supported by the agent adapter.',
          );
        }
        if (delta['content'] case final String text) yield TextDelta(text);
        final thought = delta['reasoning_content'] ?? delta['reasoning'];
        if (thought is String) {
          reasoning.write(thought);
          yield ReasoningDelta(thought);
        }
        for (final item in delta['tool_calls'] as List? ?? const []) {
          final part = item as Map;
          final index = part['index'];
          if (index is! int || index < 0) {
            throw TogetherException('Invalid tool call index');
          }
          final call = calls.putIfAbsent(index, _Call.new);
          if (part['id'] case final String id) call.id = id;
          final function = part['function'] as Map?;
          if (function?['name'] case final String name) call.name = name;
          if (function?['arguments'] case final String arguments) {
            call.arguments.write(arguments);
          }
        }
        if (choice['finish_reason'] case final String reason) finish = reason;
      }
    }
    if (finish == null) {
      throw TogetherException('Stream ended without a finish reason');
    }
    if (!{'stop', 'eos', 'tool_calls', 'length'}.contains(finish)) {
      throw TogetherException('Unsupported finish reason');
    }
    if ((finish == 'tool_calls') != calls.isNotEmpty) {
      throw TogetherException('Incomplete tool calls');
    }
    if (reasoning.isNotEmpty) {
      yield ProviderOutput(
        provider: 'together.chat',
        items: [
          {'reasoning_content': reasoning.toString()},
        ],
      );
    }
    final indices = calls.keys.toList()..sort();
    for (final index in indices) {
      final call = calls[index]!;
      if (call.id == null ||
          call.id!.isEmpty ||
          call.name == null ||
          call.name!.isEmpty) {
        throw TogetherException('Incomplete tool call');
      }
      final value = _decode(call.arguments.toString());
      if (value is! Map<String, dynamic>) {
        throw TogetherException('Invalid tool arguments');
      }
      yield ToolCallReady(
        ToolCall(
          id: call.id!,
          name: call.name!,
          arguments: Map<String, Object?>.from(value),
        ),
      );
    }
    yield ModelFinished(finish);
  }
}

final class _Call {
  String? id;
  String? name;
  final arguments = StringBuffer();
}

JsonObject _message(ChatMessage message) {
  if (message.role == MessageRole.tool) {
    return {
      'role': 'tool',
      'tool_call_id': message.toolCallId,
      'content': message.text,
    };
  }
  if (message.role == MessageRole.assistant) {
    if (message.content.any((part) => part is! TextPart)) {
      throw UnsupportedError('Assistant multimedia content is unsupported.');
    }
    final replay = message.providerData['together.chat'];
    return {
      'role': 'assistant',
      'content': message.text,
      if (replay != null &&
          replay.isNotEmpty &&
          replay.first['reasoning_content'] != null)
        'reasoning_content': replay.first['reasoning_content'],
      if (message.toolCalls.isNotEmpty)
        'tool_calls': [
          for (final (index, call) in message.toolCalls.indexed)
            {
              'index': index,
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': jsonEncode(call.arguments),
              },
            },
        ],
    };
  }
  return {
    'role': 'user',
    'content': [
      for (final part in message.content)
        switch (part) {
          TextPart(:final text) => {'type': 'text', 'text': text},
          ImagePart(:final url) => {
            'type': 'image_url',
            'image_url': {'url': url},
          },
          VideoPart(:final url) => {
            'type': 'video_url',
            'video_url': {'url': url},
          },
          AudioPart(:final data, :final format) when format == 'wav' => {
            'type': 'input_audio',
            'input_audio': {'data': data, 'format': format},
          },
          AudioPart() => throw UnsupportedError(
            'Together supports wav input audio only.',
          ),
          FilePart() || DocumentPart() => throw UnsupportedError(
            'Together chat does not support documents.',
          ),
        },
    ],
  };
}
