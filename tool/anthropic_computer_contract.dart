import 'dart:convert';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart';

void main() {
  final click = {
    'coordinate': [1, 2],
    'text': 'shift',
  };
  final inputs = <String, Map<String, Object?>>{
    'key': {'text': 'Return', 'repeat': 2},
    'hold_key': {'text': 'shift', 'duration': 1},
    'type': {'text': 'hello'},
    'cursor_position': {},
    'left_mouse_down': {},
    'left_mouse_up': {},
    'screenshot': {},
    'mouse_move': {
      'coordinate': [1, 2],
    },
    'left_click': click,
    'right_click': click,
    'middle_click': click,
    'double_click': click,
    'triple_click': click,
    'left_click_drag': {
      'coordinate': [1, 2],
      'start_coordinate': [3, 4],
      'text': 'shift',
    },
    'scroll': {
      'scroll_amount': 2,
      'scroll_direction': 'down',
      'coordinate': [1, 2],
      'text': 'shift',
    },
    'wait': {'duration': 1},
    'zoom': {
      'region': [1, 2, 3, 4],
    },
  };
  final requiredFields = <String, List<String>>{};
  for (final entry in inputs.entries) {
    final raw = <String, dynamic>{
      'type': 'tool_use',
      'id': 'id',
      'name': entry.key,
      'toolset_name': 'computer',
      'input': entry.value,
    };
    final parsed = AnthropicComputerCall.fromJson(raw);
    if (jsonEncode(parsed.raw['input']) != jsonEncode(entry.value)) {
      throw StateError('Failed input ${entry.key}');
    }
    final missing = <String>[];
    for (final field in entry.value.keys) {
      final reduced = Map<String, Object?>.from(entry.value)..remove(field);
      try {
        AnthropicComputerCall.fromJson({...raw, 'input': reduced});
      } on FormatException {
        missing.add(field);
      }
    }
    requiredFields[entry.key] = missing;
    try {
      AnthropicComputerCall.fromJson({
        ...raw,
        'input': {...entry.value, 'unexpected': true},
      });
      throw StateError('Accepted unexpected field in ${entry.key}');
    } on FormatException {
      /* expected */
    }
  }
  final configs = {
    for (final name in inputs.keys)
      name: {'enabled': true, 'defer_loading': false},
  };
  final tool = AnthropicComputerTool<void>(
    environmentId: 'desktop',
    configs: ComputerToolsetConfigs.fromJson(configs),
    cacheControl: CacheControlEphemeral.fromJson({
      'type': 'ephemeral',
      'ttl': '1h',
    }),
    allowedCallers: const ['direct'],
    execute: (_, _) => AnthropicComputerResult.empty(),
  );
  final definition = tool.definition;
  validateAnthropicComputerDefinition(definition);
  final text = AnthropicComputerResult.text('ok').toJson();
  final error = AnthropicComputerResult.error('failed').toJson();
  final image = AnthropicComputerResult.screenshot(
    ImageSource.base64(data: 'aGVsbG8=', mediaType: ImageMediaType.png),
  ).toJson();
  if (text['is_error'] == true || error['is_error'] != true) {
    throw StateError('Result error flag');
  }
  print(
    jsonEncode({
      'inputs': inputs,
      'required': requiredFields,
      'configs': definition.definition['configs'],
      'definition': definition.definition,
      'directions': [
        for (final direction in AnthropicComputerScrollDirection.values)
          direction.name,
      ],
      'text': text,
      'error': error,
      'image': image,
    }),
  );
}
