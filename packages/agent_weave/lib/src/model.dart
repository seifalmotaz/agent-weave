import 'dart:convert';
import 'citations.dart';
import 'references.dart';
import 'cancellation.dart';

typedef JsonObject = Map<String, Object?>;

/// Snapshot JSON at public ownership boundaries, including nested collections.
JsonObject immutableJson(JsonObject value) {
  Object? freeze(Object? item) => switch (item) {
    Map<Object?, Object?> map => Map<String, Object?>.unmodifiable(
      map.map((key, value) {
        if (key is! String) {
          throw ArgumentError('JSON object keys must be strings.');
        }
        return MapEntry(key, freeze(value));
      }),
    ),
    List<Object?> list => List<Object?>.unmodifiable(list.map(freeze)),
    _ => item,
  };
  return freeze(value) as JsonObject;
}

/// Compare JSON values without coercing Dart integers to JavaScript doubles.
bool jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && jsonEquals(a[key], b[key]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is num && b is num && (a is int) != (b is int)) {
    final real = a is double ? a : b as double;
    return real.isFinite &&
        real == real.truncateToDouble() &&
        BigInt.from(a) == BigInt.from(b);
  }
  return a == b;
}

/// Apply changes made through a typed JSON view without dropping unknown fields.
/// Editing an array's length replaces that array; unchanged arrays retain opaque data.
JsonObject applyJsonChanges(
  JsonObject original,
  JsonObject before,
  JsonObject after,
) {
  Object? patch(Object? raw, Object? old, Object? next) {
    if (jsonEquals(old, next)) return raw;
    if (raw is Map && old is Map && next is Map) {
      return <String, Object?>{
        for (final key in {...raw.keys, ...next.keys})
          if (!(old.containsKey(key) && !next.containsKey(key)) &&
              (raw.containsKey(key) ||
                  !old.containsKey(key) ||
                  !jsonEquals(old[key], next[key])))
            key as String: old.containsKey(key) && next.containsKey(key)
                ? patch(raw[key], old[key], next[key])
                : next.containsKey(key)
                ? next[key]
                : raw[key],
      };
    }
    if (raw is List &&
        old is List &&
        next is List &&
        raw.length == old.length &&
        old.length == next.length) {
      return [
        for (var i = 0; i < raw.length; i++) patch(raw[i], old[i], next[i]),
      ];
    }
    return next;
  }

  return immutableJson(patch(original, before, after) as JsonObject);
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

sealed class ToolCall {
  final String id;
  final String name;
  final JsonObject arguments;
  ToolCall._({
    required this.id,
    required this.name,
    required JsonObject arguments,
  }) : arguments = immutableJson(arguments);
  factory ToolCall({
    required String id,
    required String name,
    required JsonObject arguments,
  }) = FunctionToolCall;
  JsonObject toJson();
  factory ToolCall.fromJson(JsonObject json) {
    final id = json['id'] as String;
    final name = json['name'] as String;
    final arguments = Map<String, Object?>.from(json['arguments'] as Map);
    return switch (json['kind']) {
      null || 'function' => ToolCall(id: id, name: name, arguments: arguments),
      'provider_approval' => ProviderApprovalCall(
        id: id,
        name: name,
        arguments: arguments,
        provider: json['provider'] as String,
        serverLabel: json['serverLabel'] as String,
        providerRequestId: json['providerRequestId'] as String,
      ),
      'native' => NativeToolCall(
        id: id,
        name: name,
        arguments: arguments,
        provider: json['provider'] as String,
        requiresApproval: json['requiresApproval'] as bool,
      ),
      _ => throw const FormatException('Unsupported tool call kind.'),
    };
  }
}

final class FunctionToolCall extends ToolCall {
  FunctionToolCall({
    required super.id,
    required super.name,
    required super.arguments,
  }) : super._();
  @override
  JsonObject toJson() => {'id': id, 'name': name, 'arguments': arguments};
}

final class NativeToolCall extends ToolCall {
  final String provider;
  final bool requiresApproval;
  NativeToolCall({
    required super.id,
    required super.name,
    required super.arguments,
    required this.provider,
    this.requiresApproval = false,
  }) : super._();
  @override
  JsonObject toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
    'kind': 'native',
    'provider': provider,
    'requiresApproval': requiresApproval,
  };
}

/// A provider-owned approval, never a locally executable tool.
final class ProviderApprovalCall extends ToolCall {
  final String provider;
  final String serverLabel;

  /// Backend-only provider identifier. Do not include in UI projections.
  final String providerRequestId;
  ProviderApprovalCall({
    required super.id,
    required super.name,
    required super.arguments,
    required this.provider,
    required this.serverLabel,
    required this.providerRequestId,
  }) : super._() {
    if ([
      id,
      name,
      provider,
      serverLabel,
      providerRequestId,
    ].any((v) => v.trim().isEmpty)) {
      throw const FormatException('Invalid provider approval.');
    }
  }
  @override
  JsonObject toJson() => {
    'kind': 'provider_approval',
    'id': id,
    'name': name,
    'arguments': arguments,
    'provider': provider,
    'serverLabel': serverLabel,
    'providerRequestId': providerRequestId,
  };
}

/// Private decision for provider continuation and ordered replay.
final class ProviderApprovalDecision {
  final String provider;
  final String providerRequestId;
  final bool approved;
  final String? reason;
  const ProviderApprovalDecision({
    required this.provider,
    required this.providerRequestId,
    required this.approved,
    this.reason,
  });
  JsonObject toJson() => {
    'provider': provider,
    'providerRequestId': providerRequestId,
    'approved': approved,
    'reason': ?reason,
  };
  factory ProviderApprovalDecision.fromJson(JsonObject json) =>
      ProviderApprovalDecision(
        provider: json['provider'] as String,
        providerRequestId: json['providerRequestId'] as String,
        approved: json['approved'] as bool,
        reason: json['reason'] as String?,
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

/// Structured output parsed from its original model JSON.
final class StructuredMessageOutput {
  final Object? data;
  final String raw;
  StructuredMessageOutput(this.raw)
    : data = immutableJson({'data': jsonDecode(raw)})['data'];
  JsonObject toJson() => {'raw': raw};
  factory StructuredMessageOutput.fromJson(JsonObject json) {
    if (json['raw'] is! String) {
      throw const FormatException('Invalid structured message output.');
    }
    return StructuredMessageOutput(json['raw'] as String);
  }
}

final class ChatMessage {
  final String id;
  final MessageRole role;
  final List<ContentPart> content;
  final List<ToolCall> toolCalls;
  final String? toolCallId;

  /// Citations into the flattened assistant [text], in UTF-16 code units.
  final List<TextCitation> citations;

  /// Provider output references associated with enclosing text segments.
  final List<OutputReference> references;
  final StructuredMessageOutput? structuredOutput;

  /// Provider replay state, including encrypted reasoning. Never sent to UI clients.
  final Map<String, List<JsonObject>> providerData;
  ChatMessage({
    required this.id,
    required this.role,
    Iterable<ContentPart> content = const [],
    Iterable<ToolCall> toolCalls = const [],
    this.toolCallId,
    Iterable<TextCitation> citations = const [],
    Iterable<OutputReference> references = const [],
    this.structuredOutput,
    Map<String, List<JsonObject>> providerData = const {},
  }) : content = List.unmodifiable(content),
       citations = List.unmodifiable(citations),
       references = List.unmodifiable(references),
       toolCalls = List.unmodifiable(toolCalls),
       providerData = Map.unmodifiable({
         for (final entry in providerData.entries)
           entry.key: List<JsonObject>.unmodifiable(
             entry.value.map(immutableJson),
           ),
       }) {
    if (role != MessageRole.assistant && this.citations.isNotEmpty) {
      throw const FormatException(
        'Only assistant messages can contain citations.',
      );
    }
    if (role != MessageRole.assistant && this.references.isNotEmpty) {
      throw const FormatException(
        'Only assistant messages can contain references.',
      );
    }
    for (final reference in this.references) {
      reference.validateFor(text);
    }
    for (final citation in this.citations) {
      citation.validateFor(text);
    }
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
    if (role != MessageRole.assistant && structuredOutput != null) {
      throw ArgumentError(
        'Only assistant messages can contain structured output.',
      );
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
    if (citations.isNotEmpty)
      'citations': [for (final citation in citations) citation.toJson()],
    if (references.isNotEmpty)
      'references': [for (final reference in references) reference.toJson()],
    if (providerData.isNotEmpty) 'providerData': providerData,
    if (structuredOutput != null)
      'structuredOutput': structuredOutput!.toJson(),
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
    citations: _readCitations(json['citations']),
    references: _readReferences(json['references']),
    structuredOutput: json['structuredOutput'] == null
        ? null
        : StructuredMessageOutput.fromJson(
            Map<String, Object?>.from(json['structuredOutput'] as Map),
          ),
    providerData: {
      for (final entry in (json['providerData'] as Map? ?? {}).entries)
        entry.key as String: [
          for (final item in entry.value as List)
            Map<String, Object?>.from(item as Map),
        ],
    },
  );
}

List<TextCitation> _readCitations(Object? value) {
  if (value == null) return const [];
  try {
    return [
      for (final item in value as List)
        TextCitation.fromJson(Map<String, Object?>.from(item as Map)),
    ];
  } catch (_) {
    throw const FormatException('Invalid message citations.');
  }
}

List<OutputReference> _readReferences(Object? value) {
  if (value == null) return const [];
  try {
    return [
      for (final item in value as List)
        OutputReference.fromJson(Map<String, Object?>.from(item as Map)),
    ];
  } catch (_) {
    throw const FormatException('Invalid message references.');
  }
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

sealed class ModelTool {
  final String name;
  final String description;
  final JsonObject inputSchema;
  const ModelTool._({
    required this.name,
    required this.description,
    required this.inputSchema,
  });
  const factory ModelTool({
    required String name,
    required String description,
    required JsonObject inputSchema,
  }) = FunctionModelTool;
}

final class FunctionModelTool extends ModelTool {
  const FunctionModelTool({
    required super.name,
    required super.description,
    required super.inputSchema,
  }) : super._();
}

final class NativeModelTool extends ModelTool {
  final String provider;
  final JsonObject definition;

  /// Private identity of the execution environment across approval resumes.
  final String? bindingId;
  NativeModelTool({
    required super.name,
    required super.description,
    required JsonObject inputSchema,
    required this.provider,
    required JsonObject definition,
    this.bindingId,
  }) : definition = immutableJson(definition),
       super._(inputSchema: immutableJson(inputSchema)) {
    if (bindingId != null && bindingId!.trim().isEmpty) {
      throw ArgumentError.value(bindingId, 'bindingId', 'Must not be empty');
    }
  }
}

final class ModelRequest {
  final List<ChatMessage> messages;
  final List<ModelTool> tools;

  /// Trusted backend-only decisions in conversation order; never expose to UI.
  final List<ProviderApprovalDecision> providerApprovalDecisions;
  final String? instructions;
  final JsonObject? outputSchema;
  final int maxOutputTokens;
  ModelRequest({
    required Iterable<ChatMessage> messages,
    Iterable<ModelTool> tools = const [],
    Iterable<ProviderApprovalDecision> providerApprovalDecisions = const [],
    this.instructions,
    JsonObject? outputSchema,
    this.maxOutputTokens = 1024,
  }) : messages = List.unmodifiable(messages),
       providerApprovalDecisions = List.unmodifiable(providerApprovalDecisions),
       tools = List.unmodifiable(
         tools.map(
           (tool) => switch (tool) {
             FunctionModelTool() => ModelTool(
               name: tool.name,
               description: tool.description,
               inputSchema: immutableJson(tool.inputSchema),
             ),
             NativeModelTool() => NativeModelTool(
               name: tool.name,
               description: tool.description,
               inputSchema: tool.inputSchema,
               provider: tool.provider,
               definition: tool.definition,
               bindingId: tool.bindingId,
             ),
           },
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

/// Optional validation of the complete tool registry before a run can execute.
abstract interface class ModelToolValidator {
  void validateTools(Iterable<ModelTool> tools);
}

sealed class ModelEvent {
  const ModelEvent();
}

final class TextDelta extends ModelEvent {
  final String text;
  const TextDelta(this.text);
}

/// A reference associated with text emitted so far in this model invocation.
final class ReferenceReady extends ModelEvent {
  final OutputReference reference;
  const ReferenceReady(this.reference);
}

/// A validated citation into text emitted so far in this model invocation.
final class CitationReady extends ModelEvent {
  final TextCitation citation;
  const CitationReady(this.citation);
}

final class ReasoningDelta extends ModelEvent {
  final String text;
  const ReasoningDelta(this.text);
}

/// A complete non-text output part. Text remains a stream of [TextDelta] events.
final class ContentPartReady extends ModelEvent {
  final ContentPart part;

  /// UTF-16 offset in accumulated text; omission places the part after current text.
  final int? textOffset;
  ContentPartReady(this.part, {this.textOffset}) {
    if (textOffset != null && textOffset! < 0) {
      throw ArgumentError.value(textOffset);
    }
    if (part is TextPart) throw ArgumentError('Use TextDelta for text output.');
  }
}

final class ToolCallReady extends ModelEvent {
  final ToolCall call;
  const ToolCallReady(this.call);
}

/// Private boundary immediately before a provider-managed effect may start.
final class ProviderExecutionStarting extends ModelEvent {
  const ProviderExecutionStarting();
}

final class ProviderApprovalReady extends ModelEvent {
  final ProviderApprovalCall call;
  const ProviderApprovalReady(this.call);
}

final class NativeToolCallReady extends ModelEvent {
  final NativeToolCall call;
  const NativeToolCallReady(this.call);
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
  final bool continueTurn;
  const ModelFinished([this.reason = 'stop']) : continueTurn = false;

  /// A completed invocation that needs another step without local tool results.
  /// The agent checkpoints its output and counts it against `maxSteps`.
  const ModelFinished.continuation([this.reason = 'pause'])
    : continueTurn = true;
}

final class ProviderOutput extends ModelEvent {
  final String provider;
  final List<JsonObject> items;
  ProviderOutput({required this.provider, required Iterable<JsonObject> items})
    : items = List.unmodifiable(items.map(immutableJson));
}

/// A stable, secret-free profile of provider-controlled execution across a turn.
/// Changes invalidate unfinished continuations. Custom models that can cause
/// provider-managed effects must implement this contract.
abstract interface class ModelContinuationContract {
  /// Versioned JSON with integer `v: 1` and a nonempty adapter-defined `kind`.
  JsonObject get continuationContract;
}

/// Models that validate provider-owned approval configuration.
abstract interface class ProviderApprovalModel implements ChatModel {
  /// Secret-free exact configuration used to bind and validate this approval.
  JsonObject approvalContract(ProviderApprovalCall call);
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
