import 'package:agent_weave/agent_weave.dart';

/// Reconciles native annotation events with the authoritative terminal output.
final class ResponsesReferences {
  final _events = <JsonObject>[];

  void observe(JsonObject event) {
    if ((event['type'] == 'response.output_item.added' ||
            event['type'] == 'response.output_item.done') &&
        (event['item'] is! Map ||
            (event['item'] as Map)['type'] != 'message')) {
      return;
    }
    if ({
      'response.output_text.annotation.added',
      'response.content_part.done',
      'response.content_part.added',
      'response.output_item.done',
      'response.output_item.added',
    }.contains(event['type'])) {
      _events.add(immutableJson(event));
    }
  }

  List<OutputReference> finish(
    List<JsonObject> output, {
    required String streamedText,
    required String finalText,
  }) {
    final parts =
        <
          (int, int),
          ({
            String itemId,
            String text,
            int start,
            int end,
            List<Object?> annotations,
          })
        >{};
    var offset = 0;
    for (var oi = 0; oi < output.length; oi++) {
      final item = output[oi];
      if (item['type'] != 'message') continue;
      final content = item['content'];
      if (content is! List) {
        throw const FormatException('Invalid Responses message content.');
      }
      for (var ci = 0; ci < content.length; ci++) {
        final part = content[ci];
        if (part is! Map) {
          throw const FormatException('Invalid Responses content part.');
        }
        if (part['type'] == 'refusal') {
          offset += (part['refusal'] as String).length;
        } else if (part['type'] == 'output_text') {
          final text = part['text'] as String;
          final annotations = part['annotations'];
          if (annotations != null && annotations is! List) {
            throw const FormatException('Invalid Responses annotations.');
          }
          final itemId = item['id'];
          if (itemId is! String &&
              (annotations is List && annotations.isNotEmpty)) {
            throw const FormatException('Annotated message lacks an ID.');
          }
          parts[(oi, ci)] = (
            itemId: itemId as String? ?? '',
            text: text,
            start: offset,
            end: offset + text.length,
            annotations: annotations as List? ?? const [],
          );
          offset += text.length;
        } else {
          throw UnsupportedError(
            'Unsupported Responses message content: ${part['type']}',
          );
        }
      }
    }
    final refs = <OutputReference>[];
    final canonical = <(int, int, int), JsonObject>{};
    for (final entry in parts.entries) {
      final part = entry.value;
      for (var ai = 0; ai < part.annotations.length; ai++) {
        final annotation = part.annotations[ai];
        if (annotation is! Map) {
          throw const FormatException('Incomplete Responses annotation.');
        }
        final ref = _reference(
          Map<String, Object?>.from(annotation),
          part.start,
          part.end,
        );
        refs.add(ref);
        canonical[(entry.key.$1, entry.key.$2, ai)] = ref.toJson();
      }
    }
    if (refs.isNotEmpty &&
        streamedText.isNotEmpty &&
        streamedText != finalText) {
      throw const FormatException(
        'References require matching streamed and final text.',
      );
    }
    void reconcile(int oi, int ci, int ai, Object? raw, String itemId) {
      final part = parts[(oi, ci)];
      if (part == null || part.itemId != itemId || ai < 0) {
        throw const FormatException(
          'Responses annotation does not match terminal output.',
        );
      }
      if (raw == null) return;
      if (ai >= part.annotations.length) {
        throw const FormatException(
          'Responses annotation does not match terminal output.',
        );
      }
      if (raw is! Map) {
        throw const FormatException('Invalid Responses annotation.');
      }
      final value = _reference(
        Map<String, Object?>.from(raw),
        part.start,
        part.end,
      );
      if (!jsonEquals(value.toJson(), canonical[(oi, ci, ai)])) {
        throw const FormatException('Conflicting Responses annotations.');
      }
    }

    void reconcilePart(
      int oi,
      int ci,
      String itemId,
      Object? raw, {
      bool initial = false,
    }) {
      if (raw is! Map || raw['type'] != 'output_text') return;
      final part = parts[(oi, ci)];
      if (part == null ||
          part.itemId != itemId ||
          raw['text'] is! String ||
          (initial
              ? !part.text.startsWith(raw['text'] as String)
              : raw['text'] != part.text)) {
        throw const FormatException(
          'Responses text part does not match terminal output.',
        );
      }
      final annotations = raw['annotations'];
      if (annotations == null) return;
      if (annotations is! List ||
          (initial
              ? annotations.length > part.annotations.length
              : annotations.length != part.annotations.length)) {
        throw const FormatException(
          'Responses annotations do not match terminal output.',
        );
      }
      for (var ai = 0; ai < annotations.length; ai++) {
        reconcile(oi, ci, ai, annotations[ai], itemId);
      }
    }

    for (final event in _events) {
      switch (event['type']) {
        case 'response.output_text.annotation.added':
          final oi = event['output_index'],
              ci = event['content_index'],
              ai = event['annotation_index'],
              id = event['item_id'];
          if (oi is! int ||
              oi < 0 ||
              ci is! int ||
              ci < 0 ||
              ai is! int ||
              ai < 0 ||
              id is! String ||
              !event.containsKey('annotation')) {
            throw const FormatException(
              'Invalid annotation event coordinates.',
            );
          }
          reconcile(oi, ci, ai, event['annotation'], id);
        case 'response.content_part.done' || 'response.content_part.added':
          final oi = event['output_index'],
              ci = event['content_index'],
              id = event['item_id'];
          if (oi is! int || oi < 0 || ci is! int || ci < 0 || id is! String) {
            throw const FormatException('Invalid content part coordinates.');
          }
          reconcilePart(
            oi,
            ci,
            id,
            event['part'],
            initial: event['type'] == 'response.content_part.added',
          );
        case 'response.output_item.done' || 'response.output_item.added':
          final item = event['item'];
          if (item is! Map || item['type'] != 'message') continue;
          final id = item['id'];
          if (id is! String) continue;
          final oi = event['output_index'] is int
              ? event['output_index'] as int
              : output.indexWhere((v) => v['id'] == id);
          if (oi < 0 || oi >= output.length || output[oi]['id'] != id) {
            throw const FormatException(
              'Responses item does not match terminal output.',
            );
          }
          final content = item['content'];
          if (content is! List) {
            throw const FormatException('Invalid Responses content.');
          }
          for (var ci = 0; ci < content.length; ci++) {
            reconcilePart(
              oi,
              ci,
              id,
              content[ci],
              initial: event['type'] == 'response.output_item.added',
            );
          }
      }
    }
    return refs;
  }
}

OutputReference _reference(JsonObject annotation, int start, int end) {
  try {
    final type = annotation['type'];
    final (CitationSource source, ReferencePosition position) = switch (type) {
      'file_citation' => (
        FileCitationSource(
          provider: 'openai',
          fileId: annotation['file_id'] as String,
          filename: annotation['filename'] as String,
        ),
        ProviderTextPosition(annotation['index'] as int),
      ),
      'file_path' => (
        FileCitationSource(
          provider: 'openai',
          fileId: annotation['file_id'] as String,
        ),
        FileListPosition(annotation['index'] as int),
      ),
      'container_file_citation' => (
        FileCitationSource(
          provider: 'openai',
          fileId: annotation['file_id'] as String,
          containerId: annotation['container_id'] as String,
          filename: annotation['filename'] as String,
        ),
        ProviderTextRange(
          start: annotation['start_index'] as int,
          end: annotation['end_index'] as int,
        ),
      ),
      'url_citation' => (
        UrlCitationSource(
          annotation['url'] as String,
          title: annotation['title'] as String,
        ),
        ProviderTextRange(
          start: annotation['start_index'] as int,
          end: annotation['end_index'] as int,
        ),
      ),
      _ => throw UnsupportedError('Unsupported Responses annotation: $type'),
    };
    return OutputReference(
      provider: 'openai',
      source: source,
      partStart: start,
      partEnd: end,
      position: position,
    );
  } on TypeError {
    throw const FormatException('Malformed Responses annotation.');
  }
}

/// Extract only documented Chat Completions URL annotations.
List<OutputReference> chatOutputReferences(JsonObject message) {
  final raw = message['annotations'];
  if (raw == null) return const [];
  if (raw is! List ||
      (message['content'] != null && message['content'] is! String)) {
    throw const FormatException('Invalid Chat annotations.');
  }
  final length = (message['content'] as String? ?? '').length;
  return [
    for (final item in raw)
      () {
        if (item is! Map ||
            item['type'] != 'url_citation' ||
            item['url_citation'] is! Map) {
          throw const FormatException('Unsupported Chat annotation.');
        }
        final citation = Map<String, Object?>.from(item['url_citation'] as Map);
        return _reference({...citation, 'type': 'url_citation'}, 0, length);
      }(),
  ];
}
