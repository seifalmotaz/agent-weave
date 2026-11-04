import 'dart:async';
import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';

import 'custom_definition.dart';

enum OpenAICustomGrammarSyntax { lark, regex }

enum OpenAICustomAllowedCaller { direct, programmatic }

final class OpenAIToolNamespace {
  final String name;
  final String description;
  OpenAIToolNamespace({required this.name, required this.description}) {
    if (name.trim().isEmpty) {
      throw ArgumentError('Namespace name must not be empty.');
    }
  }
}

final class OpenAICustomToolFormat {
  final JsonObject _value;
  OpenAICustomToolFormat.text() : _value = const {'type': 'text'};
  OpenAICustomToolFormat.grammar(
    String definition, {
    required OpenAICustomGrammarSyntax syntax,
  }) : _value = immutableJson({
         'type': 'grammar',
         'definition': definition,
         'syntax': syntax.name,
       });
  JsonObject toJson() => _value;
}

/// Native cache breakpoint on custom tool result content.
final class OpenAICustomPromptCacheBreakpoint {
  final String? ttl;
  OpenAICustomPromptCacheBreakpoint({this.ttl}) {
    if (ttl != null && ttl != '30m' && ttl != '12h') {
      throw ArgumentError('Invalid cache TTL.');
    }
  }
  JsonObject toJson() => {'mode': 'explicit', if (ttl != null) 'ttl': ttl};
}

/// One native custom tool result content block.
final class OpenAICustomToolContent {
  final JsonObject _json;
  OpenAICustomToolContent._(this._json);
  factory OpenAICustomToolContent.text(
    String text, {
    OpenAICustomPromptCacheBreakpoint? cache,
  }) => OpenAICustomToolContent.fromJson({
    'type': 'input_text',
    'text': text,
    if (cache != null) 'prompt_cache_breakpoint': cache.toJson(),
  });
  factory OpenAICustomToolContent.image({
    required String detail,
    String? imageUrl,
    String? fileId,
    OpenAICustomPromptCacheBreakpoint? cache,
  }) => OpenAICustomToolContent.fromJson({
    'type': 'input_image',
    'detail': detail,
    'image_url': ?imageUrl,
    'file_id': ?fileId,
    if (cache != null) 'prompt_cache_breakpoint': cache.toJson(),
  });
  factory OpenAICustomToolContent.file({
    String? detail,
    String? fileData,
    String? fileId,
    String? fileUrl,
    String? filename,
    OpenAICustomPromptCacheBreakpoint? cache,
  }) => OpenAICustomToolContent.fromJson({
    'type': 'input_file',
    'detail': ?detail,
    'file_data': ?fileData,
    'file_id': ?fileId,
    'file_url': ?fileUrl,
    'filename': ?filename,
    if (cache != null) 'prompt_cache_breakpoint': cache.toJson(),
  });
  factory OpenAICustomToolContent.fromJson(JsonObject value) {
    final json = immutableJson(value);
    jsonEncode(json);
    void optionalString(String key, {bool nullable = false}) {
      if (json.containsKey(key) &&
          json[key] is! String &&
          !(nullable && json[key] == null)) {
        throw FormatException('Invalid content $key.');
      }
    }

    switch (json['type']) {
      case 'input_text':
        if (json['text'] is! String) {
          throw const FormatException('Invalid text content.');
        }
      case 'input_image':
        if (!const [
          'auto',
          'low',
          'high',
          'original',
        ].contains(json['detail'])) {
          throw const FormatException('Invalid image detail.');
        }
        optionalString('image_url', nullable: true);
        optionalString('file_id', nullable: true);
      case 'input_file':
        if (json.containsKey('detail') &&
            !const ['auto', 'low', 'high'].contains(json['detail'])) {
          throw const FormatException('Invalid file detail.');
        }
        for (final key in ['file_data', 'file_url', 'filename']) {
          optionalString(key);
        }
        optionalString('file_id', nullable: true);
      default:
        throw const FormatException('Unsupported custom tool content type.');
    }
    if (json.containsKey('prompt_cache_breakpoint')) {
      final cache = json['prompt_cache_breakpoint'];
      if (cache is! Map ||
          cache['mode'] != 'explicit' ||
          (cache.containsKey('ttl') &&
              !const ['30m', '12h'].contains(cache['ttl']))) {
        throw const FormatException('Invalid cache breakpoint.');
      }
    }
    return OpenAICustomToolContent._(json);
  }
  JsonObject toJson() => _json;
}

final class OpenAICustomToolResult {
  final Object output;
  final bool isError;

  /// Optional application-supplied output item ID.
  final String? id;

  /// Optional application-supplied direct caller, never inferred by the SDK.
  final JsonObject? caller;
  final bool _hasCaller;
  OpenAICustomToolResult._(
    this.output,
    this.isError,
    this.id,
    this.caller,
    this._hasCaller,
  );

  factory OpenAICustomToolResult.text(
    String output, {
    String? id,
    JsonObject? caller,
  }) => OpenAICustomToolResult.fromJson({
    'output': output,
    'isError': false,
    'id': ?id,
    'caller': ?caller,
  });
  factory OpenAICustomToolResult.error(
    String output, {
    String? id,
    JsonObject? caller,
  }) => OpenAICustomToolResult.fromJson({
    'output': output,
    'isError': true,
    'id': ?id,
    'caller': ?caller,
  });
  factory OpenAICustomToolResult.content(
    Iterable<OpenAICustomToolContent> output, {
    String? id,
    JsonObject? caller,
  }) => OpenAICustomToolResult.fromJson({
    'output': [for (final part in output) part.toJson()],
    'isError': false,
    'id': ?id,
    'caller': ?caller,
  });
  factory OpenAICustomToolResult.fromJson(JsonObject value) {
    if (value.keys.any(
          (k) => !const {'output', 'isError', 'id', 'caller'}.contains(k),
        ) ||
        value['isError'] is! bool ||
        (value.containsKey('id') && value['id'] is! String)) {
      throw const FormatException('Invalid custom result.');
    }
    final rawCaller = value['caller'];
    if (rawCaller != null &&
        (rawCaller is! Map ||
            rawCaller.length != 1 ||
            rawCaller['type'] != 'direct')) {
      throw const FormatException('Invalid custom result caller.');
    }
    final caller = rawCaller == null
        ? null
        : immutableJson(Map<String, Object?>.from(rawCaller as Map));
    final output = value['output'];
    if (output is String) {
      return OpenAICustomToolResult._(
        output,
        value['isError'] as bool,
        value['id'] as String?,
        caller,
        value.containsKey('caller'),
      );
    }
    if (output is List) {
      return OpenAICustomToolResult._(
        List<JsonObject>.unmodifiable(
          output.map((e) {
            if (e is! Map) {
              throw const FormatException('Invalid custom result content.');
            }
            return OpenAICustomToolContent.fromJson(
              Map<String, Object?>.from(e),
            ).toJson();
          }),
        ),
        value['isError'] as bool,
        value['id'] as String?,
        caller,
        value.containsKey('caller'),
      );
    }
    throw const FormatException('Invalid custom result output.');
  }
  JsonObject toJson() => immutableJson({
    'output': output,
    'isError': isError,
    'id': ?id,
    if (_hasCaller) 'caller': caller,
  });
}

/// Validated direct custom call; raw provider metadata remains private to adapters.
final class OpenAICustomCall {
  final JsonObject raw;
  OpenAICustomCall._(this.raw);
  String get id => raw['id'] as String;
  String get callId => raw['call_id'] as String;
  String get name => raw['name'] as String;
  String get input => raw['input'] as String;
  String? get namespace => raw['namespace'] as String?;
  factory OpenAICustomCall.fromJson(JsonObject value) {
    final raw = immutableJson(value);
    if (raw['type'] != 'custom_tool_call' ||
        raw['status'] != 'completed' ||
        raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        raw['call_id'] is! String ||
        (raw['call_id'] as String).isEmpty ||
        raw['name'] is! String ||
        (raw['name'] as String).isEmpty ||
        raw['input'] is! String ||
        (raw.containsKey('namespace') && raw['namespace'] is! String) ||
        (raw.containsKey('async') && raw['async'] != false)) {
      throw const FormatException('Invalid or unsupported custom call.');
    }
    final caller = raw['caller'];
    if (caller != null &&
        (caller is! Map || caller['type'] != 'direct' || caller.length != 1)) {
      throw const FormatException('Unsupported custom caller.');
    }
    jsonEncode(raw);
    return OpenAICustomCall._(raw);
  }
}

final class OpenAICustomTool<C> implements AgentTool<C>, NativeToolFallback<C> {
  @override
  final NativeModelTool definition;
  @override
  final bool needsApproval;
  final FutureOr<OpenAICustomToolResult> Function(
    String input,
    ToolContext<C> context,
  )
  execute;
  OpenAICustomTool({
    required String name,
    String? localName,
    OpenAIToolNamespace? namespace,
    required String bindingId,
    this.needsApproval = false,
    String? description,
    OpenAICustomToolFormat? format,
    bool? deferLoading,
    bool? isAsync,
    List<OpenAICustomAllowedCaller>? allowedCallers,
    required this.execute,
  }) : definition = _definition(
         name,
         localName,
         namespace,
         bindingId,
         description,
         format,
         deferLoading,
         isAsync,
         allowedCallers,
       );
  static NativeModelTool _definition(
    String name,
    String? localName,
    OpenAIToolNamespace? namespace,
    String bindingId,
    String? description,
    OpenAICustomToolFormat? format,
    bool? deferLoading,
    bool? isAsync,
    List<OpenAICustomAllowedCaller>? allowedCallers,
  ) {
    if (name.trim().isEmpty || bindingId.trim().isEmpty) {
      throw ArgumentError('Tool name and bindingId must not be empty.');
    }
    if (isAsync == true) {
      throw UnsupportedError('Asynchronous custom tools are not supported.');
    }
    if (allowedCallers != null &&
        (allowedCallers.isEmpty ||
            allowedCallers.contains(OpenAICustomAllowedCaller.programmatic))) {
      throw UnsupportedError('Programmatic custom calls are not supported.');
    }
    final native = <String, Object?>{
      'type': 'custom',
      'name': name,
      'description': ?description,
      if (format != null) 'format': format.toJson(),
      'defer_loading': ?deferLoading,
      'async': ?isAsync,
      if (allowedCallers != null)
        'allowed_callers': [for (final value in allowedCallers) value.name],
    };
    validateCustomToolDefinition(native);
    final tool = NativeModelTool(
      name: localName ?? name,
      description: description ?? '',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'input': {'type': 'string'},
        },
        'required': ['input'],
        'additionalProperties': false,
      },
      provider: 'openai.responses',
      definition: namespace == null
          ? native
          : {
              'type': 'namespace',
              'name': namespace.name,
              'description': namespace.description,
              'tools': [native],
            },
      bindingId: bindingId,
    );
    validateToolDefinition(tool, null);
    return tool;
  }

  @override
  bool get clientExecuted => false;
  @override
  JsonObject? get outputSchema => null;
  @override
  Object? declinedResult({required bool cancelled}) =>
      OpenAICustomToolResult.error(
        cancelled ? 'Tool call cancelled.' : 'Tool call declined.',
      ).toJson();
  @override
  Object? skippedResult() =>
      OpenAICustomToolResult.error('Tool call skipped.').toJson();
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<C> context) async {
    context.cancellation.throwIfCancelled();
    validateSchema(definition.inputSchema, input);
    if (needsApproval && !context.approved) {
      throw StateError('Custom call requires approval.');
    }
    final result = await execute(input['input'] as String, context);
    context.cancellation.throwIfCancelled();
    return result.toJson();
  }
}
