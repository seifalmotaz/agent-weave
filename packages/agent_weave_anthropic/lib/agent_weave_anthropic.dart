import 'dart:convert';

export 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart';

import 'package:agent_weave/agent_weave.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as api;

/// A native Messages stream. The caller owns and closes [client].
final class AnthropicChatModel implements ChatModel {
  final api.AnthropicClient client;
  final String model;
  final api.MessageCreateRequest Function(api.MessageCreateRequest)? configure;
  final List<String> betas;
  final String? userProfileId;

  const AnthropicChatModel({
    required this.client,
    required this.model,
    this.configure,
    this.betas = const [],
    this.userProfileId,
  });

  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
    tools: true,
    imageInput: true,
    fileInput: true,
    structuredOutput: true,
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
        'Anthropic adapter does not implement native tool definitions or calls.',
      );
    }
    final messages = <Map<String, dynamic>>[];
    for (final message in request.messages) {
      final blocks = <Map<String, dynamic>>[];
      final replay = message.providerData['anthropic.messages'];
      if (message.role == MessageRole.tool) {
        blocks.add({
          'type': 'tool_result',
          'tool_use_id': message.toolCallId,
          'content': message.text,
        });
      } else if (message.role == MessageRole.assistant &&
          replay != null &&
          replay.isNotEmpty) {
        blocks.addAll(replay.map((e) => Map<String, dynamic>.from(e)));
      } else {
        for (final part in message.content) {
          blocks.add(switch (part) {
            TextPart(:final text) => {'type': 'text', 'text': text},
            DocumentPart part when message.role == MessageRole.user =>
              _anthropicDocument(part),
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
      final role = message.role == MessageRole.assistant ? 'assistant' : 'user';
      if (messages.isNotEmpty && messages.last['role'] == role) {
        (messages.last['content'] as List).addAll(blocks);
      } else {
        messages.add({'role': role, 'content': blocks});
      }
    }
    final canonical = api.MessageCreateRequest.fromJson({
      'model': model,
      'max_tokens': request.maxOutputTokens,
      'messages': messages,
      if (request.instructions != null) 'system': request.instructions,
      if (request.outputSchema != null)
        'output_config': {
          'format': {
            'type': 'json_schema',
            'schema': jsonDecode(jsonEncode(request.outputSchema)),
          },
        },
      if (request.tools.isNotEmpty)
        'tools': [
          for (final tool in request.tools)
            {
              'name': tool.name,
              'description': tool.description,
              'input_schema': jsonDecode(jsonEncode(tool.inputSchema)),
            },
        ],
    });
    final params = configure?.call(canonical) ?? canonical;
    final original = canonical.toJson();
    final configured = params.toJson();
    for (final field in ['messages', 'max_tokens', 'system', 'tools']) {
      if (canonicalJson(_ownedValue(field, original[field])) !=
          canonicalJson(_ownedValue(field, configured[field]))) {
        throw ArgumentError('configure cannot replace runtime-owned $field.');
      }
    }
    if (request.outputSchema != null &&
        canonicalJson((original['output_config'] as Map)['format']) !=
            canonicalJson((configured['output_config'] as Map?)?['format'])) {
      throw ArgumentError(
        'configure cannot replace the runtime output schema.',
      );
    }
    final blocks = <int, Map<String, dynamic>>{};
    final arguments = <int, StringBuffer>{};
    var inputTokens = 0, outputTokens = 0;
    int? cachedTokens;
    String? actualModel, reason;
    var stopped = false;
    final openBlocks = <int>{};
    try {
      await for (final event in client.messages.createStream(
        params,
        abortTrigger: cancellation.whenCancelled,
        betas: betas,
        userProfileId: userProfileId,
      )) {
        cancellation.throwIfCancelled();
        final json = event.toJson();
        if (stopped) throw const FormatException('Event after message_stop.');
        switch (json['type']) {
          case 'message_start':
            final message = json['message'] as Map;
            actualModel = message['model'] as String?;
            final usage = message['usage'] as Map;
            cachedTokens = usage['cache_read_input_tokens'] as int?;
            inputTokens =
                (usage['input_tokens'] as int? ?? 0) +
                (cachedTokens ?? 0) +
                (usage['cache_creation_input_tokens'] as int? ?? 0);
          case 'content_block_start':
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
            }.contains(block['type'])) {
              throw UnsupportedError(
                'Unsupported Anthropic content block: ${block['type']}',
              );
            }
            blocks[index] = block;
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
                final text = delta['text'] as String;
                block['text'] = '${block['text'] ?? ''}$text';
                yield TextDelta(text);
              case 'thinking_delta':
                final text = delta['thinking'] as String;
                block['thinking'] = '${block['thinking'] ?? ''}$text';
                yield ReasoningDelta(text);
              case 'signature_delta':
                block['signature'] =
                    '${block['signature'] ?? ''}${delta['signature']}';
              case 'input_json_delta':
                (arguments[index] ??= StringBuffer()).write(
                  delta['partial_json'],
                );
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
            if (block['type'] == 'tool_use') {
              final partial = arguments[index]?.toString();
              final input = partial == null || partial.isEmpty
                  ? block['input']
                  : jsonDecode(partial);
              block['input'] = Map<String, dynamic>.from(input as Map);
              yield ToolCallReady(
                ToolCall(
                  id: block['id'] as String,
                  name: block['name'] as String,
                  arguments: Map<String, Object?>.from(block['input'] as Map),
                ),
              );
            }
          case 'message_delta':
            reason = (json['delta'] as Map)['stop_reason'] as String? ?? reason;
            outputTokens =
                (json['usage'] as Map)['output_tokens'] as int? ?? outputTokens;
          case 'message_stop':
            stopped = true;
          case 'error':
            throw StateError('Anthropic stream error: ${json['error']}');
        }
      }
    } catch (_) {
      cancellation.throwIfCancelled();
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
      _ => throw UnsupportedError('Unsupported Anthropic stop reason: $reason'),
    };
    final ordered = blocks.keys.toList()..sort();
    yield ProviderOutput(
      provider: 'anthropic.messages',
      items: [for (final index in ordered) blocks[index]!],
    );
    yield TokenUsage(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      model: actualModel,
      cachedInputTokens: cachedTokens,
    );
    yield ModelFinished(finishReason);
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
          ..remove('strict'),
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
                Map<String, dynamic>.from(raw as Map)..remove('cache_control'),
            ];
          }
          return message;
        }(),
    ];
  }
  return value;
}

Map<String, dynamic> _anthropicDocument(DocumentPart part) => {
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
    FileIdDocumentPart() => throw UnsupportedError(
      'The pinned Anthropic SDK cannot represent file-ID document sources. Use a URL or inline data.',
    ),
  },
};
