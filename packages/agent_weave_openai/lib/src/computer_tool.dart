import 'dart:async';
import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:openai_dart/openai_dart.dart' as api;

/// Approval policy for an application-owned computer executor.
enum ComputerApproval { always, safetyChecks }

/// Execution environment for the preview computer profile.
enum ComputerEnvironment { browser, mac, windows, linux, ubuntu }

/// A validated, immutable provider call. Actions are ordered as supplied.
final class OpenAIComputerCall {
  final JsonObject raw;
  final List<api.ComputerAction> actions;
  final List<JsonObject> safetyChecks;
  String get callId => raw['call_id'] as String;

  OpenAIComputerCall._(this.raw, this.actions, this.safetyChecks);

  factory OpenAIComputerCall.fromJson(JsonObject input) {
    final raw = immutableJson(input);
    if (raw['type'] != 'computer_call' ||
        raw['call_id'] is! String ||
        (raw['call_id'] as String).isEmpty ||
        raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        raw['status'] != 'completed') {
      throw const FormatException('Invalid or incomplete computer call.');
    }
    final actionList = raw['actions'];
    final action = raw['action'];
    if ((actionList == null) == (action == null) ||
        (actionList != null && (actionList is! List || actionList.isEmpty))) {
      throw const FormatException('Invalid computer actions.');
    }
    final actions = <api.ComputerAction>[];
    for (final entry in actionList as List? ?? [action]) {
      if (entry is! Map) {
        throw const FormatException('Invalid computer action.');
      }
      final fields = switch (entry['type']) {
        'click' => {'type', 'button', 'x', 'y', 'keys'},
        'double_click' || 'move' => {'type', 'x', 'y', 'keys'},
        'drag' => {'type', 'path', 'keys'},
        'keypress' => {'type', 'keys'},
        'scroll' => {'type', 'x', 'y', 'scroll_x', 'scroll_y', 'keys'},
        'type' => {'type', 'text'},
        'screenshot' || 'wait' => {'type'},
        _ => throw const FormatException('Unknown computer action.'),
      };
      if (entry.keys.any((key) => !fields.contains(key))) {
        throw const FormatException('Unsupported computer action field.');
      }
      final parsed = api.ComputerAction.fromJson(
        Map<String, dynamic>.from(entry),
      );
      if (parsed is api.ClickAction &&
          parsed.button == api.ClickButton.unknown) {
        throw const FormatException('Unknown computer button.');
      }
      // Force validation of SDK lazy casts before any application callback.
      jsonEncode(parsed.toJson());
      if (parsed is api.DragAction) {
        final path = parsed.path
            .map((point) {
              if (point['x'] is! int ||
                  point['y'] is! int ||
                  point.keys.any((key) => key != 'x' && key != 'y')) {
                throw const FormatException('Invalid drag point.');
              }
              return Map<String, dynamic>.unmodifiable({
                'x': point['x'],
                'y': point['y'],
              });
            })
            .toList(growable: false);
        actions.add(
          api.DragAction(
            path: List.unmodifiable(path),
            keys: parsed.keys == null ? null : List.unmodifiable(parsed.keys!),
          ),
        );
      } else {
        actions.add(parsed);
      }
    }
    final checks = raw['pending_safety_checks'];
    if (action != null && checks == null) {
      throw const FormatException(
        'Legacy computer call requires safety checks.',
      );
    }
    if (checks != null && checks is! List) {
      throw const FormatException('Invalid safety checks.');
    }
    final safetyChecks = <JsonObject>[];
    for (final check in checks as List? ?? []) {
      if (check is! Map ||
          check['id'] is! String ||
          (check['id'] as String).isEmpty ||
          (check['code'] != null && check['code'] is! String) ||
          (check['message'] != null && check['message'] is! String)) {
        throw const FormatException('Invalid safety check.');
      }
      safetyChecks.add(
        immutableJson({
          'id': check['id'],
          if (check.containsKey('code')) 'code': check['code'],
          if (check.containsKey('message')) 'message': check['message'],
        }),
      );
    }
    final safeRaw = immutableJson({
      'type': 'computer_call',
      'id': raw['id'],
      'call_id': raw['call_id'],
      'status': raw['status'],
      if (action != null)
        'action': actions.single.toJson()
      else
        'actions': [for (final value in actions) value.toJson()],
      if (checks != null) 'pending_safety_checks': safetyChecks,
    });
    return OpenAIComputerCall._(
      safeRaw,
      List.unmodifiable(actions),
      List.unmodifiable(safetyChecks),
    );
  }
}

/// A fresh screenshot captured by the application after the complete action batch.
final class OpenAIComputerScreenshot {
  final String? imageUrl;
  final String? fileId;
  final api.ImageDetail? detail;
  OpenAIComputerScreenshot({this.imageUrl, this.fileId, this.detail}) {
    if ((imageUrl == null) == (fileId == null) ||
        (imageUrl != null && imageUrl!.isEmpty) ||
        (fileId != null && fileId!.isEmpty)) {
      throw ArgumentError('Provide exactly one nonempty imageUrl or fileId.');
    }
    if (imageUrl != null && imageUrl!.startsWith('data:')) {
      final match = RegExp(
        r'^data:image/[a-zA-Z0-9.+-]+;base64,(.+)$',
      ).firstMatch(imageUrl!);
      if (match == null) {
        throw const FormatException('Invalid screenshot data URL.');
      }
      final bytes = base64Decode(match.group(1)!);
      if (bytes.isEmpty) throw const FormatException('Empty screenshot data.');
    }
  }
  OpenAIComputerScreenshot.url(String url, {api.ImageDetail? detail})
    : this(imageUrl: url, detail: detail);
  OpenAIComputerScreenshot.fileId(String id, {api.ImageDetail? detail})
    : this(fileId: id, detail: detail);
  JsonObject toJson() => {
    'type': 'computer_screenshot',
    if (imageUrl != null) 'image_url': imageUrl,
    if (fileId != null) 'file_id': fileId,
    if (detail != null) 'detail': detail!.value,
  };
}

/// Registers a computer environment; the application owns all side effects.
final class OpenAIComputerTool<C> implements AgentTool<C> {
  @override
  final NativeModelTool definition;
  final ComputerApproval approval;
  final FutureOr<OpenAIComputerScreenshot> Function(
    OpenAIComputerCall,
    ToolContext<C>,
  )
  execute;

  OpenAIComputerTool({
    String name = 'computer',
    String description = 'Use the computer',
    required String environmentId,
    this.approval = ComputerApproval.always,
    required this.execute,
  }) : definition = _definition(name, description, environmentId, {
         'type': 'computer',
       });

  OpenAIComputerTool.preview({
    String name = 'computer',
    String description = 'Use the computer',
    required String environmentId,
    required int width,
    required int height,
    required ComputerEnvironment environment,
    this.approval = ComputerApproval.always,
    required this.execute,
  }) : definition = _definition(name, description, environmentId, {
         'type': 'computer_use_preview',
         'display_width': width,
         'display_height': height,
         'environment': environment.name,
       }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Invalid preview computer environment.');
    }
  }

  static NativeModelTool _definition(
    String name,
    String description,
    String environmentId,
    JsonObject wire,
  ) {
    if (environmentId.trim().isEmpty) {
      throw ArgumentError('environmentId must not be empty.');
    }
    final definition = NativeModelTool(
      name: name,
      description: description,
      inputSchema: const {'type': 'object'},
      provider: 'openai.responses',
      definition: wire,
      bindingId: environmentId,
    );
    validateToolDefinition(definition, null);
    return definition;
  }

  @override
  bool get needsApproval => approval == ComputerApproval.always;
  @override
  bool get clientExecuted => false;
  @override
  JsonObject? get outputSchema => null;
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<C> context) async {
    context.cancellation.throwIfCancelled();
    final call = OpenAIComputerCall.fromJson(input);
    if (call.callId != context.toolCallId) {
      throw const FormatException(
        'Computer call ID does not match tool context.',
      );
    }
    if ((needsApproval || call.safetyChecks.isNotEmpty) && !context.approved) {
      throw StateError('Computer call requires approval.');
    }
    final screenshot = await execute(call, context);
    context.cancellation.throwIfCancelled();
    return {
      'output': screenshot.toJson(),
      if (call.safetyChecks.isNotEmpty)
        'acknowledged_safety_checks': call.safetyChecks,
    };
  }
}
