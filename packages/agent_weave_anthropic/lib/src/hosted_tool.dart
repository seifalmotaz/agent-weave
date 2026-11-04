import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart' show snapshotJson;
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as api;

/// A provider-executed tool. It never invokes an application tool executor.
/// Options are snapshotted; unknown option fields remain intact for the API.
final class AnthropicHostedTool {
  final JsonObject definition;
  String get name => definition['name'] as String;

  AnthropicHostedTool(api.BuiltInTool tool) : this.fromJson(tool.toJson());

  AnthropicHostedTool.fromJson(JsonObject definition)
    : definition = snapshotJson(definition) {
    if (this.definition['name'] is! String ||
        !anthropicHostedToolNames.containsKey(this.definition['type']) ||
        anthropicHostedToolNames[this.definition['type']] !=
            this.definition['name'] ||
        this.definition.containsKey('input_schema')) {
      throw ArgumentError('Expected a supported Anthropic hosted tool.');
    }
    if (definition['allowed_domains'] != null &&
        definition['blocked_domains'] != null) {
      throw ArgumentError('Choose allowed_domains or blocked_domains.');
    }
  }
}

// Exact versions from the pinned official Messages contract; client tools such
// as bash, browser, computer and memory must not enter the provider-owned path.
const anthropicHostedToolNames = {
  'web_search_20250305': 'web_search',
  'web_search_20260209': 'web_search',
  'web_search_20260318': 'web_search',
  'web_fetch_20250910': 'web_fetch',
  'web_fetch_20260209': 'web_fetch',
  'web_fetch_20260309': 'web_fetch',
  'web_fetch_20260318': 'web_fetch',
  'code_execution_20250522': 'code_execution',
  'code_execution_20250825': 'code_execution',
  'code_execution_20260120': 'code_execution',
  'code_execution_20260521': 'code_execution',
  'tool_search_tool_regex_20251119': 'tool_search_tool_regex',
  'tool_search_tool_regex': 'tool_search_tool_regex',
  'tool_search_tool_bm25_20251119': 'tool_search_tool_bm25',
  'tool_search_tool_bm25': 'tool_search_tool_bm25',
};

const anthropicHostedResultNames = {
  'web_search_tool_result': {'web_search'},
  'web_fetch_tool_result': {'web_fetch'},
  'code_execution_tool_result': {'code_execution'},
  'bash_code_execution_tool_result': {'bash_code_execution'},
  'text_editor_code_execution_tool_result': {'text_editor_code_execution'},
  'tool_search_tool_result': {
    'tool_search_tool_regex',
    'tool_search_tool_bm25',
  },
};
