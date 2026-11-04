/// Native Together Chat Completions transport and AgentWeave adapter.
library;

import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
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
      snapshotJson({
        'type': 'function',
        'function': {'name': name},
      }),
    );
  }
  Object toJson() => _value;
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
  }) : _json = snapshotJson({
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
  }) : details = details == null ? null : snapshotJson(details);
  @override
  String toString() =>
      'TogetherException: $message${statusCode == null ? '' : ' (HTTP $statusCode)'}';
}

/// Raw native JSON API. The caller owns this client and must close it.
final class TogetherClient {
  final String apiKey;
  final Map<String, String> headers;
  final Map<String, String> query;
  final JsonHttpClient _transport;
  Uri get baseUri => _transport.baseUri;
  Duration get requestTimeout => _transport.requestTimeout;
  TogetherClient({
    required this.apiKey,
    String baseUrl = 'https://api.together.ai/v1',
    Map<String, String> headers = const {},
    Map<String, String> query = const {},
    http.Client? httpClient,
    Duration requestTimeout = const Duration(minutes: 2),
  }) : headers = Map.unmodifiable(headers),
       query = Map.unmodifiable(query),
       _transport = JsonHttpClient(
         baseUrl: baseUrl,
         requestTimeout: requestTimeout,
         httpClient: httpClient,
       ) {
    if (headers.keys.any(
      (key) => {
        'authorization',
        'proxy-authorization',
        'host',
        'cookie',
        'content-length',
        'transfer-encoding',
        'connection',
      }.contains(key.toLowerCase()),
    )) {
      throw ArgumentError('A transport-owned header was supplied.');
    }
  }
  void close() => _transport.close();
  JsonHttpRequest _request(JsonObject body) => JsonHttpRequest(
    body: body,
    headers: {...headers, 'Authorization': 'Bearer $apiKey'},
  );
  Map<String, List<String>> get _query => {
    for (final entry in query.entries) entry.key: [entry.value],
  };
  TogetherException _failure(JsonHttpException error) => TogetherException(
    error.message,
    statusCode: error.statusCode,
    requestId: error.requestId,
    details: error.details,
  );
  Future<JsonObject> createChat(
    JsonObject request, {
    CancellationToken? cancellation,
  }) async {
    if (request['stream'] == true) {
      throw ArgumentError('createChat requires a non-streaming request.');
    }
    try {
      final response = await _transport.sendJson(
        '/chat/completions',
        prepare: () => _request(request),
        cancellation: cancellation,
        query: _query,
      );
      final value = _decode(response.body);
      if (value is! Map<String, dynamic>) {
        throw TogetherException('Invalid JSON response');
      }
      if (value.containsKey('error')) {
        throw TogetherException(
          'Provider returned an error',
          details: value,
          requestId:
              response.headers['x-request-id'] ??
              response.headers['request-id'],
        );
      }
      return value;
    } on JsonHttpException catch (error) {
      throw _failure(error);
    }
  }

  /// Cancelling this subscription aborts only its own HTTP request.
  Stream<JsonObject> streamChat(
    JsonObject request, {
    CancellationToken? cancellation,
  }) {
    var done = false;
    var failed = false;
    final finished = <int>{};
    final n = request['n'] is int ? request['n'] as int : 1;
    return _transport
        .streamJson(
          '/chat/completions',
          prepare: () => _request({...request, 'stream': true}),
          cancellation: cancellation,
          query: _query,
        )
        .transform(
          StreamTransformer<JsonSseEvent, JsonObject>.fromHandlers(
            handleData: (event, sink) {
              if (event is JsonSseDone) {
                done = true;
                return;
              }
              final data = event as JsonSseData;
              final value = data.data;
              if (value.containsKey('error') || data.event == 'error') {
                failed = true;
                sink.addError(
                  TogetherException(
                    'Provider returned a stream error',
                    details: value,
                    requestId:
                        data.responseHeaders['x-request-id'] ??
                        data.responseHeaders['request-id'],
                  ),
                );
                return;
              }
              if (value['choices'] case final List<Object?> choices) {
                for (final choice in choices) {
                  if (choice case {
                    'finish_reason': final String _,
                    'index': final int index,
                  }) {
                    finished.add(index);
                  }
                }
              }
              sink.add(value);
            },
            handleError: (Object error, StackTrace stack, sink) {
              failed = true;
              sink.addError(
                error is JsonHttpException ? _failure(error) : error,
                stack,
              );
            },
            handleDone: (sink) {
              if (!failed && !done && finished.length < n) {
                sink.addError(TogetherException('Truncated stream'));
              }
              sink.close();
            },
          ),
        );
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
  }) =>
      cancellation.bindStream((child) => _stream(request, cancellation: child));

  Stream<ModelEvent> _stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    if (request.tools.any((tool) => tool is NativeModelTool) ||
        request.messages.any(
          (message) => message.toolCalls.any((call) => call is NativeToolCall),
        )) {
      throw UnsupportedError(
        'Together adapter does not implement native tool definitions or calls.',
      );
    }
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
          model: actualModel,
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
