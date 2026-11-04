import 'package:agent_weave/agent_weave.dart';

/// Validate supported known fields while retaining unknown native extensions.
void validateCustomToolDefinition(JsonObject value) {
  if (value['type'] != 'custom' ||
      value['name'] is! String ||
      (value['name'] as String).isEmpty) {
    throw ArgumentError('Invalid custom tool identity.');
  }
  if (value.containsKey('description') && value['description'] is! String) {
    throw ArgumentError('Invalid custom tool description.');
  }
  for (final key in ['async', 'defer_loading']) {
    if (value.containsKey(key) && value[key] is! bool) {
      throw ArgumentError('Invalid custom tool option: $key.');
    }
  }
  if (value['async'] == true) {
    throw UnsupportedError('Asynchronous custom tools are not supported.');
  }
  if (value.containsKey('allowed_callers') &&
      value['allowed_callers'] != null) {
    final callers = value['allowed_callers'];
    if (callers is! List ||
        callers.isEmpty ||
        callers.any((c) => c is! String)) {
      throw ArgumentError('Invalid custom tool callers.');
    }
    if (callers.any((c) => c != 'direct')) {
      throw UnsupportedError('Only direct custom tool calls are supported.');
    }
  }
  if (value.containsKey('format')) {
    final format = value['format'];
    if (format is! Map) throw ArgumentError('Invalid custom tool format.');
    switch (format['type']) {
      case 'text':
        break;
      case 'grammar':
        if (format['definition'] is! String ||
            !const ['lark', 'regex'].contains(format['syntax'])) {
          throw ArgumentError('Invalid custom tool grammar.');
        }
      default:
        throw ArgumentError('Invalid custom tool format.');
    }
  }
}
