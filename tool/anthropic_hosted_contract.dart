import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;

// Exercise the public boundary against the independently extracted official pin.
void main() {
  final inventory =
      jsonDecode(File('docs/anthropic-api-inventory.json').readAsStringSync())
          as Map;
  final declarations = inventory['declarations'] as Map;
  final names = (declarations['ToolUnion']['type'] as String).split(' | ');
  final literals = RegExp("'([^']+)'");
  List<String> values(String name, String field) => [
    for (final item in declarations[name]['fields'] as List)
      if ((item as Map)['name'] == field)
        for (final match in literals.allMatches(item['type'] as String))
          match[1]!,
  ];
  var versions = 0;
  for (final name in names) {
    final server = RegExp(
      r'^(WebSearchTool|WebFetchTool|CodeExecutionTool|ToolSearchToolBm25_|ToolSearchToolRegex)',
    ).hasMatch(name);
    final types = values(name, 'type');
    final wireNames = values(name, 'name');
    if (!server) {
      if (!{
        'Tool',
        'ToolBash20250124',
        'BrowserToolset20260801',
        'MemoryTool20250818',
        'ComputerToolset20260801',
        'ToolTextEditor20250124',
        'ToolTextEditor20250429',
        'ToolTextEditor20250728',
      }.contains(name)) {
        throw StateError('Classify new official tool declaration: $name');
      }
      for (final type in types) {
        try {
          api.AnthropicHostedTool.fromJson({
            'type': type,
            'name': wireNames.firstOrNull ?? 'client',
          });
        } on ArgumentError {
          continue;
        }
        throw StateError('Client-executed $type entered hosted path.');
      }
      continue;
    }
    if (types.isEmpty || wireNames.length != 1) {
      throw StateError('Unexpected hosted union: $name');
    }
    for (final type in types) {
      final body = <String, Object?>{
        'type': type,
        'name': wireNames.single,
        'future_native_field': {'value': true},
      };
      final tool = api.AnthropicHostedTool.fromJson(body);
      if (canonicalJson(tool.definition) != canonicalJson(body)) {
        throw StateError('Hosted field loss: $type');
      }
      versions++;
    }
  }
  print(
    'PASS Anthropic hosted contract: $versions official type spellings; client tools excluded. Nested options and live behavior require separate tests.',
  );
}
