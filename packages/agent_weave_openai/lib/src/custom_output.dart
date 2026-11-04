import 'package:agent_weave/agent_weave.dart';
import 'custom_definition.dart';

/// Registry keyed by provider identity, with a separate local executor alias.
final class CustomRegistry {
  final Map<(String?, String), NativeModelTool> byIdentity = {};
  final Map<String, NativeModelTool> byAlias = {};
  final Map<String, String> namespaces = {};
  NativeModelTool? computer;

  CustomRegistry(Iterable<ModelTool> tools, String provider) {
    for (final tool in tools.whereType<NativeModelTool>()) {
      if (provider != 'openai.responses' ||
          tool.provider != provider ||
          tool.bindingId == null) {
        throw UnsupportedError(
          'Unsupported native Responses tool configuration.',
        );
      }
      final definition = tool.definition;
      if ({'computer', 'computer_use_preview'}.contains(definition['type'])) {
        if (computer != null) {
          throw UnsupportedError('Only one computer tool may be registered.');
        }
        computer = tool;
        continue;
      }
      String? namespace;
      JsonObject custom;
      if (definition['type'] == 'namespace') {
        final items = definition['tools'];
        if (definition['name'] is! String ||
            definition['description'] is! String ||
            items is! List ||
            items.length != 1 ||
            items.single is! Map<String, Object?>) {
          throw ArgumentError('Invalid custom namespace definition.');
        }
        namespace = definition['name'] as String;
        final description = definition['description'] as String;
        if (namespace.isEmpty ||
            (namespaces.containsKey(namespace) &&
                namespaces[namespace] != description)) {
          throw ArgumentError('Conflicting custom namespace definitions.');
        }
        namespaces[namespace] = description;
        custom = items.single as JsonObject;
      } else {
        custom = definition;
      }
      validateCustomToolDefinition(custom);
      final name = custom['name'] as String;
      final identity = (namespace, name);
      if (byIdentity.containsKey(identity) || byAlias.containsKey(tool.name)) {
        throw ArgumentError('Duplicate custom tool identity.');
      }
      byIdentity[identity] = tool;
      byAlias[tool.name] = tool;
    }
  }

  List<JsonObject> wireTools(Iterable<NativeModelTool> native) {
    final output = <JsonObject>[];
    final emitted = <String>{};
    for (final tool in native) {
      final def = tool.definition;
      if (def['type'] != 'namespace') {
        output.add(def);
        continue;
      }
      final name = def['name'] as String;
      if (!emitted.add(name)) continue;
      output.add({
        'type': 'namespace',
        'name': name,
        'description': namespaces[name],
        'tools': [
          for (final other in native)
            if (other.definition['type'] == 'namespace' &&
                other.definition['name'] == name)
              ...(other.definition['tools'] as List),
        ],
      });
    }
    return output;
  }

  NativeModelTool resolve(String? namespace, String name) =>
      byIdentity[(namespace, name)] ??
      (throw const FormatException('Unregistered custom tool identity.'));
}

final class _CustomProgress {
  final String id;
  final StringBuffer text = StringBuffer();
  bool sawDelta = false;
  String? doneInput;
  JsonObject? addedItem;
  JsonObject? doneItem;
  _CustomProgress(this.id);
}

/// Reconciles any observed streaming fragments with the terminal item.
final class CustomStreamTracker {
  final Map<int, _CustomProgress> _indexes = {};
  final Map<String, int> _ids = {};
  int? _lastSequence;

  void _sequence(JsonObject event) {
    final value = event['sequence_number'];
    if (value is! int ||
        value < 0 ||
        (_lastSequence != null && value <= _lastSequence!)) {
      throw const FormatException('Invalid custom stream sequence.');
    }
    _lastSequence = value;
  }

  bool _matchesInput(_CustomProgress state, String input) {
    final prefix = state.addedItem?['input'] as String? ?? '';
    if (!input.startsWith(prefix)) return false;
    if (!state.sawDelta) return true;
    final delta = state.text.toString();
    return delta == input || '$prefix$delta' == input;
  }

  _CustomProgress _at(Object? index, Object? id) {
    if (index is! int ||
        index < 0 ||
        id is! String ||
        id.isEmpty ||
        (_ids.containsKey(id) && _ids[id] != index)) {
      throw const FormatException('Invalid custom stream identity.');
    }
    final current = _indexes.putIfAbsent(index, () => _CustomProgress(id));
    if (current.id != id) {
      throw const FormatException('Conflicting custom stream identity.');
    }
    _ids[id] = index;
    return current;
  }

  void observe(JsonObject event) {
    final type = event['type'];
    if (type == 'response.custom_tool_call_input.delta' ||
        type == 'response.custom_tool_call_input.done') {
      _sequence(event);
      final state = _at(event['output_index'], event['item_id']);
      if (state.doneItem != null) {
        throw const FormatException('Custom input after item completion.');
      }
      if (type == 'response.custom_tool_call_input.delta') {
        if (state.doneInput != null || event['delta'] is! String) {
          throw const FormatException('Invalid custom input delta.');
        }
        state.sawDelta = true;
        state.text.write(event['delta']);
      } else {
        if (state.doneInput != null ||
            event['input'] is! String ||
            !_matchesInput(state, event['input'] as String)) {
          throw const FormatException('Invalid custom input completion.');
        }
        state.doneInput = event['input'] as String;
      }
    } else if ((type == 'response.output_item.added' ||
            type == 'response.output_item.done') &&
        event['item'] is Map &&
        (event['item'] as Map)['type'] == 'custom_tool_call') {
      _sequence(event);
      final item = Map<String, Object?>.from(event['item'] as Map);
      final state = _at(event['output_index'], item['id']);
      if (type == 'response.output_item.added') {
        if (state.addedItem != null ||
            state.doneItem != null ||
            state.sawDelta ||
            state.doneInput != null) {
          throw const FormatException('Invalid custom added item.');
        }
        final caller = item['caller'];
        if (item['call_id'] is! String ||
            (item['call_id'] as String).isEmpty ||
            item['name'] is! String ||
            (item['name'] as String).isEmpty ||
            item['input'] is! String ||
            !{'in_progress', 'completed'}.contains(item['status']) ||
            (item.containsKey('namespace') && item['namespace'] is! String) ||
            (item.containsKey('async') && item['async'] != false) ||
            (caller != null &&
                (caller is! Map ||
                    caller['type'] != 'direct' ||
                    caller.length != 1))) {
          throw const FormatException('Invalid custom added item.');
        }
        state.addedItem = item;
      } else {
        if (state.doneItem != null) {
          throw const FormatException('Duplicate custom done item.');
        }
        state.doneItem = item;
      }
    }
  }

  void finish(List<JsonObject> output) {
    for (final entry in _indexes.entries) {
      final index = entry.key, state = entry.value;
      if (index >= output.length) {
        throw const FormatException('Custom stream item missing from output.');
      }
      final item = output[index];
      if (item['type'] != 'custom_tool_call' ||
          item['id'] != state.id ||
          (state.addedItem != null &&
              ['call_id', 'name', 'namespace', 'caller', 'async'].any(
                (key) =>
                    state.addedItem!.containsKey(key) &&
                    !jsonEquals(state.addedItem![key], item[key]),
              )) ||
          (item['input'] is! String ||
              !_matchesInput(state, item['input'] as String)) ||
          (state.doneInput != null && state.doneInput != item['input']) ||
          (state.doneItem != null && !jsonEquals(state.doneItem, item))) {
        throw const FormatException('Custom stream does not match output.');
      }
    }
  }
}
