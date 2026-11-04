import 'dart:convert';
import 'dart:math';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:ollama_dart/ollama_dart.dart' as api;
import 'client.dart';

/// Native chat normalization. The application owns [client].
final class OllamaChatModel implements ChatModel {
  final OllamaNativeClient client;
  final String model;
  final JsonObject _options;
  final api.ThinkValue? think;
  final api.KeepAlive? keepAlive;
  final JsonObject Function(JsonObject)? configure;
  OllamaChatModel({
    required this.client,
    required this.model,
    api.ModelOptions? options,
    this.think,
    this.keepAlive,
    this.configure,
  }) : _options = snapshotJson(options?.toJson() ?? {});

  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
    tools: true,
    structuredOutput: true,
    imageInput: true,
  );
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => cancellation.bindStream((token) => _stream(request, token));

  Stream<ModelEvent> _stream(
    ModelRequest request,
    CancellationToken token,
  ) async* {
    token.throwIfCancelled();
    if (request.tools.any((tool) => tool is NativeModelTool) ||
        request.messages.any(
          (message) => message.toolCalls.any((call) => call is NativeToolCall),
        )) {
      throw UnsupportedError(
        'Ollama normalized chat supports function tools only.',
      );
    }
    if (_options['num_predict'] != null &&
        _options['num_predict'] != request.maxOutputTokens) {
      throw ArgumentError('Set the output limit through maxOutputTokens.');
    }
    final bindings = <String, JsonObject>{};
    final messages = <JsonObject>[
      if (request.instructions != null)
        {'role': 'system', 'content': request.instructions},
    ];
    for (final message in request.messages) {
      if (message.role == MessageRole.tool) {
        final binding = bindings[message.toolCallId];
        if (binding == null) {
          throw const FormatException(
            'Tool result has no matching Ollama call.',
          );
        }
        messages.add({
          'role': 'tool',
          'content': message.text,
          'tool_name': binding['name'],
          'tool_call_id': ?binding['nativeId'],
        });
        continue;
      }
      final replay = message.providerData['ollama.chat'];
      JsonObject wire;
      if (message.role == MessageRole.assistant &&
          replay != null &&
          replay.isNotEmpty) {
        if (replay.length != 1 || replay.single['role'] != 'assistant') {
          throw const FormatException('Invalid Ollama replay.');
        }
        wire = replay.single;
      } else {
        final images = <String>[];
        for (final part in message.content) {
          if (part is ImagePart && message.role == MessageRole.user) {
            final data = RegExp(
              r'^data:image/[A-Za-z0-9.+-]+;base64,(.+)$',
            ).firstMatch(part.url);
            if (data == null || base64Decode(data.group(1)!).isEmpty) {
              throw UnsupportedError(
                'Ollama images require inline base64 data; URLs are not fetched.',
              );
            }
            images.add(data.group(1)!);
          } else if (part is! TextPart) {
            throw UnsupportedError(
              'This content part is not supported by Ollama chat.',
            );
          }
        }
        wire = {
          'role': message.role.name,
          'content': message.text,
          if (images.isNotEmpty) 'images': images,
          if (message.toolCalls.isNotEmpty)
            'tool_calls': [
              for (final call in message.toolCalls)
                {
                  'function': {'name': call.name, 'arguments': call.arguments},
                },
            ],
        };
      }
      final wireCalls = wire['tool_calls'] as List? ?? [];
      final saved = message.providerData['ollama.chat.bindings'];
      if (wireCalls.length != message.toolCalls.length ||
          (saved != null && saved.length != wireCalls.length)) {
        throw const FormatException('Ollama replay call count mismatch.');
      }
      for (var i = 0; i < wireCalls.length; i++) {
        final native = Map<String, Object?>.from(wireCalls[i] as Map);
        final function = _function(native);
        final call = message.toolCalls[i];
        if (function['name'] != call.name ||
            !jsonEquals(function['arguments'], call.arguments) ||
            (saved != null &&
                (saved[i]['localId'] != call.id ||
                    saved[i]['position'] != i ||
                    saved[i]['nativeId'] != native['id']))) {
          throw const FormatException(
            'Ollama replay does not match its tool call.',
          );
        }
        if (bindings.containsKey(call.id)) {
          throw const FormatException('Duplicate local tool ID.');
        }
        bindings[call.id] = {'name': call.name, 'nativeId': ?native['id']};
      }
      messages.add(wire);
    }
    final canonical = snapshotJson({
      'model': model,
      'messages': messages,
      'stream': true,
      'options': {..._options, 'num_predict': request.maxOutputTokens},
      'think': ?think?.toJson(),
      'keep_alive': ?keepAlive?.toJson(),
      if (request.outputSchema != null) 'format': request.outputSchema,
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
    });
    final body = snapshotJson(configure?.call(canonical) ?? canonical);
    for (final field in [
      'model',
      'messages',
      'stream',
      'tools',
      if (request.outputSchema != null) 'format',
    ]) {
      if (!jsonEquals(body[field], canonical[field])) {
        throw ArgumentError('configure cannot replace runtime-owned $field.');
      }
    }
    if (body['options'] is! Map ||
        (body['options'] as Map)['num_predict'] != request.maxOutputTokens) {
      throw ArgumentError('configure cannot replace the runtime output limit.');
    }
    final content = StringBuffer(), thinking = StringBuffer();
    final extras = <String, Object?>{};
    final calls = <int, JsonObject>{};
    final frames = <JsonObject>[];
    JsonObject? terminal;
    String? reportedModel;
    var nextIndex = 0;
    await for (final event in client.streamChat(body, cancellation: token)) {
      token.throwIfCancelled();
      final json = event.data;
      frames.add(json);
      if (json['model'] case final String value when value.isNotEmpty) {
        reportedModel = value;
      }
      final message = json['message'];
      if (message != null) {
        if (message is! Map ||
            (message['role'] != null && message['role'] != 'assistant')) {
          throw const FormatException('Invalid Ollama assistant message.');
        }
        if ((message['images'] as List? ?? []).isNotEmpty) {
          throw UnsupportedError(
            'Ollama output images require native response handling.',
          );
        }
        for (final entry in message.entries) {
          if (!{
            'content',
            'thinking',
            'tool_calls',
            'images',
            'role',
          }.contains(entry.key)) {
            extras[entry.key as String] = entry.value;
          }
        }
        if (message['content'] != null) {
          final text = message['content'] as String;
          content.write(text);
          if (text.isNotEmpty) yield TextDelta(text);
        }
        if (message['thinking'] != null) {
          final text = message['thinking'] as String;
          thinking.write(text);
          if (text.isNotEmpty) yield ReasoningDelta(text);
        }
        for (final raw in message['tool_calls'] as List? ?? []) {
          final call = snapshotJson(Map<String, Object?>.from(raw as Map));
          final function = _function(call);
          final indexValue = function['index'];
          if (indexValue != null && (indexValue is! int || indexValue < 0)) {
            throw const FormatException('Invalid Ollama tool index.');
          }
          int? previous;
          if (call['id'] != null) {
            for (final entry in calls.entries) {
              if (entry.value['id'] == call['id']) previous = entry.key;
            }
          }
          final index = indexValue as int? ?? previous ?? nextIndex;
          nextIndex = max(nextIndex, index + 1);
          final prior = calls[index];
          if (prior != null) {
            final old = _function(prior);
            if (old['name'] != function['name'] ||
                !jsonEquals(old['arguments'], function['arguments']) ||
                (prior['id'] != null &&
                    call['id'] != null &&
                    prior['id'] != call['id'])) {
              throw UnsupportedError(
                'Ambiguous repeated Ollama tool call; use the native stream.',
              );
            }
            calls[index] = snapshotJson({
              ...prior,
              ...call,
              'function': {...old, ...function, 'arguments': old['arguments']},
            });
          } else {
            calls[index] = call;
          }
        }
      }
      if (json['done'] == true) terminal = json;
    }
    token.throwIfCancelled();
    if (terminal == null) {
      throw StateError('Ollama did not complete the response.');
    }
    final reason = terminal['done_reason'];
    if (reason != null && !{'stop', 'length'}.contains(reason)) {
      throw UnsupportedError(
        'Unsupported normalized Ollama completion reason.',
      );
    }
    if (reason == 'length' && calls.isNotEmpty) {
      throw const FormatException(
        'Truncated Ollama response cannot execute tools.',
      );
    }
    final ordered = calls.keys.toList()..sort();
    final localBindings = <JsonObject>[];
    final nativeIds = <String>{};
    for (var position = 0; position < ordered.length; position++) {
      final call = calls[ordered[position]]!;
      final function = _function(call);
      if (call['id'] is String && !nativeIds.add(call['id'] as String)) {
        throw const FormatException('Duplicate native Ollama ID.');
      }
      final id = _id();
      localBindings.add({
        'localId': id,
        'position': position,
        'nativeId': ?call['id'],
      });
      yield ToolCallReady(
        ToolCall(
          id: id,
          name: function['name'] as String,
          arguments: Map<String, Object?>.from(function['arguments'] as Map),
        ),
      );
    }
    yield ProviderOutput(
      provider: 'ollama.chat',
      items: [
        {
          ...extras,
          'role': 'assistant',
          'content': content.toString(),
          if (thinking.isNotEmpty) 'thinking': thinking.toString(),
          if (calls.isNotEmpty)
            'tool_calls': [for (final index in ordered) calls[index]!],
        },
      ],
    );
    if (localBindings.isNotEmpty) {
      yield ProviderOutput(
        provider: 'ollama.chat.bindings',
        items: localBindings,
      );
    }
    yield ProviderOutput(provider: 'ollama.chat.frames', items: frames);
    yield ProviderOutput(
      provider: 'ollama.chat.metadata',
      items: [
        {
          for (final entry in terminal.entries)
            if (entry.key != 'message') entry.key: entry.value,
        },
      ],
    );
    final input = terminal['prompt_eval_count'],
        output = terminal['eval_count'];
    if (input is int && output is int) {
      yield TokenUsage(
        inputTokens: input,
        outputTokens: output,
        model: reportedModel,
        cachedInputTokens: terminal['prompt_eval_cached_count'] as int?,
      );
    }
    yield ModelFinished(
      calls.isNotEmpty
          ? 'tool_calls'
          : reason == 'length'
          ? 'length'
          : reason == null
          ? 'unknown'
          : 'stop',
    );
  }
}

JsonObject _function(JsonObject call) {
  final value = call['function'];
  if (value is! Map ||
      value['name'] is! String ||
      (value['name'] as String).isEmpty ||
      value['arguments'] is! Map ||
      (call['id'] != null &&
          (call['id'] is! String || (call['id'] as String).isEmpty))) {
    throw const FormatException('Invalid Ollama function call.');
  }
  return Map<String, Object?>.from(value);
}

String _id() {
  final random = Random.secure();
  return 'ollama-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
}

final class OllamaEmbeddingResult {
  final List<List<double>> embeddings;
  final JsonObject raw;
  String? get model => raw['model'] as String?;
  int? get inputTokens => raw['prompt_eval_count'] as int?;
  OllamaEmbeddingResult._(this.embeddings, this.raw);
  factory OllamaEmbeddingResult.fromJson(JsonObject data) {
    if ((data['model'] != null && data['model'] is! String) ||
        (data['prompt_eval_count'] != null &&
            (data['prompt_eval_count'] is! int ||
                (data['prompt_eval_count'] as int) < 0))) {
      throw const FormatException('Invalid embedding metadata.');
    }
    final rows = data['embeddings'];
    if (rows is! List) {
      throw const FormatException('Missing embedding vectors.');
    }
    final vectors = <List<double>>[];
    int? size;
    for (final row in rows) {
      if (row is! List ||
          row.any((value) => value is! num || !value.isFinite) ||
          (size != null && row.length != size)) {
        throw const FormatException('Invalid embedding vector.');
      }
      size = row.length;
      vectors.add(
        List<double>.unmodifiable(
          row.map((value) => (value as num).toDouble()),
        ),
      );
    }
    return OllamaEmbeddingResult._(
      List.unmodifiable(vectors),
      snapshotJson(data),
    );
  }
}

final class OllamaEmbeddingModel
    implements EmbeddingModel<api.EmbedRequest, OllamaEmbeddingResult> {
  final OllamaNativeClient client;
  const OllamaEmbeddingModel(this.client);
  @override
  Future<OllamaEmbeddingResult> embed(
    api.EmbedRequest request, {
    CancellationToken? cancellation,
  }) async => OllamaEmbeddingResult.fromJson(
    (await client.embed(request.toJson(), cancellation: cancellation)).data,
  );
}
