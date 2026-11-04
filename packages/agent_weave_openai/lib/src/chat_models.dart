import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:openai_dart/openai_dart.dart' as api;

/// Caller owns [client] and must close it when the application shuts down.
final class OpenAIResponsesModel implements ChatModel {
  final api.OpenAIClient client;
  final String model;

  /// Typed access to provider-specific options without weakening the core API.
  final api.CreateResponseRequest Function(api.CreateResponseRequest)?
  configure;
  const OpenAIResponsesModel({
    required this.client,
    required this.model,
    this.configure,
  });

  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
    tools: true,
    structuredOutput: true,
    imageInput: true,
    fileInput: true,
    videoInput: true,
  );

  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    final input = <JsonObject>[];
    for (final message in request.messages) {
      if (message.role == MessageRole.tool) {
        input.add({
          'type': 'function_call_output',
          'call_id': message.toolCallId,
          'output': message.text,
        });
        continue;
      }
      final replay = message.providerData['openai.responses'];
      if (replay != null && replay.isNotEmpty) {
        input.addAll(replay);
        continue;
      }
      if (message.content.isNotEmpty) {
        input.add({
          'type': 'message',
          'role': message.role.name,
          'content': [
            for (final part in message.content)
              switch (part) {
                TextPart(:final text) => {
                  'type': message.role == MessageRole.assistant
                      ? 'output_text'
                      : 'input_text',
                  'text': text,
                },
                ImagePart(:final url) => {
                  'type': 'input_image',
                  'image_url': url,
                },
                FilePart(:final fileId) => {
                  'type': 'input_file',
                  'file_id': fileId,
                },
                VideoPart(:final url) => {
                  'type': 'input_video',
                  'video_url': url,
                },
                AudioPart() => throw const FormatException(
                  'Responses model does not accept inline audio.',
                ),
              },
          ],
        });
      }
      for (final call in message.toolCalls) {
        input.add({
          'type': 'function_call',
          'call_id': call.id,
          'name': call.name,
          'arguments': jsonEncode(call.arguments),
        });
      }
    }
    var params = api.CreateResponseRequest.fromJson({
      'model': model,
      'input': input,
      'store': false,
      'include': ['reasoning.encrypted_content'],
      'max_output_tokens': request.maxOutputTokens,
      if (request.instructions != null) 'instructions': request.instructions,
      if (request.tools.isNotEmpty)
        'tools': [
          for (final tool in request.tools)
            {
              'type': 'function',
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.inputSchema,
              'strict': false,
            },
        ],
      if (request.outputSchema != null)
        'text': {
          'format': {
            'type': 'json_schema',
            'name': 'result',
            'schema': request.outputSchema,
            'strict': true,
          },
        },
    });
    final configured = configure?.call(params) ?? params;
    final options = _preserveRequest(
      params.toJson(),
      configured.toJson(),
      owned: ['input', 'instructions', 'max_output_tokens'],
      schemaField: 'text',
    );
    options['include'] = <Object?>{
      ...?options['include'] as List?,
      'reasoning.encrypted_content',
    }.toList();
    params = api.CreateResponseRequest.fromJson(options);

    await for (final event in client.responses.createStream(
      params,
      abortTrigger: cancellation.whenCancelled,
    )) {
      cancellation.throwIfCancelled();
      final json = event.toJson();
      switch (json['type']) {
        case 'response.output_text.delta':
          yield TextDelta(json['delta'] as String);
        case 'response.refusal.delta':
          yield TextDelta(json['delta'] as String);
        case 'response.reasoning_summary_text.delta':
          yield ReasoningDelta(json['delta'] as String);
        case 'response.output_item.done':
          final item = json['item'] as Map;
          if (item['type'] == 'function_call') {
            yield ToolCallReady(
              ToolCall(
                id: item['call_id'] as String,
                name: item['name'] as String,
                arguments: Map<String, Object?>.from(
                  jsonDecode(item['arguments'] as String) as Map,
                ),
              ),
            );
          } else if (const {
            'computer_call',
            'local_shell_call',
            'shell_call',
            'custom_tool_call',
            'apply_patch_call',
            'mcp_approval_request',
            'tool_search_call',
          }.contains(item['type'])) {
            throw UnsupportedError(
              'OpenAI ${item['type']} requires a native continuation handler. '
              'This agent adapter currently executes registered function tools only.',
            );
          }
        case 'response.completed' || 'response.incomplete':
          final response = json['response'] as Map;
          yield ProviderOutput(
            provider: 'openai.responses',
            items: [
              for (final item in response['output'] as List? ?? [])
                Map<String, Object?>.from(item as Map),
            ],
          );
          if (response['usage'] case final Map<String, dynamic> usage) {
            yield TokenUsage(
              inputTokens: usage['input_tokens'] as int,
              outputTokens: usage['output_tokens'] as int,
              model: response['model'] as String? ?? params.model,
              cachedInputTokens:
                  (usage['input_tokens_details'] as Map?)?['cached_tokens']
                      as int?,
              reasoningTokens:
                  (usage['output_tokens_details'] as Map?)?['reasoning_tokens']
                      as int?,
            );
          }
          yield ModelFinished(
            json['type'] == 'response.incomplete' ? 'length' : 'stop',
          );
        case 'response.failed' || 'error':
          throw StateError('OpenAI response failed.');
      }
    }
  }
}

final class OpenAIChatModel implements ChatModel {
  final api.OpenAIClient client;
  final String model;
  final api.ChatCompletionCreateRequest Function(
    api.ChatCompletionCreateRequest,
  )?
  configure;
  const OpenAIChatModel({
    required this.client,
    required this.model,
    this.configure,
  });
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
    tools: true,
    structuredOutput: true,
    imageInput: true,
    audioInput: true,
  );

  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    var params = api.ChatCompletionCreateRequest.fromJson({
      'model': model,
      'max_completion_tokens': request.maxOutputTokens,
      'stream_options': {'include_usage': true},
      'messages': [
        if (request.instructions != null)
          {'role': 'system', 'content': request.instructions},
        for (final message in request.messages)
          {
            'role': message.role.name,
            if (message.role == MessageRole.tool) ...{
              'tool_call_id': message.toolCallId,
              'content': message.text,
            } else ...{
              'content': [
                for (final part in message.content)
                  switch (part) {
                    TextPart(:final text) => {'type': 'text', 'text': text},
                    ImagePart(:final url) => {
                      'type': 'image_url',
                      'image_url': {'url': url},
                    },
                    FilePart() => throw const FormatException(
                      'Chat model does not accept files.',
                    ),
                    AudioPart(:final data, :final format) => {
                      'type': 'input_audio',
                      'input_audio': {'data': data, 'format': format},
                    },
                    VideoPart() => throw const FormatException(
                      'Chat model does not accept video.',
                    ),
                  },
              ],
              if (message.toolCalls.isNotEmpty)
                'tool_calls': [
                  for (final call in message.toolCalls)
                    {
                      'id': call.id,
                      'type': 'function',
                      'function': {
                        'name': call.name,
                        'arguments': jsonEncode(call.arguments),
                      },
                    },
                ],
            },
          },
      ],
      if (request.tools.isNotEmpty)
        'tools': [
          for (final tool in request.tools)
            {
              'type': 'function',
              'function': {
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.inputSchema,
                'strict': false,
              },
            },
        ],
      if (request.outputSchema != null)
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'result',
            'schema': request.outputSchema,
            'strict': true,
          },
        },
    });
    final configured = configure?.call(params) ?? params;
    params = api.ChatCompletionCreateRequest.fromJson(
      _preserveRequest(
        params.toJson(),
        configured.toJson(),
        owned: ['messages', 'max_completion_tokens'],
        schemaField: 'response_format',
      ),
    );

    final calls = <int, _CallBuffer>{};
    String? finishReason;
    await for (final event in client.chat.completions.createStream(
      params,
      abortTrigger: cancellation.whenCancelled,
    )) {
      cancellation.throwIfCancelled();
      final json = event.toJson();
      if (json['usage'] case final Map<String, dynamic> usage) {
        yield TokenUsage(
          inputTokens: usage['prompt_tokens'] as int,
          outputTokens: usage['completion_tokens'] as int,
          model: json['model'] as String? ?? params.model,
          cachedInputTokens:
              (usage['prompt_tokens_details'] as Map?)?['cached_tokens']
                  as int?,
          reasoningTokens:
              (usage['completion_tokens_details'] as Map?)?['reasoning_tokens']
                  as int?,
        );
      }
      for (final raw in json['choices'] as List? ?? []) {
        final choice = raw as Map;
        if (choice['index'] != 0) continue;
        final delta = choice['delta'] as Map? ?? const {};
        if (delta['content'] case final String text) yield TextDelta(text);
        if (delta['refusal'] case final String text) yield TextDelta(text);
        if (delta['reasoning_content'] case final String text) {
          yield ReasoningDelta(text);
        }
        for (final raw in delta['tool_calls'] as List? ?? []) {
          final tool = raw as Map;
          final call = calls.putIfAbsent(tool['index'] as int, _CallBuffer.new);
          if (tool['id'] case final String id) call.id = id;
          if (tool['function'] case final Map<String, dynamic> function) {
            if (function['name'] case final String name) call.name.write(name);
            if (function['arguments'] case final String arguments) {
              call.arguments.write(arguments);
            }
          }
        }
        if (choice['finish_reason'] case final String reason) {
          finishReason = reason;
        }
      }
    }
    if (finishReason == null) {
      throw StateError('OpenAI stream has no finish reason.');
    }
    for (final entry
        in calls.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      final call = entry.value;
      if (call.id == null || call.name.isEmpty) {
        throw const FormatException('Incomplete tool call.');
      }
      yield ToolCallReady(
        ToolCall(
          id: call.id!,
          name: call.name.toString(),
          arguments: Map<String, Object?>.from(
            jsonDecode(call.arguments.toString()) as Map,
          ),
        ),
      );
    }
    yield ModelFinished(finishReason);
  }
}

final class _CallBuffer {
  String? id;
  final name = StringBuffer();
  final arguments = StringBuffer();
}

// Provider options cannot silently rewrite the runtime's conversation contract.
Map<String, dynamic> _preserveRequest(
  Map<String, dynamic> canonical,
  Map<String, dynamic> configured, {
  required List<String> owned,
  required String schemaField,
}) {
  for (final key in owned) {
    if (canonical.containsKey(key) &&
        canonicalJson(canonical[key]) != canonicalJson(configured[key])) {
      throw ArgumentError(
        'configure cannot replace runtime-owned $key. Set it on AiAgent instead.',
      );
    }
  }
  final canonicalSchema = canonical[schemaField];
  final configuredSchema = configured[schemaField];
  final before = schemaField == 'text' && canonicalSchema is Map
      ? canonicalSchema['format']
      : canonicalSchema;
  final after = schemaField == 'text' && configuredSchema is Map
      ? configuredSchema['format']
      : configuredSchema;
  if (before != null && canonicalJson(before) != canonicalJson(after)) {
    throw ArgumentError('configure cannot replace the runtime output schema.');
  }
  for (final tool in canonical['tools'] as List? ?? []) {
    final matches = (configured['tools'] as List? ?? []).where(
      (candidate) => canonicalJson(candidate) == canonicalJson(tool),
    );
    if (matches.length != 1) {
      throw ArgumentError(
        'configure must preserve every runtime tool exactly once.',
      );
    }
  }
  return Map<String, dynamic>.from(configured);
}
