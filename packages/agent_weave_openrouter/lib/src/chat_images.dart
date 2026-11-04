part of '../agent_weave_openrouter.dart';

// Native assistant images bypass the SDK's text-only assistant serializer.
ModelRequest _textOnlyChatRequest(ModelRequest request) => ModelRequest(
  messages: [
    for (final message in request.messages)
      if (message.role == MessageRole.assistant)
        ChatMessage(
          id: message.id,
          role: message.role,
          content: message.content.where((part) => part is! ImagePart),
          toolCalls: message.toolCalls,
          citations: message.citations,
          references: message.references,
          structuredOutput: message.structuredOutput,
          providerData: message.providerData,
        )
      else
        message,
  ],
  tools: request.tools,
  instructions: request.instructions,
  outputSchema: request.outputSchema,
  maxOutputTokens: request.maxOutputTokens,
);

void _restoreChatImages(ChatMessage message, JsonObject wire) {
  if (message.role != MessageRole.assistant) return;
  final saved = message.providerData['openrouter.chat.images'];
  if (saved != null) {
    if (saved.length != 1 ||
        saved.single.keys.any(
          (key) => !{'content', 'refusal', 'images'}.contains(key),
        ) ||
        !jsonEquals(_ChatImageOutput.decode(saved.single).contentJson, [
          for (final part in message.content) part.toJson(),
        ])) {
      throw const FormatException(
        'Image replay does not match assistant content.',
      );
    }
    wire.addAll(saved.single);
  } else if (message.content.any((part) => part is ImagePart)) {
    wire['content'] = [
      for (final part in message.content)
        switch (part) {
          TextPart(:final text) => {'type': 'text', 'text': text},
          ImagePart(:final url) => {
            'type': 'image_url',
            'image_url': {'url': _imageUrl(url)},
          },
          _ => throw UnsupportedError('Unsupported assistant image content.'),
        },
    ];
  }
}

String _imageUrl(Object? value) {
  if (value is! String || value.isEmpty) {
    throw const FormatException('Expected a generated image URL.');
  }
  final uri = Uri.tryParse(value);
  if (uri == null) throw const FormatException('Invalid generated image URL.');
  if (uri.scheme == 'data') {
    final data = uri.data;
    if (data == null ||
        !data.mimeType.toLowerCase().startsWith('image/') ||
        !data.isBase64 ||
        data.contentAsBytes().isEmpty) {
      throw const FormatException('Expected nonempty base64 image data.');
    }
  } else if (!{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw const FormatException('Expected an absolute HTTP(S) image URL.');
  }
  return value;
}

final class _ChatImageOutput {
  final String text;
  final List<({int offset, ImagePart part})> images;
  final JsonObject source;
  _ChatImageOutput(this.text, this.images, this.source);

  factory _ChatImageOutput.decode(JsonObject message) {
    final text = StringBuffer();
    final images = <({int offset, ImagePart part})>[];
    void image(Object? value) {
      if (value is! Map || value['image_url'] is! Map) {
        throw const FormatException('Invalid generated image item.');
      }
      images.add((
        offset: text.length,
        part: ImagePart(_imageUrl((value['image_url'] as Map)['url'])),
      ));
    }

    switch (message['content']) {
      case final String value:
        text.write(value);
      case final List<Object?> parts:
        for (final part in parts) {
          if (part is! Map) {
            throw const FormatException('Invalid content part.');
          }
          switch (part['type']) {
            case 'text' when part['text'] is String:
              text.write(part['text']);
            case 'image_url':
              image(part);
            default:
              throw UnsupportedError('Unsupported native assistant content.');
          }
        }
      case null:
        break;
      default:
        throw const FormatException('Invalid assistant content.');
    }
    if (message['refusal'] case final String refusal) {
      text.write(refusal);
    } else if (message['refusal'] != null) {
      throw const FormatException('Invalid assistant refusal.');
    }
    if (message.containsKey('images')) {
      final items = message['images'];
      if (items is! List) {
        throw const FormatException('Invalid assistant images.');
      }
      for (final item in items) {
        image(item);
      }
    }
    return _ChatImageOutput(
      text.toString(),
      List.unmodifiable(images),
      snapshotJson({
        for (final key in ['content', 'refusal', 'images'])
          if (message.containsKey(key)) key: message[key],
      }),
    );
  }

  List<JsonObject> get contentJson {
    final parts = <JsonObject>[];
    var cursor = 0;
    for (final image in images) {
      if (image.offset > cursor) {
        parts.add(TextPart(text.substring(cursor, image.offset)).toJson());
      }
      parts.add(image.part.toJson());
      cursor = image.offset;
    }
    if (cursor < text.length) {
      parts.add(TextPart(text.substring(cursor)).toJson());
    }
    return parts;
  }
}

/// Adapt a completed native message to the existing text/function codec.
JsonObject _bufferedImageChunk(JsonObject response, _ChatImageOutput output) {
  final choices = response['choices'];
  if (choices is! List || choices.length != 1 || choices.single is! Map) {
    throw const FormatException('Expected one completed Chat choice.');
  }
  final choice = choices.single as Map;
  final message = choice['message'];
  if (choice['index'] != 0 ||
      message is! Map<String, Object?> ||
      message['role'] != 'assistant' ||
      choice['finish_reason'] is! String) {
    throw const FormatException('Invalid completed Chat choice.');
  }
  final calls = message['tool_calls'];
  if (calls != null && calls is! List) {
    throw const FormatException('Invalid completed function calls.');
  }
  return {
    ...response,
    'choices': [
      {
        for (final entry in choice.entries)
          if (entry.key != 'message') entry.key as String: entry.value,
        'delta': {
          for (final entry in message.entries)
            if (!{
              'content',
              'images',
              'refusal',
              'tool_calls',
            }.contains(entry.key))
              entry.key: entry.value,
          'content': output.text,
          if (calls is List)
            'tool_calls': [
              for (var i = 0; i < calls.length; i++)
                if (calls[i] is Map && (calls[i] as Map)['type'] == 'function')
                  {...Map<String, Object?>.from(calls[i] as Map), 'index': i}
                else
                  throw const FormatException(
                    'Invalid completed function call.',
                  ),
            ],
        },
      },
    ],
  };
}
