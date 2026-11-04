import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'model.dart';

/// A transport event. JSON is confined to the protocol boundary.
final class AgentEvent {
  final JsonObject json;
  AgentEvent(JsonObject json) : json = immutableJson(json);
  String get type => json['type'] as String;
  String toSse() => 'data: ${jsonEncode(json)}\n\n';
}

final class ResumeAnswer {
  final String interruptId;
  final Object? value;
  final bool cancelled;
  const ResumeAnswer({required this.interruptId, required this.value})
    : cancelled = false;
  const ResumeAnswer.cancelled({required this.interruptId})
    : value = null,
      cancelled = true;
  factory ResumeAnswer.fromJson(JsonObject json) => switch (json['status']) {
    'resolved' => ResumeAnswer(
      interruptId: json['interruptId'] as String,
      value: json['payload'],
    ),
    'cancelled' => ResumeAnswer.cancelled(
      interruptId: json['interruptId'] as String,
    ),
    _ => throw const FormatException(
      'Expected resolved or cancelled resume status.',
    ),
  };
}

final class ChatRequest {
  final String threadId;
  final String runId;
  final String? parentRunId;
  final List<ChatMessage> messages;
  final List<ResumeAnswer> resume;
  ChatRequest({
    required this.threadId,
    required this.runId,
    this.parentRunId,
    Iterable<ChatMessage> messages = const [],
    Iterable<ResumeAnswer> resume = const [],
  }) : messages = List.unmodifiable(messages),
       resume = List.unmodifiable(resume) {
    for (final id in [threadId, runId, ?parentRunId]) {
      if (id.isEmpty || id.length > 256) {
        throw const FormatException(
          'Identifiers must contain 1–256 characters.',
        );
      }
    }
    if (this.messages.length > 1000 || this.resume.length > 100) {
      throw const FormatException(
        'Request exceeds the message or resume limit.',
      );
    }
    final ids = this.messages.map((m) => m.id).toSet();
    if (ids.length != this.messages.length) {
      throw const FormatException('Duplicate message identifiers.');
    }
    if (this.resume.map((r) => r.interruptId).toSet().length !=
        this.resume.length) {
      throw const FormatException('Duplicate interrupt answers.');
    }
  }

  factory ChatRequest.fromJson(JsonObject json) {
    if (json['threadId'] is! String ||
        json['runId'] is! String ||
        json['messages'] is! List) {
      throw const FormatException('Expected threadId, runId, and messages.');
    }
    return ChatRequest(
      threadId: json['threadId'] as String,
      runId: json['runId'] as String,
      parentRunId: json['parentRunId'] as String?,
      messages: [
        for (final raw in json['messages'] as List)
          if (_acceptRole((raw as Map)['role']))
            _wireMessage(Map<String, Object?>.from(raw)),
      ],
      resume: [
        for (final raw in json['resume'] as List? ?? [])
          ResumeAnswer.fromJson(Map<String, Object?>.from(raw as Map)),
      ],
    );
  }
}

bool _acceptRole(Object? role) => switch (role) {
  'user' => true,
  'assistant' || 'tool' || 'reasoning' || 'activity' => false,
  _ => throw const FormatException('Unsupported message role.'),
};

ChatMessage _wireMessage(JsonObject json) {
  final role = MessageRole.values.byName(json['role'] as String);
  final parts = <ContentPart>[];
  final calls = <ToolCall>[];
  if (json['content'] case final String text) parts.add(TextPart(text));
  for (final raw
      in (json['parts'] ?? (json['content'] is List ? json['content'] : null))
              as List? ??
          []) {
    final part = Map<String, Object?>.from(raw as Map);
    switch (part['type']) {
      case 'text':
        parts.add(TextPart((part['content'] ?? part['text']) as String));
      case 'image':
        final source = part['source'];
        final url =
            part['url'] ??
            (source is Map ? (source['value'] ?? source['url']) : null);
        if (url is! String) throw const FormatException('Expected image URL.');
        parts.add(ImagePart(url));
      case 'video':
        final source = part['source'];
        final url =
            part['url'] ??
            (source is Map ? (source['value'] ?? source['url']) : null);
        if (url is! String) throw const FormatException('Expected video URL.');
        parts.add(VideoPart(url));
      case 'audio':
        final source = part['source'];
        final data =
            part['data'] ??
            (source is Map ? (source['value'] ?? source['data']) : null);
        final format =
            part['format'] ??
            (source is Map ? source['format'] : null) ??
            switch (source is Map ? source['mimeType'] : null) {
              'audio/mpeg' => 'mp3',
              'audio/wav' => 'wav',
              _ => null,
            };
        if (data is! String || format is! String) {
          throw const FormatException('Expected audio data and format.');
        }
        parts.add(AudioPart(data: data, format: format));
      case 'document':
        final source = part['source'];
        final id =
            part['fileId'] ??
            (source is Map && source['type'] == 'file'
                ? (source['value'] ?? source['fileId'])
                : null);
        if (id is String && (source is! Map || source['provider'] == null)) {
          // Preserve the existing unscoped OpenAI handle wire format.
          parts.add(FilePart(id));
        } else {
          final metadata = part['metadata'];
          parts.add(
            DocumentPart.fromJson({
              ...part,
              'filename':
                  part['filename'] ??
                  (metadata is Map ? metadata['filename'] : null),
            }),
          );
        }
      case 'tool-call':
        final args = part['input'] ?? part['arguments'] ?? part['args'] ?? '{}';
        calls.add(
          ToolCall(
            id: (part['id'] ?? part['toolCallId']) as String,
            name: (part['name'] ?? part['toolName']) as String,
            arguments: Map<String, Object?>.from(
              (args is String ? jsonDecode(args) : args) as Map,
            ),
          ),
        );
      case 'tool-result':
        // Server history owns completed tool results, never client-supplied parts.
        break;
      default:
        throw const FormatException('Unsupported message part.');
    }
  }
  return ChatMessage(
    id: json['id'] as String,
    role: role,
    content: parts,
    toolCalls: calls,
    toolCallId: json['toolCallId'] as String?,
  );
}

/// Stable schema identity used by TanStack interrupt bindings.
/// Derived from TanStack AI's MIT-licensed interrupt serialization contract.
/// Uses JavaScript number semantics; not a server-side schema equality check.
String schemaHash(JsonObject? schema) =>
    'sha256:${sha256.convert(utf8.encode(schema == null ? 'undefined' : canonicalJson(schema)))}';

String canonicalJson(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${canonicalJson(value[key])}').join(',')}}';
  }
  if (value is List<Object?>) return '[${value.map(canonicalJson).join(',')}]';
  if (value is num) {
    final number = value.toDouble();
    if (!number.isFinite) throw ArgumentError('JSON numbers must be finite.');
    if (number == 0) return '0';
    return number.toString().replaceFirst(RegExp(r'\.0(?=e|$)'), '');
  }
  return jsonEncode(value);
}

JsonObject approvalResponseSchema(JsonObject inputSchema) => {
  'oneOf': [
    {
      'type': 'object',
      'properties': {
        'approved': {'const': true},
        'editedArgs': inputSchema,
      },
      'required': ['approved'],
      'additionalProperties': false,
    },
    {
      'type': 'object',
      'properties': {
        'approved': {'const': false},
      },
      'required': ['approved'],
      'additionalProperties': false,
    },
  ],
};
