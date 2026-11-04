import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart'
    show JsonHttpException, snapshotJson;
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as api;
import 'computer_tool.dart';
import 'citations.dart';
import 'hosted_tool.dart';
import 'mcp_tool.dart';

/// A native Messages stream. The caller owns and closes [client].
final class AnthropicChatModel implements ChatModel, ModelContinuationContract {
  final api.AnthropicClient client;
  final String model;
  final api.MessageCreateRequest Function(api.MessageCreateRequest)? configure;
  final List<String> betas;
  final String? userProfileId;
  final List<AnthropicHostedTool> hostedTools;
  final List<AnthropicMcpServer> mcpServers;
  final String? authorityBindingId;
  final JsonObject options;
  final JsonObject? toolChoice;
  final Map<String, JsonObject> functionToolOptions;
  final Object? container;
  final Map<String, List<JsonObject?>> messageDecorations;
  final JsonObject? systemCacheControl;
  final bool citations;
  AnthropicChatModel({
    required this.client,
    required this.model,
    this.configure,
    List<String> betas = const [],
    String? userProfileId,
    List<AnthropicHostedTool> hostedTools = const [],
    List<AnthropicMcpServer> mcpServers = const [],
    this.authorityBindingId,
    JsonObject options = const {},
    JsonObject? toolChoice,
    Map<String, JsonObject> functionToolOptions = const {},
    Object? container,
    Map<String, List<JsonObject?>> messageDecorations = const {},
    JsonObject? systemCacheControl,
    this.citations = false,
  }) : userProfileId =
           userProfileId ?? _defaultHeader(client, 'anthropic-user-profile-id'),
       container = _containerOption(container),
       messageDecorations = _messageDecorations(messageDecorations),
       systemCacheControl = systemCacheControl == null
           ? null
           : snapshotJson(systemCacheControl),
       hostedTools = List.unmodifiable(hostedTools),
       mcpServers = List.unmodifiable(mcpServers),
       betas = List.unmodifiable(
         mcpServers.isEmpty
             ? {..._defaultBetas(client), ...betas}
             : mergeAnthropicMcpBetas([
                 ..._defaultBetas(client),
                 ...betas,
               ], mcpServers.first.beta),
       ),
       options = _anthropicOptions(options),
       toolChoice = toolChoice == null ? null : snapshotJson(toolChoice),
       functionToolOptions = _anthropicFunctionOptions(functionToolOptions) {
    _validateManaged(
      this.hostedTools,
      this.mcpServers,
      authorityBindingId,
      configure != null,
    );
  }
  AnthropicProtocolModel get _delegate => AnthropicProtocolModel(
    model: model,
    hostedTools: hostedTools,
    mcpServers: mcpServers,
    authorityBindingId: authorityBindingId,
    options: options,
    toolChoice: toolChoice,
    functionToolOptions: functionToolOptions,
    container: container,
    messageDecorations: messageDecorations,
    systemCacheControl: systemCacheControl,
    betas: betas,
    userProfileId: userProfileId,
    citations: citations,
    configure: configure == null
        ? null
        : (body) {
            final api.MessageCreateRequest typed;
            try {
              typed = api.MessageCreateRequest.fromJson(
                Map<String, dynamic>.from(body),
              );
            } on FormatException {
              throw UnsupportedError(
                'The pinned SDK cannot decode this request for typed configuration. Use AnthropicNativeClient.chatModel with native JSON configuration.',
              );
            }
            final before = snapshotJson(typed.toJson());
            final after = snapshotJson(configure!(typed).toJson());
            return applyJsonChanges(body, before, after);
          },
    transport: (body, token) => client.messages.postStream(
      '/v1/messages',
      body: Map<String, dynamic>.from(body),
      headers: {
        if (betas.isNotEmpty) 'anthropic-beta': betas.join(','),
        'anthropic-user-profile-id': ?userProfileId,
      },
      abortTrigger: token.whenCancelled,
    ),
  );
  @override
  JsonObject get continuationContract => _delegate.continuationContract;
  @override
  ModelCapabilities get capabilities => _delegate.capabilities;
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => _delegate.stream(request, cancellation: cancellation);
}

String? _defaultHeader(api.AnthropicClient client, String key) {
  for (final entry in client.config.defaultHeaders.entries) {
    if (entry.key.toLowerCase() == key) return entry.value;
  }
  return null;
}

Object? _containerOption(Object? value) {
  if (value == null) return null;
  if (value is String) {
    if (value.trim().isEmpty) throw ArgumentError('Invalid container.');
    return value;
  }
  if (value is! Map<String, Object?> ||
      (value['id'] != null &&
          (value['id'] is! String || (value['id'] as String).trim().isEmpty)) ||
      (value['skills'] != null && value['skills'] is! List)) {
    throw ArgumentError('Invalid container.');
  }
  return snapshotJson(value);
}

Map<String, List<JsonObject?>> _messageDecorations(
  Map<String, List<JsonObject?>> value,
) => Map.unmodifiable({
  for (final entry in value.entries)
    entry.key: List<JsonObject?>.unmodifiable([
      for (final item in entry.value) item == null ? null : snapshotJson(item),
    ]),
});

List<String> _defaultBetas(api.AnthropicClient client) => [
  for (final entry in client.config.defaultHeaders.entries)
    if (entry.key.toLowerCase() == 'anthropic-beta')
      ...entry.value.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty),
];

void _validateManaged(
  List<AnthropicHostedTool> hosted,
  List<AnthropicMcpServer> servers,
  String? authority,
  bool hasConfigure,
) {
  validateAnthropicMcpServers(servers);
  if ((hosted.isNotEmpty || servers.isNotEmpty) &&
      (authority == null || authority.trim().isEmpty)) {
    throw ArgumentError(
      'Provider-managed tools require a stable authorityBindingId.',
    );
  }
  if (authority != null && authority.trim().isEmpty) {
    throw ArgumentError('Invalid authorityBindingId.');
  }
  if ((hosted.isNotEmpty || servers.isNotEmpty) && hasConfigure) {
    throw ArgumentError(
      'Provider-managed tools require immutable options instead of configure.',
    );
  }
}

JsonObject _anthropicOptions(JsonObject value) {
  const owned = {
    'model',
    'messages',
    'system',
    'max_tokens',
    'tools',
    'tool_choice',
    'mcp_servers',
    'container',
    'stream',
    'authorization',
    'api_key',
    'headers',
  };
  if (value.keys.any(owned.contains)) {
    throw ArgumentError('Options contain runtime-owned or credential fields.');
  }
  if (value['output_config'] != null &&
      (value['output_config'] is! Map ||
          (value['output_config'] as Map).containsKey('format'))) {
    throw ArgumentError('Runtime owns output format.');
  }
  return snapshotJson(value);
}

Map<String, JsonObject> _anthropicFunctionOptions(
  Map<String, JsonObject> value,
) {
  final result = <String, JsonObject>{};
  for (final entry in value.entries) {
    final o = entry.value;
    if (entry.key.trim().isEmpty ||
        o.keys.any(
          (key) => !{
            'strict',
            'defer_loading',
            'allowed_callers',
            'cache_control',
          }.contains(key),
        ) ||
        (o['strict'] != null && o['strict'] is! bool) ||
        (o['defer_loading'] != null && o['defer_loading'] is! bool) ||
        (o['allowed_callers'] != null &&
            (o['allowed_callers'] is! List ||
                (o['allowed_callers'] as List).any((v) => v is! String))) ||
        (o['cache_control'] != null && o['cache_control'] is! Map)) {
      throw ArgumentError('Invalid function tool options.');
    }
    result[entry.key] = snapshotJson(o);
  }
  return Map.unmodifiable(result);
}

/// Canonical Messages encoding and raw stream normalization, without SDK decoding.
final class AnthropicProtocolModel
    implements ChatModel, ModelContinuationContract {
  final String model;
  final JsonObject Function(JsonObject)? configure;
  final Stream<JsonObject> Function(JsonObject, CancellationToken) transport;
  final List<AnthropicHostedTool> hostedTools;
  final List<AnthropicMcpServer> mcpServers;
  final String? authorityBindingId;
  final JsonObject options;
  final JsonObject? toolChoice;
  final Map<String, JsonObject> functionToolOptions;
  final List<String> betas;
  final String? userProfileId;
  final Object? container;
  final Map<String, List<JsonObject?>> messageDecorations;
  final JsonObject? systemCacheControl;
  final bool citations;
  AnthropicProtocolModel({
    required this.model,
    required this.transport,
    this.configure,
    List<AnthropicHostedTool> hostedTools = const [],
    List<AnthropicMcpServer> mcpServers = const [],
    this.authorityBindingId,
    JsonObject options = const {},
    JsonObject? toolChoice,
    Map<String, JsonObject> functionToolOptions = const {},
    List<String> betas = const [],
    this.userProfileId,
    Object? container,
    Map<String, List<JsonObject?>> messageDecorations = const {},
    JsonObject? systemCacheControl,
    this.citations = false,
  }) : container = _containerOption(container),
       messageDecorations = _messageDecorations(messageDecorations),
       systemCacheControl = systemCacheControl == null
           ? null
           : snapshotJson(systemCacheControl),
       hostedTools = List.unmodifiable(hostedTools),
       mcpServers = List.unmodifiable(mcpServers),
       betas = List.unmodifiable(
         mcpServers.isEmpty
             ? betas
             : mergeAnthropicMcpBetas(betas, mcpServers.first.beta),
       ),
       options = _anthropicOptions(options),
       toolChoice = toolChoice == null ? null : snapshotJson(toolChoice),
       functionToolOptions = _anthropicFunctionOptions(functionToolOptions) {
    _validateManaged(
      this.hostedTools,
      this.mcpServers,
      authorityBindingId,
      configure != null,
    );
  }
  @override
  JsonObject get continuationContract => snapshotJson({
    'v': 1,
    'kind': 'anthropic.messages',
    'model': model,
    'betas': betas,
    'userProfileId': userProfileId,
    'citations': citations,
    'authorityBindingId': authorityBindingId,
    'hostedTools': [for (final tool in hostedTools) tool.definition],
    'mcpServers': [for (final server in mcpServers) server.contract],
    'options': options,
    'toolChoice': toolChoice,
    'functionToolOptions': functionToolOptions,
    'container': container,
    'messageDecorations': messageDecorations,
    'systemCacheControl': systemCacheControl,
  });
  @override
  ModelCapabilities get capabilities => ModelCapabilities(
    tools: true,
    imageInput: true,
    fileInput: true,
    structuredOutput: !citations,
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
    if (request.providerApprovalDecisions.isNotEmpty ||
        request.messages.any(
          (message) =>
              message.toolCalls.any((call) => call is ProviderApprovalCall),
        )) {
      throw UnsupportedError(
        'Provider approval history requires its native adapter.',
      );
    }
    cancellation.throwIfCancelled();
    final hosted = List<AnthropicHostedTool>.unmodifiable(hostedTools);
    final names = request.tools.map((tool) => tool.name).toSet();
    for (final tool in hosted) {
      if (!names.add(tool.name)) {
        throw ArgumentError(
          'Hosted tool names must be unique and cannot shadow local tools.',
        );
      }
    }
    final nativeTools = request.tools.whereType<NativeModelTool>().toList();
    if (nativeTools.length > 1 ||
        nativeTools.any(
          (tool) =>
              tool.provider != 'anthropic.messages' ||
              tool.definition['type'] != 'computer_toolset_20260801',
        ) ||
        (nativeTools.isNotEmpty &&
            request.tools.any(
              (tool) => tool is FunctionModelTool && tool.name == 'computer',
            ))) {
      throw UnsupportedError(
        'Unsupported Anthropic native tool configuration.',
      );
    }
    for (final tool in nativeTools) {
      validateAnthropicComputerDefinition(tool);
    }
    final nativeHistory = <String, NativeToolCall>{};
    final callOrder = <String, int>{};
    final messages = <Map<String, dynamic>>[];
    String? containerId;
    ChatMessage? lastAssistant;
    for (final message in request.messages) {
      final blocks = <Map<String, dynamic>>[];
      final replay = message.providerData['anthropic.messages'];
      if (message.role == MessageRole.assistant) {
        lastAssistant = message;
        for (final metadata
            in message.providerData['anthropic.messages.metadata'] ??
                <JsonObject>[]) {
          if (metadata['container'] != null) {
            containerId = _containerId(metadata['container']);
          }
        }
        final ids = replay == null || replay.isEmpty
            ? message.toolCalls.map((call) => call.id)
            : replay
                  .where((block) => block['type'] == 'tool_use')
                  .map((block) => block['id'] as String);
        for (final id in ids) {
          callOrder[id] = callOrder.length;
        }
      }
      for (final call in message.toolCalls.whereType<NativeToolCall>()) {
        if (call.provider != 'anthropic.messages') {
          throw UnsupportedError('Foreign native call in Anthropic history.');
        }
        if (nativeTools.length != 1 ||
            call.provider != 'anthropic.messages' ||
            call.name != nativeTools.single.name ||
            nativeHistory.containsKey(call.id)) {
          throw const FormatException('Invalid Anthropic native call history.');
        }
        final parsed = AnthropicComputerCall.fromJson(
          call.arguments,
          definition: nativeTools.single,
        );
        if (parsed.id != call.id) {
          throw const FormatException('Computer call ID mismatch.');
        }
        if (replay == null ||
            replay
                    .where(
                      (block) =>
                          block['type'] == 'tool_use' &&
                          block['toolset_name'] == 'computer' &&
                          jsonEquals(
                            AnthropicComputerCall.fromJson(
                              block,
                              definition: nativeTools.single,
                            ).raw,
                            call.arguments,
                          ),
                    )
                    .length !=
                1) {
          throw const FormatException(
            'Computer call requires exact provider replay.',
          );
        }
        nativeHistory[call.id] = call;
      }
      for (final block in replay ?? <JsonObject>[]) {
        if (block['type'] == 'tool_use' &&
            block['toolset_name'] != null &&
            (block['toolset_name'] != 'computer' ||
                !nativeHistory.containsKey(block['id']))) {
          throw const FormatException('Unmatched native tool replay.');
        }
      }
      if (message.role == MessageRole.tool) {
        final call = nativeHistory[message.toolCallId];
        blocks.add(
          call == null
              ? {
                  'type': 'tool_result',
                  'tool_use_id': message.toolCallId,
                  'content': message.text,
                }
              : {
                  'type': 'tool_result',
                  'tool_use_id': call.id,
                  'toolset_name': 'computer',
                  ..._computerResult(call, jsonDecode(message.text)),
                },
        );
      } else if (message.role == MessageRole.assistant &&
          replay != null &&
          replay.isNotEmpty) {
        blocks.addAll(replay.map(anthropicReplayBlock));
      } else {
        for (final part in message.content) {
          blocks.add(switch (part) {
            TextPart(:final text) => {'type': 'text', 'text': text},
            DocumentPart part when message.role == MessageRole.user =>
              _anthropicDocument(part, citations: citations),
            ImagePart(:final url) when message.role == MessageRole.user => {
              'type': 'image',
              'source': {'type': 'url', 'url': url},
            },
            _ => throw UnsupportedError(
              'Anthropic adapter does not support this content part.',
            ),
          });
        }
        for (final call in message.toolCalls) {
          blocks.add({
            'type': 'tool_use',
            'id': call.id,
            'name': call.name,
            'input': call.arguments,
          });
        }
      }
      final decorations = messageDecorations[message.id];
      if (decorations != null) {
        if (message.role != MessageRole.user ||
            decorations.length > blocks.length) {
          throw const FormatException('Invalid message decorations.');
        }
        for (var i = 0; i < decorations.length; i++) {
          final decoration = decorations[i];
          if (decoration == null) continue;
          final type = blocks[i]['type'];
          final allowed = type == 'document'
              ? {'cache_control', 'context', 'citations'}
              : {'cache_control'};
          if (!{'document', 'text', 'image'}.contains(type) ||
              decoration.keys.any((key) => !allowed.contains(key)) ||
              (decoration['context'] != null &&
                  decoration['context'] is! String) ||
              (decoration['cache_control'] != null &&
                  decoration['cache_control'] is! Map) ||
              (decoration['citations'] != null &&
                  decoration['citations'] is! Map)) {
            throw const FormatException('Invalid message decorations.');
          }
          blocks[i].addAll(decoration);
        }
      }
      final role = message.role == MessageRole.assistant ? 'assistant' : 'user';
      if (messages.isNotEmpty && messages.last['role'] == role) {
        (messages.last['content'] as List).addAll(blocks);
      } else {
        messages.add({'role': role, 'content': blocks});
      }
    }
    if (nativeTools.isNotEmpty) {
      for (final message in messages.where(
        (message) => message['role'] == 'user',
      )) {
        final content = message['content'] as List;
        final positions = [
          for (var i = 0; i < content.length; i++)
            if (content[i]['type'] == 'tool_result') i,
        ];
        final results = [for (final i in positions) content[i]];
        results.sort(
          (a, b) => (callOrder[a['tool_use_id']] ?? callOrder.length).compareTo(
            callOrder[b['tool_use_id']] ?? callOrder.length,
          ),
        );
        for (var i = 0; i < positions.length; i++) {
          content[positions[i]] = results[i];
        }
      }
    }
    final functionNames = request.tools
        .whereType<FunctionModelTool>()
        .map((tool) => tool.name)
        .toSet();
    if (functionToolOptions.keys.any((name) => !functionNames.contains(name))) {
      throw ArgumentError('Function options must name registered tools.');
    }
    final canonical = snapshotJson({
      ...options,
      'model': model,
      'tool_choice': ?toolChoice,
      if (mcpServers.isNotEmpty)
        'mcp_servers': [for (final server in mcpServers) server.definition],
      'max_tokens': request.maxOutputTokens,
      'messages': messages,
      'container': ?(containerId == null
          ? container
          : container is Map<String, Object?>
          ? {...container as Map<String, Object?>, 'id': containerId}
          : containerId),
      if (request.instructions != null)
        'system': systemCacheControl == null
            ? request.instructions
            : [
                {
                  'type': 'text',
                  'text': request.instructions,
                  'cache_control': systemCacheControl,
                },
              ],
      if (request.outputSchema != null)
        'output_config': {
          ...?options['output_config'] as Map<String, Object?>?,
          'format': {
            'type': 'json_schema',
            'schema': jsonDecode(jsonEncode(request.outputSchema)),
          },
        },
      if (request.tools.isNotEmpty ||
          hosted.isNotEmpty ||
          mcpServers.any((server) => server.toolsetDefinition != null))
        'tools': [
          for (final tool in hosted) tool.definition,
          for (final server in mcpServers)
            if (server.toolsetDefinition != null) server.toolsetDefinition!,
          for (final tool in request.tools)
            switch (tool) {
              NativeModelTool() => tool.definition,
              FunctionModelTool() => {
                'name': tool.name,
                'description': tool.description,
                'input_schema': jsonDecode(jsonEncode(tool.inputSchema)),
                ...?functionToolOptions[tool.name],
              },
            },
        ],
    });
    final original = canonical;
    final configured = snapshotJson(configure?.call(canonical) ?? canonical);
    for (final field in [
      'messages',
      'max_tokens',
      'system',
      'tools',
      'model',
      'tool_choice',
    ]) {
      if (!jsonEquals(
        _ownedValue(field, original[field]),
        _ownedValue(field, configured[field]),
      )) {
        throw ArgumentError('configure cannot replace runtime-owned $field.');
      }
    }
    final configuredServers = configured['mcp_servers'];
    if (mcpServers.isEmpty &&
        configuredServers != null &&
        (configuredServers is! List || configuredServers.isNotEmpty)) {
      throw UnsupportedError(
        'Anthropic MCP configuration must be explicitly registered.',
      );
    }
    if (configured['stream'] != null && configured['stream'] != true) {
      throw ArgumentError('configure cannot disable streaming.');
    }
    if (containerId != null &&
        _containerId(configured['container']) != containerId) {
      throw ArgumentError(
        'configure cannot replace the conversation container.',
      );
    }
    if (request.outputSchema != null &&
        !jsonEquals(
          (original['output_config'] as Map)['format'],
          (configured['output_config'] as Map?)?['format'],
        )) {
      throw ArgumentError(
        'configure cannot replace the runtime output schema.',
      );
    }
    final definitions = <String, JsonObject>{
      for (final raw in configured['tools'] as List? ?? const [])
        if ((raw as Map)['name'] is String)
          raw['name'] as String: Map<String, Object?>.from(raw),
    };
    if (lastAssistant != null) {
      final metadata =
          lastAssistant.providerData['anthropic.messages.metadata'];
      final reason =
          metadata?.lastOrNull?['stop_reason'] ??
          (metadata?.lastOrNull?['delta'] is Map
              ? (metadata!.last['delta'] as Map)['stop_reason']
              : null);
      if (reason == 'pause_turn' &&
          request.messages.last.role != MessageRole.assistant) {
        throw const FormatException(
          'Continue the paused assistant turn before adding messages.',
        );
      }
      if (reason == 'pause_turn' || reason == 'tool_use') {
        final previous = lastAssistant.providerData['anthropic.messages.tools'];
        if (previous != null &&
            !jsonEquals(previous, configured['tools'] ?? [])) {
          throw ArgumentError(
            'Preserve tools while continuing an unfinished hosted turn.',
          );
        }
      }
    }
    _validateDocumentCitations(configured, requireEnabled: citations);
    final pendingServer = _pendingHostedHistory(messages);
    final pendingMcp = _mcpHistory(messages, mcpServers);
    final blocks = <int, Map<String, dynamic>>{};
    final arguments = <int, StringBuffer>{};
    final reportedUsage = <String, Object?>{};
    String? actualModel, reason;
    var stopped = false;
    var started = false;
    final metadata = <String, Object?>{};
    final openBlocks = <int>{};
    final stagedCalls = <int, ToolCall>{};
    var textLength = 0;
    int? activeText;
    var lastTextIndex = -1;
    final textStarts = <int, int>{};
    final resolvedServers = <JsonObject>[];
    for (final server in mcpServers) {
      cancellation.throwIfCancelled();
      resolvedServers.add(
        await cancellation.waitFor(server.resolveDefinition()),
      );
    }
    cancellation.throwIfCancelled();
    final secrets = [
      for (final server in resolvedServers)
        if (server['authorization_token'] is String)
          server['authorization_token'] as String,
    ];
    if (mcpServers.isNotEmpty) yield const ProviderExecutionStarting();
    cancellation.throwIfCancelled();
    try {
      await for (final json in transport({
        ...configured,
        if (resolvedServers.isNotEmpty) 'mcp_servers': resolvedServers,
        'stream': true,
      }, cancellation)) {
        cancellation.throwIfCancelled();
        if (stopped) throw const FormatException('Event after message_stop.');
        switch (json['type']) {
          case 'message_start':
            if (started) {
              throw const FormatException('Duplicate message_start.');
            }
            started = true;
            final message = json['message'] as Map;
            metadata.addAll({
              for (final entry in message.entries)
                if (entry.key != 'content')
                  entry.key as String: _redactMcp(entry.value, secrets),
            });
            actualModel = _redactMcp(message['model'], secrets) as String?;
            final usage = message['usage'] as Map;
            reportedUsage.addAll(Map<String, Object?>.from(usage));
          case 'content_block_start':
            if (!started) {
              throw const FormatException('Block before message_start.');
            }
            final index = json['index'] as int;
            if (!openBlocks.add(index) || blocks.containsKey(index)) {
              throw const FormatException('Duplicate content block.');
            }
            final block = Map<String, dynamic>.from(
              json['content_block'] as Map,
            );
            if (!{
              'text',
              'thinking',
              'redacted_thinking',
              'tool_use',
              'server_tool_use',
              if (mcpServers.isNotEmpty) ...{
                'mcp_tool_use',
                'mcp_tool_result',
                'mcp_tool_listing',
              },
              'container_upload',
              ...anthropicHostedResultNames.keys,
            }.contains(block['type'])) {
              throw UnsupportedError(
                'Unsupported Anthropic content block: ${block['type']}',
              );
            }
            blocks[index] = block;
            if (block['type'] == 'text') {
              if (activeText != null || index <= lastTextIndex) {
                throw const FormatException(
                  'Interleaved or out-of-order text blocks.',
                );
              }
              activeText = index;
              lastTextIndex = index;
              textStarts[index] = textLength;
              textLength += (block['text'] as String).length;
            }
            if (block['type'] == 'text' &&
                (block['text'] as String).isNotEmpty) {
              yield TextDelta(block['text'] as String);
            }
            if (block['type'] == 'thinking' &&
                (block['thinking'] as String).isNotEmpty) {
              yield ReasoningDelta(block['thinking'] as String);
            }
          case 'content_block_delta':
            final index = json['index'] as int;
            final block = blocks[index];
            if (block == null || !openBlocks.contains(index)) {
              throw const FormatException('Delta without content block.');
            }
            final delta = json['delta'] as Map;
            switch (delta['type']) {
              case 'text_delta':
                _requireBlock(block, 'text');
                final text = delta['text'] as String;
                block['text'] = '${block['text'] ?? ''}$text';
                textLength += text.length;
                yield TextDelta(text);
              case 'thinking_delta':
                _requireBlock(block, 'thinking');
                final text = delta['thinking'] as String;
                block['thinking'] = '${block['thinking'] ?? ''}$text';
                yield ReasoningDelta(text);
              case 'signature_delta':
                _requireBlock(block, 'thinking');
                block['signature'] =
                    '${block['signature'] ?? ''}${delta['signature']}';
              case 'input_json_delta':
                if (block['type'] != 'tool_use' &&
                    block['type'] != 'server_tool_use' &&
                    block['type'] != 'mcp_tool_use') {
                  throw const FormatException(
                    'Tool delta does not match its block.',
                  );
                }
                (arguments[index] ??= StringBuffer()).write(
                  delta['partial_json'],
                );
              case 'citations_delta':
                _requireBlock(block, 'text');
                final citation = Map<String, Object?>.from(
                  delta['citation'] as Map,
                );
                block['citations'] = [
                  ...?block['citations'] as List?,
                  citation,
                ];
              default:
                throw UnsupportedError(
                  'Unsupported Anthropic content delta: ${delta['type']}',
                );
            }
          case 'content_block_stop':
            final index = json['index'] as int;
            final block = blocks[index];
            if (block == null || !openBlocks.remove(index)) {
              throw const FormatException('Stop without content block.');
            }
            if (block['type'] == 'text') {
              activeText = null;
              final rawCitations = block['citations'];
              if (rawCitations != null) {
                if (rawCitations is! List) {
                  throw const FormatException('Malformed citations.');
                }
                for (final raw in rawCitations) {
                  if (raw is! Map) {
                    throw const FormatException('Malformed citation.');
                  }
                  yield CitationReady(
                    anthropicTextCitation(
                      Map<String, Object?>.from(raw),
                      start: textStarts[index]!,
                      end: textLength,
                    ),
                  );
                }
              }
            }
            if (block['type'] == 'tool_use' ||
                block['type'] == 'server_tool_use' ||
                block['type'] == 'mcp_tool_use') {
              final partial = arguments[index]?.toString();
              if (block['type'] == 'mcp_tool_use' &&
                  (partial == null || partial.isEmpty) &&
                  !block.containsKey('input')) {
                throw const FormatException('Missing MCP tool input.');
              }
              final input = partial == null || partial.isEmpty
                  ? block['input']
                  : jsonDecode(partial);
              block['input'] = block['type'] == 'tool_use'
                  ? Map<String, dynamic>.from(input as Map)
                  : input;
            }
            if (block['type'] == 'tool_use') {
              if (block['toolset_name'] != null) {
                if (block['toolset_name'] != 'computer' ||
                    nativeTools.length != 1) {
                  throw UnsupportedError(
                    'Unregistered Anthropic native toolset.',
                  );
                }
                final call = AnthropicComputerCall.fromJson(
                  Map<String, Object?>.from(block),
                  definition: nativeTools.single,
                );
                stagedCalls[index] = NativeToolCall(
                  id: call.id,
                  name: nativeTools.single.name,
                  arguments: call.raw,
                  provider: 'anthropic.messages',
                );
              } else {
                stagedCalls[index] = ToolCall(
                  id: block['id'] as String,
                  name: block['name'] as String,
                  arguments: Map<String, Object?>.from(block['input'] as Map),
                );
              }
            }
          case 'message_delta':
            metadata['delta'] = json['delta'];
            if ((json['delta'] as Map)['container'] != null) {
              _containerId((json['delta'] as Map)['container']);
              metadata['container'] = (json['delta'] as Map)['container'];
            }
            metadata['usage'] = {
              ...?metadata['usage'] as Map?,
              ...json['usage'] as Map,
            };
            reason = (json['delta'] as Map)['stop_reason'] as String? ?? reason;
            if (reason != null) metadata['stop_reason'] = reason;
            reportedUsage.addAll({
              for (final entry in (json['usage'] as Map).entries)
                if (entry.value != null) entry.key as String: entry.value,
            });
          case 'message_stop':
            stopped = true;
          case 'error':
            throw StateError('Anthropic stream error: ${json['error']}');
        }
      }
    } catch (error) {
      cancellation.throwIfCancelled();
      if (mcpServers.isNotEmpty) {
        if (error is JsonHttpException) {
          throw JsonHttpException(
            'Anthropic MCP transport failed.',
            statusCode: error.statusCode,
            requestId: _redactMcp(error.requestId, secrets) as String?,
          );
        }
        if (error is api.ApiException) {
          final headers = error.responseMetadata?.headers;
          final requestId = headers?['request-id'] ?? headers?['x-request-id'];
          throw JsonHttpException(
            'Anthropic MCP transport failed.',
            statusCode: error.statusCode,
            requestId: _redactMcp(requestId, secrets) as String?,
          );
        }
        if (error is FormatException) {
          throw const FormatException('Invalid Anthropic MCP stream.');
        }
        if (error is UnsupportedError) {
          throw UnsupportedError('Unsupported Anthropic MCP stream.');
        }
        throw StateError('Anthropic MCP stream failed.');
      }
      rethrow;
    }
    cancellation.throwIfCancelled();
    if (!stopped ||
        reason == null ||
        openBlocks.isNotEmpty ||
        actualModel == null) {
      throw StateError(
        'Anthropic stream ended before the message was complete.',
      );
    }
    final finishReason = switch (reason) {
      'end_turn' || 'stop_sequence' => 'stop',
      'max_tokens' || 'model_context_window_exceeded' => 'length',
      'tool_use' => 'tool_calls',
      'refusal' => 'refusal',
      'pause_turn' => 'pause_turn',
      _ => throw UnsupportedError('Unsupported Anthropic stop reason: $reason'),
    };
    if (reason == 'pause_turn' && stagedCalls.isNotEmpty) {
      throw const FormatException(
        'A paused server turn cannot await local tool results.',
      );
    }
    _validateMcpBlocks(
      [for (final index in (blocks.keys.toList()..sort())) blocks[index]!],
      mcpServers,
      pendingMcp,
      reason: reason,
    );
    if (pendingMcp.pending.isNotEmpty &&
        reason != 'pause_turn' &&
        !(reason == 'tool_use' && stagedCalls.isNotEmpty)) {
      throw const FormatException('Unfinished MCP requires a continuation.');
    }
    _validateHostedBlocks(
      blocks,
      reason,
      pending: pendingServer,
      definitions: definitions,
      previousIds: {
        for (final message in request.messages)
          for (final block
              in message.providerData['anthropic.messages'] ?? <JsonObject>[])
            if (block['type'] == 'tool_use' ||
                block['type'] == 'server_tool_use')
              block['id'] as String,
      },
    );
    if (metadata['container'] != null) _containerId(metadata['container']);
    if ((reason == 'pause_turn' || reason == 'tool_use') &&
        pendingServer.values.any(
          (name) => {
            'code_execution',
            'bash_code_execution',
            'text_editor_code_execution',
          }.contains(name),
        )) {
      final id =
          _containerId(metadata['container']) ??
          containerId ??
          _containerId(configured['container']);
      if (id == null) {
        throw const FormatException(
          'Unfinished code execution requires a container ID.',
        );
      }
      metadata['container'] ??= {'id': id};
    }
    if (stagedCalls.values.any((call) => call is NativeToolCall) &&
        reason != 'tool_use') {
      throw const FormatException(
        'Computer execution requires a complete tool-use turn.',
      );
    }
    final ids = <String>{};
    final orderedCalls = stagedCalls.keys.toList()..sort();
    for (final index in orderedCalls) {
      final call = stagedCalls[index]!;
      if (!ids.add(call.id)) {
        throw const FormatException('Duplicate Anthropic tool call.');
      }
      yield switch (call) {
        NativeToolCall() => NativeToolCallReady(call),
        FunctionToolCall() => ToolCallReady(call),
        ProviderApprovalCall() => throw UnsupportedError(
          'Provider approvals require their native adapter.',
        ),
      };
    }
    final ordered = blocks.keys.toList()..sort();
    yield ProviderOutput(
      provider: 'anthropic.messages',
      items: [for (final index in ordered) blocks[index]!],
    );
    yield ProviderOutput(
      provider: 'anthropic.messages.metadata',
      items: [Map<String, Object?>.from(_redactMcp(metadata, secrets) as Map)],
    );
    if (hosted.isNotEmpty || mcpServers.isNotEmpty) {
      yield ProviderOutput(
        provider: 'anthropic.messages.tools',
        items: [
          for (final raw in configured['tools'] as List? ?? [])
            Map<String, Object?>.from(raw as Map),
        ],
      );
    }
    yield TokenUsage(
      inputTokens:
          (reportedUsage['input_tokens'] as int? ?? 0) +
          (reportedUsage['cache_read_input_tokens'] as int? ?? 0) +
          (reportedUsage['cache_creation_input_tokens'] as int? ?? 0),
      outputTokens: reportedUsage['output_tokens'] as int? ?? 0,
      model: actualModel,
      cachedInputTokens: reportedUsage['cache_read_input_tokens'] as int?,
      reasoningTokens:
          (reportedUsage['output_tokens_details'] as Map?)?['thinking_tokens']
              as int?,
    );
    yield reason == 'pause_turn'
        ? ModelFinished.continuation(finishReason)
        : ModelFinished(finishReason);
  }
}

JsonObject _computerResult(NativeToolCall call, Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Invalid computer result.');
  }
  final result = AnthropicComputerResult.fromJson(value);
  AnthropicComputerCall.fromJson(call.arguments).validateResult(result);
  return result.toJson();
}

void _requireBlock(Map<String, dynamic> block, String type) {
  if (block['type'] != type) {
    throw const FormatException('Anthropic delta does not match its block.');
  }
}

// Strip only native decorations, never keys inside user schemas or tool inputs.
Object? _ownedValue(String field, Object? value) {
  if (field == 'system' &&
      value is List &&
      value.length == 1 &&
      value[0] is Map) {
    final block = Map<String, dynamic>.from(value[0] as Map)
      ..remove('cache_control');
    if (block.length == 2 && block['type'] == 'text') return block['text'];
  }
  if (field == 'tools' && value is List) {
    return [
      for (final item in value)
        Map<String, dynamic>.from(item as Map)
          ..remove('cache_control')
          ..remove('strict')
          ..remove('allowed_callers')
          ..remove('defer_loading'),
    ];
  }
  if (field == 'messages' && value is List) {
    return [
      for (final item in value)
        () {
          final message = Map<String, dynamic>.from(item as Map);
          if (message['role'] == 'user' && message['content'] is List) {
            message['content'] = [
              for (final raw in message['content'] as List)
                () {
                  final block = Map<String, dynamic>.from(raw as Map)
                    ..remove('cache_control');
                  if (block['type'] == 'document') {
                    block.remove('citations');
                    block.remove('context');
                  }
                  return block;
                }(),
            ];
          }
          return message;
        }(),
    ];
  }
  return value;
}

Map<String, dynamic> _anthropicDocument(
  DocumentPart part, {
  required bool citations,
}) => {
  if (citations) 'citations': {'enabled': true},
  'type': 'document',
  if (part.filename != null) 'title': part.filename,
  'source': switch (part) {
    UrlDocumentPart(:final url) => {'type': 'url', 'url': url},
    Base64DocumentPart(:final data, mimeType: 'application/pdf') => {
      'type': 'base64',
      'media_type': 'application/pdf',
      'data': data,
    },
    Base64DocumentPart(:final data, mimeType: 'text/plain') => {
      'type': 'text',
      'media_type': 'text/plain',
      'data': utf8.decode(base64Decode(data)),
    },
    Base64DocumentPart() => throw UnsupportedError(
      'Anthropic inline documents support PDF or UTF-8 plain text.',
    ),
    FileIdDocumentPart(provider: 'anthropic', :final fileId) => {
      'type': 'file',
      'file_id': fileId,
    },
    FileIdDocumentPart() => throw UnsupportedError(
      'Anthropic rejects document handles from other providers.',
    ),
  },
};

String? _containerId(Object? value) {
  if (value == null) return null;
  final id = value is Map ? value['id'] : value;
  if (id is! String || id.isEmpty) {
    throw const FormatException('Invalid Anthropic container.');
  }
  return id;
}

void _validateHostedBlocks(
  Map<int, Map<String, dynamic>> blocks,
  String reason, {
  required Map<String, String> pending,
  required Map<String, JsonObject> definitions,
  required Set<String> previousIds,
}) {
  final seen = {...previousIds, ...pending.keys};
  final ordered = blocks.keys.toList()..sort();
  for (final index in ordered) {
    final block = blocks[index]!;
    switch (block['type']) {
      case 'server_tool_use':
        final id = block['id'], name = block['name'];
        if (id is! String ||
            id.isEmpty ||
            name is! String ||
            !anthropicHostedResultNames.values.any(
              (names) => names.contains(name),
            ) ||
            !seen.add(id) ||
            !block.containsKey('input')) {
          throw const FormatException('Invalid Anthropic server tool call.');
        }
        if (!_supportsHostedName(definitions, name)) {
          throw const FormatException('Unregistered Anthropic hosted tool.');
        }
        pending[id] = name;
      case 'tool_use':
        final id = block['id'];
        if (id is! String || id.isEmpty || !seen.add(id)) {
          throw const FormatException(
            'Duplicate or invalid Anthropic call ID.',
          );
        }
        final caller = block['caller'];
        if (caller != null && (caller is! Map || caller['type'] != 'direct')) {
          if (caller is! Map ||
              !{
                'code_execution_20250825',
                'code_execution_20260120',
              }.contains(caller['type']) ||
              pending[caller['tool_id']] != 'code_execution' ||
              !((definitions[block['name']]?['allowed_callers'] as List?) ??
                      const [])
                  .any(
                    (allowed) =>
                        allowed == caller['type'] ||
                        (caller['type'] == 'code_execution_20260120' &&
                            allowed == 'code_execution_20260521'),
                  )) {
            throw const FormatException(
              'Unregistered Anthropic programmatic tool caller.',
            );
          }
        }
      case 'container_upload':
        if (block['file_id'] is! String ||
            (block['file_id'] as String).isEmpty) {
          throw const FormatException('Invalid Anthropic container upload.');
        }
      default:
        final names = anthropicHostedResultNames[block['type']];
        if (names != null) {
          final id = block['tool_use_id'];
          if (id is! String ||
              !names.contains(pending[id]) ||
              !block.containsKey('content')) {
            throw const FormatException(
              'Unmatched Anthropic server tool result.',
            );
          }
          pending.remove(id);
        }
    }
  }
  if ((reason == 'end_turn' || reason == 'stop_sequence') &&
      pending.isNotEmpty) {
    throw const FormatException(
      'Completed Anthropic turn has unfinished server tools.',
    );
  }
}

bool _supportsHostedName(Map<String, JsonObject> definitions, String name) {
  if (anthropicHostedToolNames[definitions[name]?['type']] == name) return true;
  if ({
    'code_execution',
    'bash_code_execution',
    'text_editor_code_execution',
  }.contains(name)) {
    return definitions.values.any(
      (tool) =>
          anthropicHostedToolNames[tool['type']] == 'code_execution' ||
          {
            'web_search_20260209',
            'web_search_20260318',
            'web_fetch_20260209',
            'web_fetch_20260309',
            'web_fetch_20260318',
          }.contains(tool['type']),
    );
  }
  return false;
}

Map<String, String> _pendingHostedHistory(List<Map<String, dynamic>> messages) {
  final pending = <String, String>{};
  final seen = <String>{};
  Set<String>? expectedClients;
  for (final message in messages) {
    final content = message['content'] as List;
    if (message['role'] == 'user') {
      if (expectedClients != null) {
        final results = <String>{};
        for (final raw in content) {
          if (raw['type'] != 'tool_result' ||
              raw['tool_use_id'] is! String ||
              !results.add(raw['tool_use_id'] as String)) {
            throw const FormatException(
              'Deferred server tools require only client tool results.',
            );
          }
        }
        if (results.length != expectedClients.length ||
            !results.containsAll(expectedClients)) {
          throw const FormatException(
            'Deferred server tools require every client result.',
          );
        }
        expectedClients = null;
      }
      continue;
    }
    final clients = <String>{};
    for (final raw in content) {
      final block = raw as Map;
      if (block['type'] == 'server_tool_use') {
        final id = block['id'], name = block['name'];
        if (id is! String || name is! String || !seen.add(id)) {
          throw const FormatException('Invalid server tool history.');
        }
        pending[id] = name;
      } else if (anthropicHostedResultNames.containsKey(block['type'])) {
        if (!anthropicHostedResultNames[block['type']]!.contains(
          pending[block['tool_use_id']],
        )) {
          throw const FormatException('Unmatched server result history.');
        }
        pending.remove(block['tool_use_id']);
      } else if (block['type'] == 'tool_use') {
        clients.add(block['id'] as String);
      }
    }
    if (pending.isNotEmpty && clients.isNotEmpty) expectedClients = clients;
  }
  if (expectedClients != null) {
    throw const FormatException(
      'Deferred server tools are waiting on client results.',
    );
  }
  return pending;
}

void _validateDocumentCitations(
  JsonObject body, {
  required bool requireEnabled,
}) {
  final enabled = <bool>[];
  for (final raw in body['messages'] as List) {
    final message = raw as Map;
    if (message['role'] != 'user' || message['content'] is! List) continue;
    for (final rawBlock in message['content'] as List) {
      final block = rawBlock as Map;
      if (block['type'] != 'document') continue;
      final config = block['citations'];
      if (config != null &&
          (config is! Map ||
              (config.containsKey('enabled') && config['enabled'] is! bool))) {
        throw const FormatException(
          'Invalid document citations configuration.',
        );
      }
      enabled.add(config is Map && config['enabled'] == true);
    }
  }
  if ((enabled.any((e) => e) && enabled.any((e) => !e)) ||
      (requireEnabled && enabled.any((e) => !e))) {
    throw ArgumentError('Citations must be enabled on all documents or none.');
  }
  if (enabled.any((e) => e) &&
      ((body['output_config'] is Map &&
              (body['output_config'] as Map)['format'] != null) ||
          body['output_format'] != null)) {
    throw ArgumentError('Citations cannot be combined with structured output.');
  }
}

Object? _redactMcp(Object? value, List<String> secrets) {
  if (value is String) {
    return secrets.fold<String>(
      value,
      (current, secret) => current.replaceAll(secret, '[REDACTED]'),
    );
  }
  if (value is List<Object?>) {
    return [for (final item in value) _redactMcp(item, secrets)];
  }
  if (value is Map<Object?, Object?>) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = _redactMcp(entry.key as String, secrets) as String;
      if (result.containsKey(key)) {
        throw const FormatException('Conflicting metadata keys.');
      }
      result[key] = _redactMcp(entry.value, secrets);
    }
    return result;
  }
  return value;
}

final class _McpHistory {
  final Map<String, String> pending = {};
  final Set<String> seen = {};
  final Map<String, List<Object?>> listings = {};
}

_McpHistory _mcpHistory(
  List<Map<String, dynamic>> messages,
  List<AnthropicMcpServer> servers,
) {
  final state = _McpHistory();
  Set<String>? expectedClients;
  for (final message in messages) {
    final content = (message['content'] as List).cast<Map<Object?, Object?>>();
    if (message['role'] == 'user') {
      if (state.pending.isNotEmpty && expectedClients == null) {
        throw const FormatException(
          'Pending MCP must continue before new user input.',
        );
      }
      if (expectedClients != null) {
        final results = <String>{};
        for (final block in content) {
          if (block['type'] != 'tool_result' ||
              block['tool_use_id'] is! String ||
              !results.add(block['tool_use_id'] as String)) {
            throw const FormatException(
              'Deferred MCP requires client results.',
            );
          }
        }
        if (results.length != expectedClients.length ||
            !results.containsAll(expectedClients)) {
          throw const FormatException(
            'Deferred MCP requires every client result.',
          );
        }
        expectedClients = null;
      }
      continue;
    }
    _validateMcpBlocks(content, servers, state);
    final clients = <String>{
      for (final block in content)
        if (block['type'] == 'tool_use' && block['id'] is String)
          block['id'] as String,
    };
    if (state.pending.isNotEmpty && clients.isNotEmpty) {
      expectedClients = clients;
    }
  }
  if (expectedClients != null) {
    throw const FormatException('Deferred MCP is waiting on client results.');
  }
  return state;
}

bool _mcpToolAllowed(AnthropicMcpServer server, String name) {
  final legacy = server.definition['tool_configuration'];
  if (legacy is Map) {
    if (legacy['enabled'] == false) return false;
    final allowed = legacy['allowed_tools'];
    if (allowed is List && !allowed.contains(name)) return false;
  }
  final toolset = server.toolsetDefinition;
  if (toolset == null) return true;
  final pinned = toolset['tools'];
  if (pinned is List &&
      !pinned.any((tool) => tool is Map && tool['name'] == name)) {
    return false;
  }
  final defaults = toolset['default_config'];
  final configs = toolset['configs'];
  final specific = configs is Map ? configs[name] : null;
  final enabled = specific is Map && specific['enabled'] is bool
      ? specific['enabled'] as bool
      : defaults is Map && defaults['enabled'] is bool
      ? defaults['enabled'] as bool
      : true;
  return enabled;
}

void _validateMcpBlocks(
  List<Map<Object?, Object?>> blocks,
  List<AnthropicMcpServer> servers,
  _McpHistory state, {
  String? reason,
}) {
  final names = servers.map((server) => server.name).toSet();
  final listedServers = <String>{};
  for (final block in blocks) {
    switch (block['type']) {
      case 'mcp_tool_use':
        final id = block['id'],
            name = block['name'],
            server = block['server_name'];
        if (id is! String ||
            id.trim().isEmpty ||
            name is! String ||
            name.trim().isEmpty ||
            server is! String ||
            !names.contains(server) ||
            !block.containsKey('input') ||
            !state.seen.add(id)) {
          throw const FormatException('Invalid MCP tool use.');
        }
        if (reason != null &&
            !_mcpToolAllowed(
              servers.singleWhere((item) => item.name == server),
              name,
            )) {
          throw const FormatException(
            'MCP tool is not enabled by its server configuration.',
          );
        }
        try {
          jsonEncode(block['input']);
        } catch (_) {
          throw const FormatException('Invalid MCP tool input.');
        }
        state.pending[id] = server;
      case 'mcp_tool_result':
        final id = block['tool_use_id'], content = block['content'];
        if (id is! String ||
            !state.pending.containsKey(id) ||
            block['is_error'] is! bool ||
            !(content is String ||
                (content is List &&
                    content.every(
                      (item) =>
                          item is Map &&
                          item['type'] == 'text' &&
                          item['text'] is String,
                    )))) {
          throw const FormatException('Invalid MCP tool result.');
        }
        state.pending.remove(id);
      case 'mcp_tool_listing':
        final name = block['mcp_server_name'], tools = block['tools'];
        if (servers.isEmpty ||
            servers.first.beta != AnthropicMcpBeta.client20260915 ||
            name is! String ||
            !names.contains(name) ||
            !listedServers.add(name) ||
            tools is! List) {
          throw const FormatException('Invalid MCP tool listing.');
        }
        final listed = <String>{};
        for (final item in tools) {
          if (item is! Map ||
              item['name'] is! String ||
              (item['name'] as String).trim().isEmpty ||
              !listed.add(item['name'] as String) ||
              item['input_schema'] is! Map ||
              (item['description'] != null && item['description'] is! String)) {
            throw const FormatException('Invalid MCP tool descriptor.');
          }
        }
        final configured = servers
            .singleWhere((server) => server.name == name)
            .toolsetDefinition?['tools'];
        if ((configured != null && !jsonEquals(configured, tools)) ||
            (state.listings.containsKey(name) &&
                !jsonEquals(state.listings[name], tools))) {
          throw const FormatException('MCP tool listing changed.');
        }
        state.listings[name] =
            snapshotJson({'tools': tools})['tools'] as List<Object?>;
      case 'tool_use' || 'server_tool_use':
        final id = block['id'];
        if (id is! String || id.isEmpty || !state.seen.add(id)) {
          throw const FormatException('Duplicate tool ID.');
        }
    }
  }
  if ((reason == 'end_turn' || reason == 'stop_sequence') &&
      state.pending.isNotEmpty) {
    throw const FormatException(
      'Completed Anthropic turn has unfinished MCP tools.',
    );
  }
}
