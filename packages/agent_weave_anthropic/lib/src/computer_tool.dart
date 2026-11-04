import 'dart:async';
import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as api;

const _members = {
  'key',
  'hold_key',
  'type',
  'cursor_position',
  'mouse_move',
  'left_mouse_down',
  'left_mouse_up',
  'left_click',
  'left_click_drag',
  'right_click',
  'middle_click',
  'double_click',
  'triple_click',
  'scroll',
  'wait',
  'screenshot',
  'zoom',
};

typedef AnthropicComputerPoint = ({num x, num y});
typedef AnthropicComputerRegion = ({num x0, num y0, num x1, num y1});

enum AnthropicComputerScrollDirection { up, down, left, right }

enum AnthropicComputerClick {
  leftClick,
  rightClick,
  middleClick,
  doubleClick,
  tripleClick,
}

enum AnthropicComputerEmpty {
  cursorPosition,
  leftMouseDown,
  leftMouseUp,
  screenshot,
}

sealed class AnthropicComputerAction {
  const AnthropicComputerAction();
}

final class AnthropicComputerKey extends AnthropicComputerAction {
  final String text;
  final num? repeat;
  const AnthropicComputerKey(this.text, this.repeat);
}

final class AnthropicComputerHoldKey extends AnthropicComputerAction {
  final String text;
  final num duration;
  const AnthropicComputerHoldKey(this.text, this.duration);
}

final class AnthropicComputerType extends AnthropicComputerAction {
  final String text;
  const AnthropicComputerType(this.text);
}

final class AnthropicComputerEmptyAction extends AnthropicComputerAction {
  final AnthropicComputerEmpty kind;
  const AnthropicComputerEmptyAction(this.kind);
}

final class AnthropicComputerMove extends AnthropicComputerAction {
  final AnthropicComputerPoint coordinate;
  const AnthropicComputerMove(this.coordinate);
}

final class AnthropicComputerClickAction extends AnthropicComputerAction {
  final AnthropicComputerClick kind;
  final AnthropicComputerPoint? coordinate;
  final String? text;
  const AnthropicComputerClickAction(this.kind, this.coordinate, this.text);
}

final class AnthropicComputerDrag extends AnthropicComputerAction {
  final AnthropicComputerPoint coordinate;
  final AnthropicComputerPoint startCoordinate;
  final String? text;
  const AnthropicComputerDrag(this.coordinate, this.startCoordinate, this.text);
}

final class AnthropicComputerScroll extends AnthropicComputerAction {
  final num amount;
  final AnthropicComputerScrollDirection direction;
  final AnthropicComputerPoint? coordinate;
  final String? text;
  const AnthropicComputerScroll(
    this.amount,
    this.direction,
    this.coordinate,
    this.text,
  );
}

final class AnthropicComputerWait extends AnthropicComputerAction {
  final num duration;
  const AnthropicComputerWait(this.duration);
}

final class AnthropicComputerZoom extends AnthropicComputerAction {
  final AnthropicComputerRegion region;
  const AnthropicComputerZoom(this.region);
}

void validateAnthropicComputerDefinition(NativeModelTool tool) {
  final wire = tool.definition;
  if (tool.provider != 'anthropic.messages' ||
      wire['type'] != 'computer_toolset_20260801' ||
      tool.bindingId == null ||
      tool.bindingId!.trim().isEmpty ||
      wire.keys.any(
        (k) => !{
          'type',
          'configs',
          'cache_control',
          'allowed_callers',
        }.contains(k),
      )) {
    throw const FormatException('Invalid computer toolset definition.');
  }
  final callers = wire['allowed_callers'];
  if (callers != null &&
      (callers is! List || callers.length != 1 || callers.single != 'direct')) {
    throw const FormatException('Only direct computer callers are supported.');
  }
  final cache = wire['cache_control'];
  if (cache != null &&
      (cache is! Map ||
          cache['type'] != 'ephemeral' ||
          cache.keys.any((k) => !{'type', 'ttl'}.contains(k)) ||
          (cache['ttl'] != null && !{'5m', '1h'}.contains(cache['ttl'])))) {
    throw const FormatException('Invalid computer cache control.');
  }
  final configs = wire['configs'];
  if (configs != null && configs is! Map) {
    throw const FormatException('Invalid computer configs.');
  }
  final map = configs as Map? ?? {};
  if (map.keys.any((k) => !_members.contains(k))) {
    throw const FormatException('Unknown computer member.');
  }
  final deferred = <bool>{};
  for (final member in _members) {
    final value = map[member];
    if (value != null &&
        (value is! Map ||
            value.keys.any((k) => !{'enabled', 'defer_loading'}.contains(k)) ||
            (value['enabled'] != null && value['enabled'] is! bool) ||
            (value['defer_loading'] != null &&
                value['defer_loading'] is! bool))) {
      throw const FormatException('Invalid computer member config.');
    }
    final config = value as Map?;
    if (config?['enabled'] != false) {
      deferred.add(config?['defer_loading'] as bool? ?? false);
    }
  }
  if (deferred.length > 1) {
    throw const FormatException('Inconsistent defer_loading.');
  }
  validateToolDefinition(tool, null);
}

final class AnthropicComputerCall {
  final JsonObject raw;
  final AnthropicComputerAction action;
  String get id => raw['id'] as String;
  AnthropicComputerCall._(this.raw, this.action);
  void validateResult(AnthropicComputerResult result) {
    if (result.isError) return;
    final image =
        action is AnthropicComputerZoom ||
        (action is AnthropicComputerEmptyAction &&
            (action as AnthropicComputerEmptyAction).kind ==
                AnthropicComputerEmpty.screenshot);
    if (image && !result.content.any((block) => block is api.ImageInputBlock)) {
      throw const FormatException(
        'Screenshot and zoom require an image result.',
      );
    }
    if (action is AnthropicComputerEmptyAction &&
        (action as AnthropicComputerEmptyAction).kind ==
            AnthropicComputerEmpty.cursorPosition &&
        !result.content.any(
          (block) =>
              block is api.TextInputBlock && block.text.trim().isNotEmpty,
        )) {
      throw const FormatException('Cursor position requires a text result.');
    }
  }

  factory AnthropicComputerCall.fromJson(
    JsonObject raw, {
    NativeModelTool? definition,
  }) {
    final name = raw['name'];
    if (raw['type'] != 'tool_use' ||
        raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        name is! String ||
        !_members.contains(name) ||
        raw['toolset_name'] != 'computer' ||
        (raw['caller'] != null &&
            (raw['caller'] is! Map ||
                (raw['caller'] as Map)['type'] != 'direct' ||
                (raw['caller'] as Map).length != 1)) ||
        raw['input'] is! Map) {
      throw const FormatException('Invalid computer call.');
    }
    if (definition != null) {
      validateAnthropicComputerDefinition(definition);
      final configs = definition.definition['configs'] as Map?;
      if ((configs?[name] as Map?)?['enabled'] == false) {
        throw const FormatException('Disabled computer member.');
      }
    }
    final input = Map<String, dynamic>.from(raw['input'] as Map);
    final fields = switch (name) {
      'key' => {'text', 'repeat'},
      'hold_key' => {'text', 'duration'},
      'type' => {'text'},
      'mouse_move' => {'coordinate'},
      'left_click_drag' => {'coordinate', 'start_coordinate', 'text'},
      'left_click' ||
      'right_click' ||
      'middle_click' ||
      'double_click' ||
      'triple_click' => {'coordinate', 'text'},
      'scroll' => {'scroll_amount', 'scroll_direction', 'coordinate', 'text'},
      'wait' => {'duration'},
      'zoom' => {'region'},
      _ => <String>{},
    };
    if (input.keys.any((k) => !fields.contains(k))) {
      throw const FormatException('Unknown computer input field.');
    }
    String str(String key) {
      final v = input[key];
      if (v is! String) throw FormatException('Invalid $key.');
      return v;
    }

    String? optionalText() {
      final v = input['text'];
      if (v != null && v is! String) {
        throw const FormatException('Invalid text.');
      }
      return v as String?;
    }

    num number(String key) {
      final v = input[key];
      if (v is! num || !v.isFinite) throw FormatException('Invalid $key.');
      return v;
    }

    List<num> list(String key, int length) {
      final v = input[key];
      if (v is! List ||
          v.length != length ||
          v.any((x) => x is! num || !x.isFinite)) {
        throw FormatException('Invalid $key.');
      }
      return v.cast<num>();
    }

    AnthropicComputerPoint point(String key) {
      final v = list(key, 2);
      return (x: v[0], y: v[1]);
    }

    AnthropicComputerPoint? coordinate() =>
        input['coordinate'] == null ? null : point('coordinate');
    AnthropicComputerRegion region() {
      final v = list('region', 4);
      return (x0: v[0], y0: v[1], x1: v[2], y1: v[3]);
    }

    AnthropicComputerScrollDirection direction() =>
        switch (str('scroll_direction')) {
          'up' => AnthropicComputerScrollDirection.up,
          'down' => AnthropicComputerScrollDirection.down,
          'left' => AnthropicComputerScrollDirection.left,
          'right' => AnthropicComputerScrollDirection.right,
          _ => throw const FormatException('Invalid scroll direction.'),
        };
    final action = switch (name) {
      'key' => AnthropicComputerKey(
        str('text'),
        input['repeat'] == null ? null : number('repeat'),
      ),
      'hold_key' => AnthropicComputerHoldKey(str('text'), number('duration')),
      'type' => AnthropicComputerType(str('text')),
      'cursor_position' => const AnthropicComputerEmptyAction(
        AnthropicComputerEmpty.cursorPosition,
      ),
      'left_mouse_down' => const AnthropicComputerEmptyAction(
        AnthropicComputerEmpty.leftMouseDown,
      ),
      'left_mouse_up' => const AnthropicComputerEmptyAction(
        AnthropicComputerEmpty.leftMouseUp,
      ),
      'screenshot' => const AnthropicComputerEmptyAction(
        AnthropicComputerEmpty.screenshot,
      ),
      'mouse_move' => AnthropicComputerMove(point('coordinate')),
      'left_click_drag' => AnthropicComputerDrag(
        point('coordinate'),
        point('start_coordinate'),
        optionalText(),
      ),
      'left_click' ||
      'right_click' ||
      'middle_click' ||
      'double_click' ||
      'triple_click' => AnthropicComputerClickAction(
        AnthropicComputerClick.values[[
          'left_click',
          'right_click',
          'middle_click',
          'double_click',
          'triple_click',
        ].indexOf(name)],
        coordinate(),
        optionalText(),
      ),
      'scroll' => AnthropicComputerScroll(
        number('scroll_amount'),
        direction(),
        coordinate(),
        optionalText(),
      ),
      'wait' => AnthropicComputerWait(number('duration')),
      'zoom' => AnthropicComputerZoom(region()),
      _ => throw const FormatException('Unknown computer member.'),
    };
    if (action is AnthropicComputerKey &&
        action.repeat != null &&
        (action.repeat! < 1 || action.repeat! > 100)) {
      throw const FormatException('Invalid key repeat.');
    }
    if ((action is AnthropicComputerHoldKey && action.duration > 300) ||
        (action is AnthropicComputerWait && action.duration > 300)) {
      throw const FormatException('Invalid duration.');
    }
    return AnthropicComputerCall._(
      immutableJson({
        'type': 'tool_use',
        'id': raw['id'],
        'name': name,
        'toolset_name': 'computer',
        'input': input,
        if (raw['caller'] != null) 'caller': {'type': 'direct'},
      }),
      action,
    );
  }
}

final class AnthropicComputerResult {
  final List<api.InputContentBlock> content;
  final bool isError;
  AnthropicComputerResult({
    Iterable<api.InputContentBlock> content = const [],
    this.isError = false,
  }) : content = List.unmodifiable(content) {
    for (final block in this.content) {
      if (block is! api.TextInputBlock && block is! api.ImageInputBlock) {
        throw ArgumentError('Only text and image content are supported.');
      }
      if (block is api.ImageInputBlock) {
        final source = block.source;
        if (source is api.Base64ImageSource &&
            (source.data.isEmpty || base64Decode(source.data).isEmpty)) {
          throw const FormatException('Invalid image data.');
        }
        if (source is api.UrlImageSource && source.url.trim().isEmpty) {
          throw const FormatException('Invalid image URL.');
        }
      }
      jsonEncode(block.toJson());
    }
  }
  factory AnthropicComputerResult.fromJson(JsonObject value) {
    if (value['content'] is! List ||
        value.keys.any((key) => !{'content', 'is_error'}.contains(key)) ||
        (value['is_error'] != null && value['is_error'] is! bool)) {
      throw const FormatException('Invalid computer result.');
    }
    final blocks = value['content'] as List;
    if (blocks.any((block) => block is! Map)) {
      throw const FormatException('Invalid computer result block.');
    }
    final result = AnthropicComputerResult(
      content: [
        for (final block in blocks)
          api.InputContentBlock.fromJson(
            Map<String, dynamic>.from(block as Map),
          ),
      ],
      isError: value['is_error'] == true,
    );
    if (canonicalJson(result.toJson()['content']) != canonicalJson(blocks)) {
      throw const FormatException('Unsupported computer result field.');
    }
    return result;
  }
  factory AnthropicComputerResult.text(String text) =>
      AnthropicComputerResult(content: [api.InputContentBlock.text(text)]);
  factory AnthropicComputerResult.empty() => AnthropicComputerResult();
  factory AnthropicComputerResult.screenshot(api.ImageSource source) =>
      AnthropicComputerResult(content: [api.InputContentBlock.image(source)]);
  factory AnthropicComputerResult.error(String text) => AnthropicComputerResult(
    content: [api.InputContentBlock.text(text)],
    isError: true,
  );
  JsonObject toJson() => immutableJson({
    'content': [for (final block in content) block.toJson()],
    if (isError) 'is_error': true,
  });
}

final class AnthropicComputerTool<C> implements SequentialNativeTool<C> {
  @override
  final NativeModelTool definition;
  @override
  final bool needsApproval;
  final FutureOr<AnthropicComputerResult> Function(
    AnthropicComputerCall,
    ToolContext<C>,
  )
  execute;
  AnthropicComputerTool({
    String name = 'computer',
    String description = 'Use the computer',
    required String environmentId,
    api.ComputerToolsetConfigs? configs,
    api.CacheControlEphemeral? cacheControl,
    List<String>? allowedCallers,
    this.needsApproval = true,
    required this.execute,
  }) : definition = NativeModelTool(
         name: name,
         description: description,
         inputSchema: const {'type': 'object'},
         provider: 'anthropic.messages',
         bindingId: environmentId,
         definition: {
           'type': 'computer_toolset_20260801',
           if (configs != null) 'configs': configs.toJson(),
           if (cacheControl != null) 'cache_control': cacheControl.toJson(),
           'allowed_callers': ?allowedCallers,
         },
       ) {
    validateAnthropicComputerDefinition(definition);
  }
  @override
  bool isFailure(Object? result) => result is Map && result['is_error'] == true;
  @override
  Object? skippedResult() => AnthropicComputerResult.error(
    'Not executed: an earlier computer action in this turn failed.',
  ).toJson();
  @override
  bool get clientExecuted => false;
  @override
  JsonObject? get outputSchema => null;
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<C> context) async {
    context.cancellation.throwIfCancelled();
    final call = AnthropicComputerCall.fromJson(input, definition: definition);
    if (call.id != context.toolCallId) {
      throw const FormatException(
        'Computer call ID does not match tool context.',
      );
    }
    if (needsApproval && !context.approved) {
      throw StateError('Computer call requires approval.');
    }
    final result = await execute(call, context);
    context.cancellation.throwIfCancelled();
    call.validateResult(result);
    return result.toJson();
  }
}
