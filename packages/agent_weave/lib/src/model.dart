import 'dart:convert';
import 'cancellation.dart';

typedef JsonObject = Map<String, Object?>;

/// Snapshot JSON at public ownership boundaries, including nested collections.
JsonObject immutableJson(JsonObject value) {
  Object? freeze(Object? item) => switch (item) {
    Map<String, Object?> map => Map<String, Object?>.unmodifiable(
      map.map((key, value) => MapEntry(key, freeze(value))),
    ),
    List<Object?> list => List<Object?>.unmodifiable(list.map(freeze)),
    _ => item,
  };
  return freeze(value) as JsonObject;
}

enum MessageRole { user, assistant, tool }

sealed class ContentPart {
  const ContentPart();
  JsonObject toJson();
  factory ContentPart.fromJson(JsonObject json) => switch (json['type']) {
    'text' => TextPart(json['text'] as String),
    'image' => ImagePart(json['url'] as String),
    'file' => FilePart(json['fileId'] as String),
    'document' => DocumentPart.fromJson(json),
    'audio' => AudioPart(
      data: json['data'] as String,
      format: json['format'] as String,
    ),
    'video' => VideoPart(json['url'] as String),
    _ => throw const FormatException('Unsupported content part.'),
  };
}

final class TextPart extends ContentPart {
  final String text;
  const TextPart(this.text);
  @override
  JsonObject toJson() => {'type': 'text', 'text': text};
}

final class ImagePart extends ContentPart {
  final String url;
  const ImagePart(this.url);
  @override
  JsonObject toJson() => {'type': 'image', 'url': url};
}

final class FilePart extends ContentPart {
  final String fileId;
  const FilePart(this.fileId);
  @override
  JsonObject toJson() => {'type': 'file', 'fileId': fileId};
}

/// A document reference. File handles are scoped to the issuing provider.
sealed class DocumentPart extends ContentPart {
  final String? filename;
  DocumentPart._(this.filename) {
    if (filename != null &&
        (filename!.trim().isEmpty ||
            filename!.contains(RegExp(r'[\r\n\x00]')))) {
      throw ArgumentError(
        'A document filename must be nonempty and contain no control delimiters.',
      );
    }
  }
  factory DocumentPart.url(String url, {String? filename}) = UrlDocumentPart;
  factory DocumentPart.base64(
    String data, {
    required String mimeType,
    String? filename,
  }) = Base64DocumentPart;
  factory DocumentPart.bytes(
    List<int> bytes, {
    required String mimeType,
    String? filename,
  }) => Base64DocumentPart(
    base64Encode(bytes),
    mimeType: mimeType,
    filename: filename,
  );

  factory DocumentPart.fileId(
    String fileId, {
    required String provider,
    String? filename,
  }) = FileIdDocumentPart;

  factory DocumentPart.fromJson(JsonObject json) {
    try {
      final source = json['source'];
      if (source is! Map<String, Object?>) {
        throw const FormatException('Expected document source.');
      }
      final filename = json['filename'] as String?;
      return switch (source['type']) {
        'url' => DocumentPart.url(
          (source['value'] ?? source['url']) as String,
          filename: filename,
        ),
        'data' => DocumentPart.base64(
          (source['value'] ?? source['data']) as String,
          mimeType: source['mimeType'] as String,
          filename: filename,
        ),
        'file' => DocumentPart.fileId(
          (source['value'] ?? source['fileId']) as String,
          provider: source['provider'] as String,
          filename: filename,
        ),
        _ => throw const FormatException('Unsupported document source.'),
      };
    } on ArgumentError {
      throw const FormatException('Invalid document source.');
    } on TypeError {
      throw const FormatException('Invalid document fields.');
    }
  }

  JsonObject get sourceJson;
  @override
  JsonObject toJson() => {
    'type': 'document',
    'source': sourceJson,
    'filename': ?filename,
  };
}

final class UrlDocumentPart extends DocumentPart {
  final String url;
  UrlDocumentPart(this.url, {String? filename}) : super._(filename) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError(
        'Document URLs must be absolute HTTP(S) URLs without credentials.',
      );
    }
  }
  @override
  JsonObject get sourceJson => {'type': 'url', 'value': url};
}

final class Base64DocumentPart extends DocumentPart {
  final String data;
  final String mimeType;
  Base64DocumentPart(String data, {required String mimeType, String? filename})
    : data = _documentBase64(data),
      mimeType = mimeType.toLowerCase(),
      super._(filename) {
    if (!RegExp(
      r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$',
    ).hasMatch(this.mimeType)) {
      throw ArgumentError('Expected a document MIME type without parameters.');
    }
  }
  @override
  JsonObject get sourceJson => {
    'type': 'data',
    'value': data,
    'mimeType': mimeType,
  };
}

final class FileIdDocumentPart extends DocumentPart {
  final String fileId;
  final String provider;
  FileIdDocumentPart(this.fileId, {required this.provider, String? filename})
    : super._(filename) {
    if (fileId.trim().isEmpty || provider.trim().isEmpty) {
      throw ArgumentError(
        'A document handle requires a file ID and issuing provider.',
      );
    }
  }
  @override
  JsonObject get sourceJson => {
    'type': 'file',
    'value': fileId,
    'provider': provider,
  };
}

String _documentBase64(String source) {
  try {
    final bytes = base64Decode(source);
    if (bytes.isEmpty) throw const FormatException('Empty document.');
    return base64Encode(bytes);
  } on FormatException {
    throw ArgumentError('Expected nonempty base64 document bytes.');
  }
}

final class ToolCall {
  final String id;
  final String name;
  final JsonObject arguments;
  ToolCall({
    required this.id,
    required this.name,
    required JsonObject arguments,
  }) : arguments = immutableJson(arguments);
  JsonObject toJson() => {'id': id, 'name': name, 'arguments': arguments};
  factory ToolCall.fromJson(JsonObject json) => ToolCall(
    id: json['id'] as String,
    name: json['name'] as String,
    arguments: Map<String, Object?>.from(json['arguments'] as Map),
  );
}

final class AudioPart extends ContentPart {
  final String data;
  final String format;
  const AudioPart({required this.data, required this.format});
  @override
  JsonObject toJson() => {'type': 'audio', 'data': data, 'format': format};
}

final class VideoPart extends ContentPart {
  final String url;
  const VideoPart(this.url);
  @override
  JsonObject toJson() => {'type': 'video', 'url': url};
}

final class ChatMessage {
  final String id;
  final MessageRole role;
  final List<ContentPart> content;
  final List<ToolCall> toolCalls;
  final String? toolCallId;

  /// Provider replay state, including encrypted reasoning. Never sent to UI clients.
  final Map<String, List<JsonObject>> providerData;
  ChatMessage({
    required this.id,
    required this.role,
    Iterable<ContentPart> content = const [],
    Iterable<ToolCall> toolCalls = const [],
    this.toolCallId,
    Map<String, List<JsonObject>> providerData = const {},
  }) : content = List.unmodifiable(content),
       toolCalls = List.unmodifiable(toolCalls),
       providerData = Map.unmodifiable({
         for (final entry in providerData.entries)
           entry.key: List<JsonObject>.unmodifiable(
             entry.value.map(immutableJson),
           ),
       }) {
    if (role == MessageRole.tool &&
        (toolCallId == null || toolCallId!.isEmpty)) {
      throw ArgumentError('Tool messages require a toolCallId.');
    }
    if (role != MessageRole.tool && toolCallId != null) {
      throw ArgumentError('Only tool messages have a toolCallId.');
    }
    if (role != MessageRole.assistant && this.toolCalls.isNotEmpty) {
      throw ArgumentError('Only assistant messages can contain tool calls.');
    }
  }

  factory ChatMessage.user(String text, {required String id}) =>
      ChatMessage(id: id, role: MessageRole.user, content: [TextPart(text)]);
  String get text =>
      content.whereType<TextPart>().map((part) => part.text).join();
  JsonObject toJson() => {
    'id': id,
    'role': role.name,
    'content': [for (final part in content) part.toJson()],
    'toolCalls': [for (final call in toolCalls) call.toJson()],
    if (toolCallId != null) 'toolCallId': toolCallId,
    if (providerData.isNotEmpty) 'providerData': providerData,
  };
  factory ChatMessage.fromJson(JsonObject json) => ChatMessage(
    id: json['id'] as String,
    role: MessageRole.values.byName(json['role'] as String),
    content: [
      for (final part in json['content'] as List)
        ContentPart.fromJson(Map<String, Object?>.from(part as Map)),
    ],
    toolCalls: [
      for (final call in json['toolCalls'] as List? ?? [])
        ToolCall.fromJson(Map<String, Object?>.from(call as Map)),
    ],
    toolCallId: json['toolCallId'] as String?,
    providerData: {
      for (final entry in (json['providerData'] as Map? ?? {}).entries)
        entry.key as String: [
          for (final item in entry.value as List)
            Map<String, Object?>.from(item as Map),
        ],
    },
  );
}

final class ModelCapabilities {
  final bool tools;
  final bool structuredOutput;
  final bool imageInput;
  final bool fileInput;
  final bool audioInput;
  final bool videoInput;
  const ModelCapabilities({
    this.tools = false,
    this.structuredOutput = false,
    this.imageInput = false,
    this.fileInput = false,
    this.audioInput = false,
    this.videoInput = false,
  });
}

final class ModelTool {
  final String name;
  final String description;
  final JsonObject inputSchema;
  const ModelTool({
    required this.name,
    required this.description,
    required this.inputSchema,
  });
}

final class ModelRequest {
  final List<ChatMessage> messages;
  final List<ModelTool> tools;
  final String? instructions;
  final JsonObject? outputSchema;
  final int maxOutputTokens;
  ModelRequest({
    required Iterable<ChatMessage> messages,
    Iterable<ModelTool> tools = const [],
    this.instructions,
    JsonObject? outputSchema,
    this.maxOutputTokens = 1024,
  }) : messages = List.unmodifiable(messages),
       tools = List.unmodifiable(
         tools.map(
           (tool) => ModelTool(
             name: tool.name,
             description: tool.description,
             inputSchema: immutableJson(tool.inputSchema),
           ),
         ),
       ),
       outputSchema = outputSchema == null ? null : immutableJson(outputSchema);
}

/// Implement a single model invocation. AgentWeave owns the tool loop.
abstract interface class ChatModel {
  ModelCapabilities get capabilities;
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  });
}

sealed class ModelEvent {
  const ModelEvent();
}

final class TextDelta extends ModelEvent {
  final String text;
  const TextDelta(this.text);
}

final class ReasoningDelta extends ModelEvent {
  final String text;
  const ReasoningDelta(this.text);
}

final class ToolCallReady extends ModelEvent {
  final ToolCall call;
  const ToolCallReady(this.call);
}

final class TokenUsage extends ModelEvent {
  final int inputTokens;
  final int outputTokens;
  final String? model;
  final int? cachedInputTokens;
  final int? reasoningTokens;
  const TokenUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.model,
    this.cachedInputTokens,
    this.reasoningTokens,
  });
  JsonObject toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'totalTokens': inputTokens + outputTokens,
    'model': ?model,
    'cachedInputTokens': ?cachedInputTokens,
    'reasoningTokens': ?reasoningTokens,
  };
}

final class ModelFinished extends ModelEvent {
  final String reason;
  const ModelFinished([this.reason = 'stop']);
}

final class ProviderOutput extends ModelEvent {
  final String provider;
  final List<JsonObject> items;
  ProviderOutput({required this.provider, required Iterable<JsonObject> items})
    : items = List.unmodifiable(items.map(immutableJson));
}

/// Optional provider capabilities use their own request/result types.
abstract interface class ImageModel<Request, Result> {
  Future<Result> generate(Request request, {CancellationToken? cancellation});
}

abstract interface class SpeechModel<Request, Result> {
  Future<Result> speak(Request request, {CancellationToken? cancellation});
}

abstract interface class TranscriptionModel<Request, Result> {
  Future<Result> transcribe(Request request, {CancellationToken? cancellation});
}

abstract interface class EmbeddingModel<Request, Result> {
  Future<Result> embed(Request request, {CancellationToken? cancellation});
}

abstract interface class RealtimeModel<Session> {
  Future<Session> connect({CancellationToken? cancellation});
}

abstract interface class DecisionModel<Request, Result> {
  Future<Result> decide(Request request, {CancellationToken? cancellation});
}

abstract interface class VideoModel<Request, Job> {
  Future<Job> create(Request request, {CancellationToken? cancellation});
}
