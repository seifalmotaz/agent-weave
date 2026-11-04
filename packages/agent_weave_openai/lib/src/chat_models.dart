import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:openai_dart/openai_dart.dart' as api;
import 'computer_tool.dart';

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
  ModelCapabilities get capabilities => ResponsesProtocolModel(
    model: model,
    transport: _transport,
    configure: configure,
  ).capabilities;

  // Typed event decoding can discard fields needed for validation and replay.
  Stream<JsonObject> _transport(
    api.CreateResponseRequest request,
    CancellationToken cancellation,
  ) => client.responses.streamSseEvents(
    endpoint: '/responses',
    body: {...request.toJson(), 'stream': true},
    abortTrigger: cancellation.whenCancelled,
  );

  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => ResponsesProtocolModel(
    model: model,
    transport: _transport,
    configure: configure,
  ).stream(request, cancellation: cancellation);
}

/// Responses request serialization and event normalization over a typed transport.
final class ResponsesProtocolModel implements ChatModel {
  final String model;
  final Stream<JsonObject> Function(
    api.CreateResponseRequest,
    CancellationToken,
  )
  transport;
  final api.CreateResponseRequest Function(api.CreateResponseRequest)?
  configure;
  final String providerDataKey;
  final String? fileIdProvider;
  final bool includeEncryptedReasoning;
  const ResponsesProtocolModel({
    required this.model,
    required this.transport,
    this.configure,
    this.providerDataKey = 'openai.responses',
    this.fileIdProvider = 'openai',
    this.includeEncryptedReasoning = true,
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
  }) => cancellation.bindStream(
    (token) => _stream(request, cancellation: token),
    isCancellationError: (error) => error is api.AbortedException,
  );

  Stream<ModelEvent> _stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    final nativeTools = request.tools.whereType<NativeModelTool>().toList();
    if (nativeTools.any(
          (tool) =>
              providerDataKey != 'openai.responses' ||
              tool.provider != 'openai.responses' ||
              tool.bindingId == null ||
              !{
                'computer',
                'computer_use_preview',
              }.contains(tool.definition['type']),
        ) ||
        nativeTools.length > 1) {
      throw UnsupportedError(
        'Unsupported native Responses tool configuration.',
      );
    }
    final nativeCalls = <String, NativeToolCall>{};
    final input = <JsonObject>[];
    for (final message in request.messages) {
      if (message.role == MessageRole.tool) {
        final call = nativeCalls[message.toolCallId];
        if (call == null) {
          input.add({
            'type': 'function_call_output',
            'call_id': message.toolCallId,
            'output': message.text,
          });
        } else {
          final original = OpenAIComputerCall.fromJson(call.arguments);
          if (call.id != original.callId) {
            throw const FormatException('Computer call ID mismatch.');
          }
          final decoded = jsonDecode(message.text);
          if (decoded is! Map || decoded['output'] is! Map) {
            throw const FormatException('Invalid computer screenshot result.');
          }
          final output = decoded['output'] as Map;
          if (output['type'] != 'computer_screenshot' ||
              output.keys.any(
                (key) =>
                    !{'type', 'image_url', 'file_id', 'detail'}.contains(key),
              )) {
            throw const FormatException('Invalid computer screenshot result.');
          }
          final screenshot = OpenAIComputerScreenshot(
            imageUrl: output['image_url'] as String?,
            fileId: output['file_id'] as String?,
            detail: output['detail'] == null
                ? null
                : api.ImageDetail.fromJson(output['detail'] as String),
          );
          final ack = decoded['acknowledged_safety_checks'];
          if (decoded.keys.any(
                (key) =>
                    !{'output', 'acknowledged_safety_checks'}.contains(key),
              ) ||
              (original.safetyChecks.isEmpty
                  ? ack != null
                  : canonicalJson(ack) !=
                        canonicalJson(original.safetyChecks))) {
            throw const FormatException(
              'Invalid computer safety acknowledgements.',
            );
          }
          input.add({
            'type': 'computer_call_output',
            'call_id': call.id,
            'output': screenshot.toJson(),
            'acknowledged_safety_checks': ?ack,
          });
        }
        continue;
      }
      for (final call in message.toolCalls.whereType<NativeToolCall>()) {
        if (call.provider != 'openai.responses' ||
            providerDataKey != 'openai.responses' ||
            nativeTools.length != 1 ||
            nativeTools.single.name != call.name ||
            nativeCalls.containsKey(call.id)) {
          throw const FormatException('Invalid native computer call history.');
        }
        nativeCalls[call.id] = call;
      }
      final replay = message.providerData[providerDataKey];
      if (replay != null && replay.isNotEmpty) {
        for (final call in message.toolCalls.whereType<NativeToolCall>()) {
          if (replay
                  .where(
                    (item) =>
                        item['type'] == 'computer_call' &&
                        canonicalJson(OpenAIComputerCall.fromJson(item).raw) ==
                            canonicalJson(call.arguments),
                  )
                  .length !=
              1) {
            throw const FormatException('Computer replay does not match call.');
          }
        }
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
                DocumentPart part => _responseDocument(part, fileIdProvider),
                FilePart(:final fileId) when fileIdProvider == 'openai' => {
                  'type': 'input_file',
                  'file_id': fileId,
                },
                FilePart() => throw ArgumentError(
                  'Legacy file handles require OpenAI.',
                ),
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
        if (call is NativeToolCall) {
          throw const FormatException(
            'Native computer call requires provider replay.',
          );
        }
        input.add({
          'type': 'function_call',
          'call_id': call.id,
          'name': call.name,
          'arguments': jsonEncode(call.arguments),
        });
      }
    }
    final replayInput = api.ResponseInput.fromOutputItems(
      List<Map<String, dynamic>>.unmodifiable(
        input.map(
          (item) => Map<String, dynamic>.unmodifiable(immutableJson(item)),
        ),
      ),
    );
    var params = api.CreateResponseRequest.fromJson({
      'model': model,
      'input': <Object?>[],
      'store': false,
      if (includeEncryptedReasoning) 'include': ['reasoning.encrypted_content'],
      'max_output_tokens': request.maxOutputTokens,
      if (request.instructions != null) 'instructions': request.instructions,
      if (request.tools.isNotEmpty)
        'tools': [
          for (final tool in request.tools)
            switch (tool) {
              NativeModelTool() => tool.definition,
              FunctionModelTool() => {
                'type': 'function',
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.inputSchema,
                'strict': false,
              },
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
    }).copyWith(input: replayInput);
    final canonical = Map<String, dynamic>.from(immutableJson(params.toJson()));
    final configured = configure?.call(params) ?? params;
    final options = _preserveRequest(
      canonical,
      configured.toJson(),
      owned: ['input', 'instructions', 'max_output_tokens', 'stream'],
      schemaField: 'text',
    );
    final configuredComputers = (options['tools'] as List? ?? [])
        .where(
          (tool) =>
              tool is Map &&
              {'computer', 'computer_use_preview'}.contains(tool['type']),
        )
        .length;
    if (configuredComputers > 1 ||
        (configuredComputers != 0 && nativeTools.isEmpty) ||
        (nativeTools.isNotEmpty && configuredComputers != 1)) {
      throw ArgumentError(
        'Exactly one registered computer profile is allowed.',
      );
    }
    final includes = <Object?>{
      ...?options['include'] as List?,
      if (includeEncryptedReasoning) 'reasoning.encrypted_content',
    };
    if (includes.isEmpty) {
      options.remove('include');
    } else {
      options['include'] = includes.toList();
    }
    params = api.CreateResponseRequest.fromJson({
      ...options,
      'input': <Object?>[],
    }).copyWith(input: replayInput);

    var terminal = false;
    final completedComputerItems = <String>{};
    String? actualModel;
    await for (final json in transport(params, cancellation)) {
      cancellation.throwIfCancelled();
      if (json['response'] case final Map<String, Object?> response) {
        if (response['model'] case final String reported) {
          actualModel = reported;
        }
      }
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
          } else if (item['type'] == 'computer_call' &&
              nativeTools.length == 1) {
            final call = OpenAIComputerCall.fromJson(
              Map<String, Object?>.from(item),
            );
            if (!completedComputerItems.add(call.callId)) {
              throw const FormatException('Duplicate computer call item.');
            }
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
          terminal = true;
          final response = json['response'] as Map;
          if (json['type'] == 'response.incomplete' &&
              (response['output'] as List? ?? []).any(
                (raw) => raw is Map && raw['type'] == 'computer_call',
              )) {
            throw StateError(
              'Incomplete response cannot execute a computer call.',
            );
          }
          if (json['type'] == 'response.completed') {
            final terminalComputerItems = <String>{};
            for (final raw in response['output'] as List? ?? []) {
              if (raw is Map &&
                  const {
                    'local_shell_call',
                    'shell_call',
                    'custom_tool_call',
                    'apply_patch_call',
                    'mcp_approval_request',
                    'tool_search_call',
                  }.contains(raw['type'])) {
                throw UnsupportedError('Unsupported native Responses call.');
              }
              if (raw is Map && raw['type'] == 'computer_call') {
                if (response['status'] != 'completed') {
                  throw const FormatException(
                    'Computer call requires a completed response.',
                  );
                }
                if (nativeTools.length != 1) {
                  throw UnsupportedError(
                    'Computer call has no registered computer tool.',
                  );
                }
                final call = OpenAIComputerCall.fromJson(
                  Map<String, Object?>.from(raw),
                );
                if (!terminalComputerItems.add(call.callId)) {
                  throw const FormatException('Duplicate computer call.');
                }
                yield NativeToolCallReady(
                  NativeToolCall(
                    id: call.callId,
                    name: nativeTools.single.name,
                    arguments: call.raw,
                    provider: 'openai.responses',
                    requiresApproval: call.safetyChecks.isNotEmpty,
                  ),
                );
              }
            }
            if (!terminalComputerItems.containsAll(completedComputerItems)) {
              throw const FormatException(
                'Computer call missing from terminal response.',
              );
            }
          }
          yield ProviderOutput(
            provider: providerDataKey,
            items: [
              for (final item in response['output'] as List? ?? [])
                Map<String, Object?>.from(item as Map),
            ],
          );
          if (response['usage'] case final Map<String, dynamic> usage) {
            yield TokenUsage(
              inputTokens: usage['input_tokens'] as int,
              outputTokens: usage['output_tokens'] as int,
              model: actualModel,
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
    if (!terminal) throw StateError('OpenAI stream has no terminal response.');
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
  ModelCapabilities get capabilities => ChatCompletionsProtocolModel(
    model: model,
    transport: _transport,
    configure: configure,
  ).capabilities;

  Stream<JsonObject> _transport(
    api.ChatCompletionCreateRequest request,
    CancellationToken cancellation,
  ) => client.chat.completions
      .createStream(request, abortTrigger: cancellation.whenCancelled)
      .map((event) => event.toJson());

  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => ChatCompletionsProtocolModel(
    model: model,
    transport: _transport,
    configure: configure,
  ).stream(request, cancellation: cancellation);
}

/// Chat Completions request serialization and event normalization.
final class ChatCompletionsProtocolModel implements ChatModel {
  final String model;
  final Stream<JsonObject> Function(
    api.ChatCompletionCreateRequest,
    CancellationToken,
  )
  transport;
  final api.ChatCompletionCreateRequest Function(
    api.ChatCompletionCreateRequest,
  )?
  configure;
  const ChatCompletionsProtocolModel({
    required this.model,
    required this.transport,
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
  }) => cancellation.bindStream(
    (token) => _stream(request, cancellation: token),
    isCancellationError: (error) => error is api.AbortedException,
  );

  Stream<ModelEvent> _stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    if (request.tools.any((tool) => tool is NativeModelTool) ||
        request.messages.any(
          (message) => message.toolCalls.any((call) => call is NativeToolCall),
        )) {
      throw UnsupportedError('Chat Completions does not support native tools.');
    }
    for (final message in request.messages) {
      if (message.role == MessageRole.assistant &&
          message.content.any((part) => part is! TextPart)) {
        throw const FormatException(
          'Chat model does not accept assistant multimedia.',
        );
      }
    }
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
              'content': message.role == MessageRole.assistant
                  ? (message.content.isEmpty ? null : message.text)
                  : [
                      for (final part in message.content)
                        switch (part) {
                          TextPart(:final text) => {
                            'type': 'text',
                            'text': text,
                          },
                          ImagePart(:final url) => {
                            'type': 'image_url',
                            'image_url': {'url': url},
                          },
                          DocumentPart() ||
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
    final canonical = Map<String, dynamic>.from(immutableJson(params.toJson()));
    final configured = configure?.call(params) ?? params;
    params = api.ChatCompletionCreateRequest.fromJson(
      _preserveRequest(
        canonical,
        configured.toJson(),
        owned: [
          'messages',
          'max_completion_tokens',
          'max_tokens',
          'stream',
          'stream_options',
        ],
        schemaField: 'response_format',
      ),
    );

    final options = params.toJson();
    if ((options['n'] != null && options['n'] != 1) ||
        (options['modalities'] as List? ?? []).contains('audio') ||
        options['audio'] != null ||
        options['functions'] != null ||
        options['function_call'] != null) {
      throw ArgumentError('Unsupported Chat Completions output mode.');
    }
    final calls = <int, _CallBuffer>{};
    String? finishReason, actualModel;
    await for (final json in transport(params, cancellation)) {
      cancellation.throwIfCancelled();
      if (json['model'] case final String reported) actualModel = reported;
      if (json['usage'] case final Map<String, dynamic> usage) {
        yield TokenUsage(
          inputTokens: usage['prompt_tokens'] as int,
          outputTokens: usage['completion_tokens'] as int,
          model: actualModel,
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
        if (delta['function_call'] != null ||
            delta['audio'] != null ||
            choice['finish_reason'] == 'function_call') {
          throw UnsupportedError('Unsupported Chat Completions output.');
        }
        if (delta['content'] case final String text) yield TextDelta(text);
        if (delta['refusal'] case final String text) yield TextDelta(text);
        if (delta['reasoning_content'] ?? delta['reasoning']
            case final String text) {
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
    if (canonicalJson(canonical[key]) != canonicalJson(configured[key])) {
      throw ArgumentError('configure cannot replace runtime-owned $key.');
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

JsonObject _responseDocument(DocumentPart part, String? fileIdProvider) => {
  'type': 'input_file',
  'filename': ?part.filename,
  ...switch (part) {
    UrlDocumentPart(:final url) => {'file_url': url},
    Base64DocumentPart(:final data, :final mimeType) => {
      'file_data': 'data:$mimeType;base64,$data',
      if (part.filename == null)
        'filename': mimeType == 'application/pdf' ? 'document.pdf' : 'document',
    },
    FileIdDocumentPart(:final fileId, :final provider)
        when fileIdProvider != null && provider == fileIdProvider =>
      {'file_id': fileId},
    FileIdDocumentPart() => throw ArgumentError(
      'The document file handle is not supported by this provider.',
    ),
  },
};
