import 'dart:async';
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:openai_dart/openai_dart.dart' as api;
import 'computer_tool.dart';
import 'hosted_tool.dart';
import 'mcp_tool.dart';
import 'mcp_output.dart';
import 'output_references.dart';
import 'platform_api.dart';

/// Caller owns [client] and closes it when the application shuts down.
final class OpenAIResponsesModel
    implements ProviderApprovalModel, ModelContinuationContract {
  final api.OpenAIClient client;
  final String model;
  final api.CreateResponseRequest Function(api.CreateResponseRequest)?
  configure;
  final JsonObject Function(JsonObject)? _nativeConfigure;
  final List<OpenAIHostedTool> hostedTools;
  final List<OpenAIMcpTool> mcpTools;

  /// A native tool-choice string or JSON object, snapshotted at construction.
  final Object? toolChoice;

  /// Stable nonsecret provider account/transport identity, required for managed tools.
  /// Change it when the account, endpoint or routing authority changes.
  final String? authorityBindingId;

  /// Frozen native request parameters, excluding runtime-owned fields and secrets.
  final JsonObject options;

  /// Frozen native decorations keyed by registered local function name.
  /// Supports strict, defer_loading, async:false and direct allowed_callers only.
  final Map<String, JsonObject> functionToolOptions;
  OpenAIResponsesModel({
    required this.client,
    required this.model,
    this.configure,
    List<OpenAIHostedTool> hostedTools = const [],
    List<OpenAIMcpTool> mcpTools = const [],
    Object? toolChoice,
    this.authorityBindingId,
    JsonObject options = const {},
    Map<String, JsonObject> functionToolOptions = const {},
  }) : functionToolOptions = _functionOptions(functionToolOptions),
       options = _responsesOptions(options),
       hostedTools = List.unmodifiable(hostedTools),
       mcpTools = List.unmodifiable(mcpTools),
       toolChoice = _responsesToolChoice(toolChoice),
       _nativeConfigure = null {
    _validateAuthority(this.hostedTools, this.mcpTools, authorityBindingId);
    if ((this.hostedTools.isNotEmpty || this.mcpTools.isNotEmpty) &&
        configure != null) {
      throw ArgumentError(
        'Provider-managed tools require immutable options instead of configure.',
      );
    }
  }

  /// Native options preserve fields not represented by the installed SDK.
  OpenAIResponsesModel.native({
    required this.client,
    required this.model,
    JsonObject Function(JsonObject)? configure,
    List<OpenAIHostedTool> hostedTools = const [],
    List<OpenAIMcpTool> mcpTools = const [],
    Object? toolChoice,
    this.authorityBindingId,
    JsonObject options = const {},
    Map<String, JsonObject> functionToolOptions = const {},
  }) : functionToolOptions = _functionOptions(functionToolOptions),
       options = _responsesOptions(options),
       hostedTools = List.unmodifiable(hostedTools),
       mcpTools = List.unmodifiable(mcpTools),
       toolChoice = _responsesToolChoice(toolChoice),
       _nativeConfigure = configure,
       configure = null {
    _validateAuthority(this.hostedTools, this.mcpTools, authorityBindingId);
    if ((this.hostedTools.isNotEmpty || this.mcpTools.isNotEmpty) &&
        configure != null) {
      throw ArgumentError(
        'Provider-managed tools require immutable options instead of configure.',
      );
    }
  }

  ResponsesProtocolModel get _delegate => ResponsesProtocolModel.native(
    model: model,
    hostedTools: hostedTools,
    mcpTools: mcpTools,
    toolChoice: toolChoice,
    authorityBindingId: authorityBindingId,
    options: options,
    functionToolOptions: functionToolOptions,
    configure:
        _nativeConfigure ??
        (configure == null
            ? null
            : (body) => _configureResponse(body, configure!)),
    transport: (body, token) => client.responses.streamSseEvents(
      endpoint: '/responses',
      body: {...body, 'stream': true},
      abortTrigger: token.whenCancelled,
    ),
  );
  @override
  JsonObject get continuationContract => _delegate.continuationContract;
  @override
  JsonObject approvalContract(ProviderApprovalCall call) =>
      _delegate.approvalContract(call);
  @override
  ModelCapabilities get capabilities => _delegate.capabilities;
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => _delegate.stream(request, cancellation: cancellation);
}

Stream<JsonObject> Function(JsonObject, CancellationToken)
_typedResponsesTransport(
  Stream<JsonObject> Function(api.CreateResponseRequest, CancellationToken)
  transport,
  bool preservesManagedTools,
) => (body, token) {
  final request = _responseRequest(body);
  if (preservesManagedTools && !jsonEquals(request.toJson(), body)) {
    throw UnsupportedError(
      'Typed transport cannot preserve these options. Use ResponsesProtocolModel.native.',
    );
  }
  return transport(request, token);
};

Map<String, JsonObject> _functionOptions(Map<String, JsonObject> value) {
  final result = <String, JsonObject>{};
  for (final entry in value.entries) {
    final options = entry.value;
    if (entry.key.trim().isEmpty ||
        options.keys.any(
          (key) => !{
            'strict',
            'defer_loading',
            'async',
            'allowed_callers',
          }.contains(key),
        ) ||
        (options['strict'] != null && options['strict'] is! bool) ||
        (options['defer_loading'] != null &&
            options['defer_loading'] is! bool) ||
        (options['async'] != null && options['async'] is! bool) ||
        (options['allowed_callers'] != null &&
            (options['allowed_callers'] is! List ||
                (options['allowed_callers'] as List).any(
                  (caller) => caller != 'direct',
                )))) {
      throw ArgumentError('Invalid function tool options.');
    }
    if (options['async'] == true) {
      throw UnsupportedError('Asynchronous function calls are not integrated.');
    }
    result[entry.key] = immutableJson(
      Map<String, Object?>.from(jsonDecode(jsonEncode(options)) as Map),
    );
  }
  return Map.unmodifiable(result);
}

Object? _responsesToolChoice(Object? value) {
  if (value == null) return null;
  if (value is! String && value is! Map<String, Object?>) {
    throw ArgumentError('toolChoice must be a string or object.');
  }
  if (value is String && !{'auto', 'none', 'required'}.contains(value) ||
      value is Map<String, Object?> &&
          (value['type'] is! String || (value['type'] as String).isEmpty)) {
    throw ArgumentError('Invalid toolChoice.');
  }
  try {
    return immutableJson({'value': jsonDecode(jsonEncode(value))})['value'];
  } catch (_) {
    throw ArgumentError('toolChoice must contain JSON values.');
  }
}

JsonObject _responsesOptions(JsonObject value) {
  const reserved = {
    'model',
    'tools',
    'tool_choice',
    'input',
    'instructions',
    'max_output_tokens',
    'stream',
    'authorization',
    'api_key',
    'headers',
    'store',
    'previous_response_id',
    'conversation',
    'background',
  };
  if (value.keys.any(reserved.contains)) {
    throw ArgumentError('Options contain runtime-owned or credential fields.');
  }
  if (value['text'] != null &&
      (value['text'] is! Map<String, Object?> ||
          (value['text'] as Map).containsKey('format'))) {
    throw ArgumentError(
      'Options text must be an object without runtime-owned format.',
    );
  }
  if (value['include'] != null &&
      (value['include'] is! List ||
          (value['include'] as List).any((entry) => entry is! String))) {
    throw ArgumentError('include must be a list of strings.');
  }
  return immutableJson(
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map),
  );
}

void _validateAuthority(
  List<OpenAIHostedTool> hosted,
  List<OpenAIMcpTool> mcp,
  String? id,
) {
  if ((hosted.isNotEmpty || mcp.isNotEmpty) &&
          (id == null || id.trim().isEmpty) ||
      (id != null && id.trim().isEmpty)) {
    throw ArgumentError(
      'Provider-managed tools require a stable authorityBindingId.',
    );
  }
}

/// Responses serialization and normalization, shared by explicit protocol adapters.
final class ResponsesProtocolModel
    implements ProviderApprovalModel, ModelContinuationContract {
  final String model;
  final Stream<JsonObject> Function(JsonObject, CancellationToken) _transport;
  final JsonObject Function(JsonObject)? _configure;
  final String providerDataKey;
  final String? fileIdProvider;
  final bool includeEncryptedReasoning;
  final List<OpenAIHostedTool> hostedTools;
  final List<OpenAIMcpTool> mcpTools;

  /// A native tool-choice string or JSON object, snapshotted at construction.
  final Object? toolChoice;

  /// Stable nonsecret provider account/transport identity, required for managed tools.
  /// Change it when the account, endpoint or routing authority changes.
  final String? authorityBindingId;

  /// Frozen native request parameters, excluding runtime-owned fields and secrets.
  final JsonObject options;

  /// Frozen native decorations keyed by registered local function name.
  /// Supports strict, defer_loading, async:false and direct allowed_callers only.
  final Map<String, JsonObject> functionToolOptions;

  ResponsesProtocolModel({
    required String model,
    required Stream<JsonObject> Function(
      api.CreateResponseRequest,
      CancellationToken,
    )
    transport,
    api.CreateResponseRequest Function(api.CreateResponseRequest)? configure,
    String providerDataKey = 'openai.responses',
    String? fileIdProvider = 'openai',
    bool includeEncryptedReasoning = true,
    List<OpenAIHostedTool> hostedTools = const [],
    List<OpenAIMcpTool> mcpTools = const [],
    Object? toolChoice,
    String? authorityBindingId,
    JsonObject options = const {},
    Map<String, JsonObject> functionToolOptions = const {},
  }) : this.native(
         model: model,
         transport: _typedResponsesTransport(
           transport,
           hostedTools.isNotEmpty || mcpTools.isNotEmpty,
         ),
         configure: configure == null
             ? null
             : (body) => _configureResponse(body, configure),
         providerDataKey: providerDataKey,
         fileIdProvider: fileIdProvider,
         includeEncryptedReasoning: includeEncryptedReasoning,
         hostedTools: hostedTools,
         mcpTools: mcpTools,
         toolChoice: toolChoice,
         authorityBindingId: authorityBindingId,
         options: options,
         functionToolOptions: functionToolOptions,
       );

  ResponsesProtocolModel.native({
    required this.model,
    required Stream<JsonObject> Function(JsonObject, CancellationToken)
    transport,
    JsonObject Function(JsonObject)? configure,
    this.providerDataKey = 'openai.responses',
    this.fileIdProvider = 'openai',
    this.includeEncryptedReasoning = true,
    List<OpenAIHostedTool> hostedTools = const [],
    List<OpenAIMcpTool> mcpTools = const [],
    Object? toolChoice,
    this.authorityBindingId,
    JsonObject options = const {},
    Map<String, JsonObject> functionToolOptions = const {},
  }) : functionToolOptions = _functionOptions(functionToolOptions),
       options = _responsesOptions(options),
       // Public parameter names are stable; transport ownership stays internal.
       // ignore: prefer_initializing_formals
       _transport = transport,
       // ignore: prefer_initializing_formals
       _configure = configure,
       hostedTools = List.unmodifiable(hostedTools),
       mcpTools = List.unmodifiable(mcpTools),
       toolChoice = _responsesToolChoice(toolChoice) {
    validateMcpTools(this.mcpTools);
    _validateAuthority(this.hostedTools, this.mcpTools, authorityBindingId);
    if ((this.hostedTools.isNotEmpty || this.mcpTools.isNotEmpty) &&
        configure != null) {
      throw ArgumentError(
        'Provider-managed tools require immutable options instead of configure.',
      );
    }
  }

  @override
  JsonObject get continuationContract => immutableJson({
    'v': 1,
    'kind': 'responses',
    'provider': providerDataKey,
    'model': model,
    'fileIdProvider': fileIdProvider,
    'includeEncryptedReasoning': includeEncryptedReasoning,
    'hostedTools': [for (final tool in hostedTools) tool.definition],
    'mcpTools': [for (final tool in mcpTools) tool.contract],
    'toolChoice': toolChoice,
    'authorityBindingId': authorityBindingId,
    'options': options,
    'functionToolOptions': functionToolOptions,
  });

  @override
  JsonObject approvalContract(ProviderApprovalCall call) {
    if (providerDataKey != 'openai.responses' ||
        call.provider != providerDataKey) {
      throw const FormatException('MCP approval provider mismatch.');
    }
    mcpToolFor(mcpTools, call.serverLabel);
    return immutableJson({
      'v': 1,
      'provider': providerDataKey,
      'mcpTools': [for (final tool in mcpTools) tool.contract],
      'hostedTools': [for (final tool in hostedTools) tool.definition],
    });
  }

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
    if (providerDataKey != 'openai.responses' &&
        (hostedTools.isNotEmpty || mcpTools.isNotEmpty)) {
      throw UnsupportedError(
        'OpenAI hosted tools require the OpenAI protocol namespace.',
      );
    }
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
    final mcpHistory = McpHistory(mcpTools, request.providerApprovalDecisions);
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
                  : !jsonEquals(ack, original.safetyChecks))) {
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
                        jsonEquals(
                          OpenAIComputerCall.fromJson(item).raw,
                          call.arguments,
                        ),
                  )
                  .length !=
              1) {
            throw const FormatException('Computer replay does not match call.');
          }
        }
        input.addAll(mcpHistory.replay(message, replay));
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
        if (call is NativeToolCall || call is ProviderApprovalCall) {
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
    mcpHistory.finish();
    final functionNames = request.tools
        .whereType<FunctionModelTool>()
        .map((tool) => tool.name)
        .toSet();
    if (functionToolOptions.keys.any((name) => !functionNames.contains(name))) {
      throw ArgumentError('Function options must name a registered function.');
    }
    final canonical = immutableJson({
      ...this.options,
      'model': model,
      'tool_choice': ?toolChoice,
      'input': input,
      'store': false,
      if (this.options['include'] != null || includeEncryptedReasoning)
        'include': {
          ...?this.options['include'] as List?,
          if (includeEncryptedReasoning) 'reasoning.encrypted_content',
        }.toList(),
      'max_output_tokens': request.maxOutputTokens,
      if (request.instructions != null) 'instructions': request.instructions,
      if (request.tools.isNotEmpty ||
          hostedTools.isNotEmpty ||
          mcpTools.isNotEmpty)
        'tools': [
          for (final tool in hostedTools) tool.definition,
          for (final tool in mcpTools) tool.definition,
          for (final tool in request.tools)
            switch (tool) {
              NativeModelTool() => tool.definition,
              FunctionModelTool() => {
                'type': 'function',
                'name': tool.name,
                'description': tool.description,
                'parameters': tool.inputSchema,
                'strict': false,
                ...?functionToolOptions[tool.name],
              },
            },
        ],
      if (request.outputSchema != null)
        'text': {
          ...?this.options['text'] as Map<String, Object?>?,
          'format': {
            'type': 'json_schema',
            'name': 'result',
            'schema': request.outputSchema,
            'strict': true,
          },
        },
    });
    final configured = _configure?.call(canonical) ?? canonical;
    final options = _preserveRequest(
      canonical,
      Map<String, dynamic>.from(configured),
      owned: [
        'input',
        'instructions',
        'max_output_tokens',
        'stream',
        'model',
        'tool_choice',
      ],
      schemaField: 'text',
      allowAdditionalTools: false,
      preserveToolOrder: true,
      immutableFunctionOptions: functionToolOptions.keys.toSet(),
      functionDecorations: const [
        'strict',
        'defer_loading',
        'async',
        'allowed_callers',
      ],
    );
    final configuredHosted = providerDataKey == 'openai.responses'
        ? _responseHostedTools(options, request.tools, mcpTools: mcpTools)
        : <OpenAIHostedTool>[];
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

    if (mcpTools.isNotEmpty) {
      final definitions = <String, JsonObject>{};
      for (final tool in mcpTools) {
        cancellation.throwIfCancelled();
        final resolved = await tool.resolveDefinition();
        cancellation.throwIfCancelled();
        definitions[tool.definition['server_label'] as String] = resolved;
      }
      options['tools'] = [
        for (final raw in options['tools'] as List)
          if ((raw as Map)['type'] == 'mcp')
            definitions[raw['server_label']]!
          else
            raw,
      ];
    }

    JsonObject? terminalResponse;
    var incomplete = false;
    final completedItems = <JsonObject>[];
    final doneCalls = <String, FunctionToolCall>{};
    final doneComputers = <String>{};
    String? actualModel;
    final streamedText = StringBuffer();
    final references = ResponsesReferences();
    final mcpOutput = McpOutput(mcpTools, request.providerApprovalDecisions);
    if (mcpTools.isNotEmpty) yield const ProviderExecutionStarting();
    cancellation.throwIfCancelled();
    await for (final json in _transport(immutableJson(options), cancellation)) {
      cancellation.throwIfCancelled();
      if (terminalResponse != null) {
        throw const FormatException('Event after Responses terminal.');
      }
      if (json['response'] case final Map<String, Object?> response) {
        if (response['model'] case final String reported) {
          actualModel = reported;
        }
      }
      if (providerDataKey == 'openai.responses') references.observe(json);
      mcpOutput.observe(json);
      switch (json['type']) {
        case 'response.output_text.delta' || 'response.refusal.delta':
          final text = json['delta'] as String;
          streamedText.write(text);
          yield TextDelta(text);
        case 'response.reasoning_summary_text.delta':
          yield ReasoningDelta(json['delta'] as String);
        case 'response.output_item.done':
          final item = immutableJson(
            Map<String, Object?>.from(json['item'] as Map),
          );
          completedItems.add(item);
          if (item['type'] == 'function_call') {
            final call = _responseFunction(item);
            if (doneCalls.containsKey(call.id)) {
              throw const FormatException('Duplicate function done item.');
            }
            doneCalls[call.id] = call;
          }
          if (item['type'] == 'computer_call') {
            if (nativeTools.length != 1) {
              throw UnsupportedError(
                'Computer call requires a registered native continuation handler.',
              );
            }
            final call = OpenAIComputerCall.fromJson(item);
            if (!doneComputers.add(call.callId)) {
              throw const FormatException('Duplicate computer done item.');
            }
          }
        case 'response.completed' || 'response.incomplete':
          terminalResponse = immutableJson(
            Map<String, Object?>.from(json['response'] as Map),
          );
          incomplete = json['type'] == 'response.incomplete';
        case 'response.failed' || 'error':
          throw StateError('OpenAI response failed.');
      }
    }
    cancellation.throwIfCancelled();
    final response = terminalResponse;
    if (response == null) {
      throw StateError('OpenAI stream has no terminal response.');
    }
    if (providerDataKey == 'openai.responses' &&
        response['status'] != null &&
        response['status'] != (incomplete ? 'incomplete' : 'completed')) {
      throw const FormatException(
        'Response status contradicts its terminal event.',
      );
    }
    final output = [
      for (final item in response['output'] as List? ?? [])
        immutableJson(Map<String, Object?>.from(item as Map)),
    ];
    if (incomplete &&
        (output.any(
              (item) => {
                'function_call',
                'computer_call',
                'mcp_approval_request',
              }.contains(item['type']),
            ) ||
            doneCalls.isNotEmpty ||
            doneComputers.isNotEmpty)) {
      throw const FormatException(
        'Incomplete response cannot execute local tools.',
      );
    }
    mcpOutput.finish(output, completed: !incomplete);
    final calls = <ToolCall>[];
    final seen = <String>{};
    final functionIds = <String>{}, computerIds = <String>{};
    final images = <({int offset, ImagePart image})>[];
    var textOffset = 0;
    for (final item in output) {
      final type = item['type'];
      if (item['id'] is String && !seen.add(item['id'] as String)) {
        throw const FormatException('Duplicate output item ID.');
      }
      if (type == 'function_call') {
        final call = _responseFunction(item);
        if (!functionIds.add(call.id)) {
          throw const FormatException('Duplicate function call ID.');
        }
        if (doneCalls[call.id] case final prior?) {
          if (prior.name != call.name ||
              !jsonEquals(prior.arguments, call.arguments)) {
            throw const FormatException(
              'Function terminal does not match done item.',
            );
          }
        }
        calls.add(call);
      } else if (type == 'computer_call') {
        if (nativeTools.length != 1) {
          throw UnsupportedError(
            'Computer call requires a registered native continuation handler.',
          );
        }
        if (response['status'] != 'completed') {
          throw const FormatException(
            'Computer call requires completed response.',
          );
        }
        final call = OpenAIComputerCall.fromJson(item);
        if (!computerIds.add(call.callId)) {
          throw const FormatException('Duplicate computer call ID.');
        }
        calls.add(
          NativeToolCall(
            id: call.callId,
            name: nativeTools.single.name,
            arguments: call.raw,
            provider: 'openai.responses',
            requiresApproval: call.safetyChecks.isNotEmpty,
          ),
        );
      } else if (type == 'mcp_approval_request') {
        calls.add(mcpOutput.approval(item));
      } else if (type == 'mcp_call' ||
          type == 'mcp_list_tools' ||
          type == 'mcp_approval_response') {
        // Validated provider execution data remains in private ordered replay.
      } else if ({
        'local_shell_call',
        'shell_call',
        'custom_tool_call',
        'apply_patch_call',
      }.contains(type)) {
        throw UnsupportedError(
          'OpenAI $type requires a separate native lifecycle handler.',
        );
      } else if (providerDataKey == 'openai.responses') {
        if (!{
          'message',
          'reasoning',
          'web_search_call',
          'file_search_call',
          'code_interpreter_call',
          'image_generation_call',
          'tool_search_call',
          'tool_search_output',
        }.contains(type)) {
          throw UnsupportedError('Unsupported Responses output item: $type');
        }
        final image = _hostedImage(item, configuredHosted);
        if (image != null) images.add((offset: textOffset, image: image));
      } else if (type == 'tool_search_call' || type == 'tool_search_output') {
        throw UnsupportedError('This provider has no tool search integration.');
      }
      if (type == 'message') textOffset += _outputText([item]).length;
    }
    if (!functionIds.containsAll(doneCalls.keys) ||
        !computerIds.containsAll(doneComputers)) {
      throw const FormatException(
        'A done call is missing from the terminal response.',
      );
    }
    for (final done in completedItems) {
      if (!{'function_call', 'computer_call'}.contains(done['type']) &&
          done['id'] is String &&
          !seen.contains(done['id'])) {
        throw const FormatException(
          'Done output item missing from terminal response.',
        );
      }
    }
    final finalText = _outputText(output);
    final outputReferences = providerDataKey == 'openai.responses'
        ? references.finish(
            output,
            streamedText: streamedText.toString(),
            finalText: finalText,
          )
        : <OutputReference>[];
    if (streamedText.isEmpty && finalText.isNotEmpty) {
      yield TextDelta(finalText);
    }
    if (images.isNotEmpty &&
        streamedText.isNotEmpty &&
        streamedText.toString() != finalText) {
      throw const FormatException('Image order requires matching final text.');
    }
    final availableText = streamedText.isEmpty
        ? finalText.length
        : streamedText.length;
    for (final media in images) {
      if (media.offset > availableText) {
        throw const FormatException(
          'Image order does not match streamed text.',
        );
      }
      yield ContentPartReady(media.image, textOffset: media.offset);
    }
    for (final reference in outputReferences) {
      yield ReferenceReady(reference);
    }
    for (final call in calls) {
      yield switch (call) {
        NativeToolCall() => NativeToolCallReady(call),
        ProviderApprovalCall() => ProviderApprovalReady(call),
        FunctionToolCall() => ToolCallReady(call),
      };
    }
    yield ProviderOutput(provider: providerDataKey, items: output);
    if (providerDataKey == 'openai.responses') {
      yield ProviderOutput(
        provider: '$providerDataKey.metadata',
        items: [
          {
            for (final entry in response.entries)
              if (entry.key != 'output')
                entry.key: entry.key == 'tools'
                    ? _withoutMcpCredentials(entry.value)
                    : entry.value,
          },
        ],
      );
    }
    if (response['usage'] case final Map<String, dynamic> usage) {
      yield TokenUsage(
        inputTokens: usage['input_tokens'] as int,
        outputTokens: usage['output_tokens'] as int,
        model: actualModel,
        cachedInputTokens:
            (usage['input_tokens_details'] as Map?)?['cached_tokens'] as int?,
        reasoningTokens:
            (usage['output_tokens_details'] as Map?)?['reasoning_tokens']
                as int?,
      );
    }
    yield ModelFinished(incomplete ? 'length' : 'stop');
  }
}

final class OpenAIChatModel implements ChatModel {
  final api.OpenAIClient client;
  final String model;
  final bool streamText;
  final api.ChatCompletionCreateRequest Function(
    api.ChatCompletionCreateRequest,
  )?
  configure;
  const OpenAIChatModel({
    required this.client,
    required this.model,
    this.configure,
    this.streamText = true,
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
  ) async* {
    var hasToolCalls = false;
    var finished = false;
    await for (final event in client.chat.completions.streamSseEvents(
      endpoint: '/chat/completions',
      body: {...request.toJson(), 'stream': true},
      abortTrigger: cancellation.whenCancelled,
    )) {
      if (event['error'] != null || event['_event'] == 'error') {
        throw StateError('OpenAI Chat stream failed.');
      }
      for (final raw in event['choices'] as List? ?? []) {
        final choice = raw as Map;
        final delta = choice['delta'];
        if (delta is Map &&
            delta['annotations'] != null &&
            (delta['annotations'] is! List ||
                (delta['annotations'] as List).isNotEmpty)) {
          throw UnsupportedError(
            'Streamed Chat annotations are not supported; use streamText: false or Responses.',
          );
        }
        if (choice['index'] != 0) continue;
        if (finished) {
          throw const FormatException('Chat choice updated after finish.');
        }
        final toolCalls = delta is Map ? delta['tool_calls'] : null;
        if (toolCalls != null && toolCalls is! List) {
          throw const FormatException('Invalid Chat tool call delta.');
        }
        if (toolCalls is List && toolCalls.isNotEmpty) hasToolCalls = true;
        final reason = choice['finish_reason'];
        if (reason != null) {
          if (!{
            'stop',
            'length',
            'tool_calls',
            'content_filter',
          }.contains(reason)) {
            throw UnsupportedError('Unsupported Chat finish reason: $reason');
          }
          if ((hasToolCalls && reason != 'tool_calls') ||
              (!hasToolCalls && reason == 'tool_calls')) {
            throw const FormatException(
              'Chat finish reason does not match tool calls.',
            );
          }
          finished = true;
        }
      }
      yield event;
    }
  }

  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) {
    if (streamText) {
      return ChatCompletionsProtocolModel(
        model: model,
        transport: _transport,
        configure: configure,
      ).stream(request, cancellation: cancellation);
    }
    return _buffered(request, cancellation);
  }

  Stream<ModelEvent> _buffered(
    ModelRequest request,
    CancellationToken cancellation,
  ) async* {
    JsonObject? rawResponse;
    var references = <OutputReference>[];
    Stream<JsonObject> transport(
      api.ChatCompletionCreateRequest params,
      CancellationToken token,
    ) async* {
      final body = params.toJson()..remove('stream_options');
      body['stream'] = false;
      final JsonObject response;
      try {
        response = await OpenAIPlatformApi(client).request(
          '/chat/completions',
          method: OpenAIHttpMethod.post,
          body: body,
          cancellation: token,
        );
      } catch (_) {
        token.throwIfCancelled();
        rethrow;
      }
      token.throwIfCancelled();
      if (response['error'] != null) {
        throw StateError('OpenAI Chat response failed.');
      }
      final choices = response['choices'];
      if (choices is! List || choices.length != 1 || choices.single is! Map) {
        throw const FormatException('Invalid Chat completion choices.');
      }
      final choice = choices.single as Map;
      if (choice['index'] != 0 || choice['message'] is! Map) {
        throw const FormatException('Invalid Chat completion message.');
      }
      final message = Map<String, Object?>.from(choice['message'] as Map);
      if (message['role'] != 'assistant') {
        throw const FormatException('Invalid Chat assistant role.');
      }
      if ((message['content'] != null && message['content'] is! String) ||
          (message['refusal'] != null && message['refusal'] is! String)) {
        throw const FormatException('Invalid Chat message text.');
      }
      if (message['audio'] != null) {
        throw UnsupportedError('Chat audio output is not supported.');
      }
      final reason = choice['finish_reason'];
      if (!{
        'stop',
        'length',
        'tool_calls',
        'content_filter',
      }.contains(reason)) {
        throw UnsupportedError('Unsupported Chat finish reason: $reason');
      }
      final toolCalls = message['tool_calls'];
      if (toolCalls != null && toolCalls is! List) {
        throw const FormatException('Invalid Chat tool calls.');
      }
      final tools = toolCalls as List? ?? const [];
      if ((tools.isNotEmpty && reason != 'tool_calls') ||
          (tools.isEmpty && reason == 'tool_calls')) {
        throw const FormatException(
          'Chat finish reason does not match tool calls.',
        );
      }
      references = chatOutputReferences(message);
      rawResponse = immutableJson(response);
      yield {
        'model': response['model'],
        if (response['usage'] != null) 'usage': response['usage'],
        'choices': [
          {
            'index': 0,
            'finish_reason': reason,
            'delta': {
              'content': message['content'],
              'refusal': message['refusal'],
              if (message['tool_calls'] != null)
                'tool_calls': [
                  for (var i = 0; i < tools.length; i++)
                    {...Map<String, Object?>.from(tools[i] as Map), 'index': i},
                ],
            },
          },
        ],
      };
    }

    await for (final event in ChatCompletionsProtocolModel(
      model: model,
      transport: transport,
      configure: configure,
    ).stream(request, cancellation: cancellation)) {
      if (event is ModelFinished) {
        for (final reference in references) {
          yield ReferenceReady(reference);
        }
        yield ProviderOutput(
          provider: 'openai.chat_completions',
          items: [rawResponse!],
        );
      }
      yield event;
    }
  }
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
    if (request.providerApprovalDecisions.isNotEmpty ||
        request.tools.any((tool) => tool is NativeModelTool) ||
        request.messages.any(
          (message) => message.toolCalls.any(
            (call) => call is NativeToolCall || call is ProviderApprovalCall,
          ),
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
  bool allowAdditionalTools = false,
  bool preserveToolOrder = false,
  Set<String> immutableFunctionOptions = const {},
  List<String> functionDecorations = const [],
}) {
  for (final key in owned) {
    if (!jsonEquals(canonical[key], configured[key])) {
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
  if (before != null && !jsonEquals(before, after)) {
    throw ArgumentError('configure cannot replace the runtime output schema.');
  }
  Object? toolValue(Object? value) {
    if (value is! Map ||
        value['type'] != 'function' ||
        immutableFunctionOptions.contains(value['name'])) {
      return value;
    }
    return Map<String, Object?>.from(value)
      ..removeWhere((key, _) => functionDecorations.contains(key));
  }

  if (!allowAdditionalTools &&
      (configured['tools'] as List? ?? []).length !=
          (canonical['tools'] as List? ?? []).length) {
    throw ArgumentError('configure cannot add unregistered tools.');
  }
  if (preserveToolOrder) {
    final before = canonical['tools'] as List? ?? [];
    final after = configured['tools'] as List? ?? [];
    if (before.length != after.length ||
        List.generate(
          before.length,
          (i) => jsonEquals(toolValue(before[i]), toolValue(after[i])),
        ).contains(false)) {
      throw ArgumentError('configure must preserve runtime tool order.');
    }
  }
  for (final tool in canonical['tools'] as List? ?? []) {
    final matches = (configured['tools'] as List? ?? []).where(
      (candidate) => jsonEquals(toolValue(candidate), toolValue(tool)),
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

api.CreateResponseRequest _responseRequest(JsonObject body) =>
    api.CreateResponseRequest.fromJson({
      ...body,
      'input': <Object?>[],
    }).copyWith(
      input: api.ResponseInput.fromOutputItems([
        for (final raw in body['input'] as List? ?? [])
          Map<String, dynamic>.unmodifiable(
            immutableJson(Map<String, Object?>.from(raw as Map)),
          ),
      ]),
    );

JsonObject _configureResponse(
  JsonObject body,
  api.CreateResponseRequest Function(api.CreateResponseRequest) configure,
) {
  final api.CreateResponseRequest typed;
  try {
    typed = _responseRequest(body);
  } on Object {
    throw UnsupportedError(
      'The pinned SDK cannot decode these options. Use OpenAIResponsesModel.native with native JSON configuration.',
    );
  }
  final before = immutableJson(typed.toJson());
  final after = immutableJson(configure(typed).toJson());
  return applyJsonChanges(body, before, after);
}

List<OpenAIHostedTool> _responseHostedTools(
  JsonObject options,
  Iterable<ModelTool> registered, {
  List<OpenAIMcpTool> mcpTools = const [],
}) {
  if (options['background'] == true ||
      options['previous_response_id'] != null ||
      options['conversation'] != null) {
    throw UnsupportedError(
      'The agent uses streamed, stateless full replay. Use SDK resource APIs for background or provider-owned conversations.',
    );
  }
  final functions = registered
      .whereType<FunctionModelTool>()
      .map((tool) => tool.name)
      .toSet();
  final hosted = <OpenAIHostedTool>[];
  final names = <String>{};
  final families = <String>{};
  final tools = options['tools'];
  if (tools != null && tools is! List) {
    throw ArgumentError('tools must be an array.');
  }
  for (final raw in tools as List? ?? []) {
    if (raw is! Map<String, Object?>) {
      throw ArgumentError('Invalid Responses tool definition.');
    }
    if (raw['type'] == 'function') {
      if (raw['name'] is! String ||
          !functions.contains(raw['name']) ||
          !names.add(raw['name'] as String)) {
        throw ArgumentError(
          'Function tools must match the registered executor exactly once.',
        );
      }
      if ((raw['async'] != null && raw['async'] is! bool) ||
          (raw['allowed_callers'] != null && raw['allowed_callers'] is! List)) {
        throw ArgumentError('Invalid function execution options.');
      }
      if (raw['async'] == true ||
          (raw['allowed_callers'] is List &&
              (raw['allowed_callers'] as List).any(
                (value) => value != 'direct',
              ))) {
        throw UnsupportedError(
          'Asynchronous and programmatic function calls need a separate continuation handler.',
        );
      }
      if (raw['strict'] != null && raw['strict'] is! bool ||
          raw['defer_loading'] != null && raw['defer_loading'] is! bool) {
        throw ArgumentError('Invalid function tool options.');
      }
    } else if (raw['type'] == 'mcp') {
      final label = raw['server_label'];
      if (label is! String ||
          !jsonEquals(mcpToolFor(mcpTools, label).definition, raw)) {
        throw ArgumentError(
          'MCP tools must match configured mcpTools exactly.',
        );
      }
    } else if (!{'computer', 'computer_use_preview'}.contains(raw['type'])) {
      final tool = OpenAIHostedTool.fromJson(raw);
      final family = tool.type.startsWith('web_search')
          ? 'web_search'
          : tool.type;
      if (!families.add(family)) {
        throw ArgumentError('Declare one hosted tool per family.');
      }
      hosted.add(tool);
    }
  }
  void choice(Object? value) {
    if (value is String && {'auto', 'none', 'required'}.contains(value)) return;
    if (value is! Map) throw ArgumentError('Invalid Responses tool choice.');
    final type = value['type'];
    if (type == 'allowed_tools') {
      if (value['tools'] is! List ||
          !{'auto', 'required'}.contains(value['mode'])) {
        throw ArgumentError('Invalid allowed tools.');
      }
      for (final tool in value['tools'] as List) {
        choice(tool);
      }
      return;
    }
    if (type == 'function' && functions.contains(value['name'])) return;
    if (type == 'mcp') {
      final label = value['server_label'];
      if (label is! String ||
          !mcpTools.any((tool) => tool.definition['server_label'] == label) ||
          (value['name'] != null &&
              (value['name'] is! String ||
                  (value['name'] as String).isEmpty))) {
        throw ArgumentError(
          'MCP tool choice requires a configured server label.',
        );
      }
      return;
    }
    if ((tools ?? []).any((tool) => (tool as Map)['type'] == type)) {
      return;
    }
    throw ArgumentError('Tool choice must reference a configured tool.');
  }

  if (options['tool_choice'] != null) choice(options['tool_choice']);
  return hosted;
}

FunctionToolCall _responseFunction(JsonObject item) {
  if (item['call_id'] is! String ||
      (item['call_id'] as String).isEmpty ||
      item['name'] is! String ||
      (item['name'] as String).isEmpty ||
      item['arguments'] is! String ||
      (item['status'] != null && item['status'] != 'completed')) {
    throw const FormatException(
      'Invalid or unfinished Responses function call.',
    );
  }
  if (item['caller'] is Map && (item['caller'] as Map)['type'] != 'direct') {
    throw UnsupportedError(
      'Programmatic function continuation is not integrated.',
    );
  }
  final arguments = jsonDecode(item['arguments'] as String);
  if (arguments is! Map<String, Object?>) {
    throw const FormatException('Function arguments must be an object.');
  }
  return FunctionToolCall(
    id: item['call_id'] as String,
    name: item['name'] as String,
    arguments: arguments,
  );
}

String _outputText(List<JsonObject> items) => [
  for (final item in items)
    if (item['type'] == 'message')
      for (final part in item['content'] as List? ?? [])
        if ((part as Map)['type'] == 'output_text')
          part['text'] as String
        else if (part['type'] == 'refusal')
          part['refusal'] as String,
].join();

ImagePart? _hostedImage(JsonObject item, List<OpenAIHostedTool> configured) {
  final type = item['type'];
  final family = switch (type) {
    'web_search_call' => 'web_search',
    'file_search_call' => 'file_search',
    'code_interpreter_call' => 'code_interpreter',
    'image_generation_call' => 'image_generation',
    'tool_search_call' || 'tool_search_output' => 'tool_search',
    _ => null,
  };
  if (family == null) return null;
  final definitions = configured.where(
    (tool) => family == 'web_search'
        ? tool.type.startsWith('web_search')
        : tool.type == family,
  );
  if (definitions.length != 1) {
    throw const FormatException('Hosted output has no configured tool.');
  }
  if (item['id'] is! String || (item['id'] as String).isEmpty) {
    throw const FormatException('Hosted output needs an ID.');
  }
  if (!{'completed', 'failed', 'incomplete'}.contains(item['status'])) {
    throw UnsupportedError('Unfinished or unknown hosted output status.');
  }
  if (family == 'tool_search' && item['execution'] != 'server') {
    throw UnsupportedError(
      'Client tool search requires an application handler.',
    );
  }
  if (type == 'image_generation_call' && item['status'] == 'completed') {
    final data = item['result'];
    if (data is! String || base64Decode(data).isEmpty) {
      throw const FormatException(
        'Completed image output has no valid base64 image.',
      );
    }
    final format =
        item['output_format'] ??
        definitions.single.definition['output_format'] ??
        'png';
    if (!{'png', 'webp', 'jpeg'}.contains(format)) {
      throw UnsupportedError('Unsupported generated image format.');
    }
    return ImagePart('data:image/$format;base64,$data');
  }
  return null;
}

// Response metadata must not reintroduce credentials stripped from tool contracts.
Object? _withoutMcpCredentials(Object? tools) => tools is List
    ? [
        for (final tool in tools)
          if (tool is Map && tool['type'] == 'mcp')
            Map<String, Object?>.from(tool)
              ..remove('authorization')
              ..remove('headers')
          else
            tool,
      ]
    : tools;
