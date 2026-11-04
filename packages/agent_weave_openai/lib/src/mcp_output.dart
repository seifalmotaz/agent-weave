import 'dart:convert';
import 'dart:math';

import 'package:agent_weave/agent_weave.dart';
import 'mcp_tool.dart';

const _mcpTypes = {
  'mcp_approval_request',
  'mcp_approval_response',
  'mcp_call',
  'mcp_list_tools',
};

void validateMcpTools(List<OpenAIMcpTool> tools) {
  final labels = <Object?>{};
  for (final tool in tools) {
    if (!labels.add(tool.definition['server_label'])) {
      throw ArgumentError('MCP server labels must be unique.');
    }
  }
}

OpenAIMcpTool mcpToolFor(List<OpenAIMcpTool> tools, String label) =>
    tools.firstWhere(
      (tool) => tool.definition['server_label'] == label,
      orElse: () => throw const FormatException('Unconfigured MCP server.'),
    );

JsonObject _arguments(JsonObject item) {
  if (item['arguments'] is! String) {
    throw const FormatException('MCP arguments must be a JSON string.');
  }
  final value = jsonDecode(item['arguments'] as String);
  if (value is! JsonObject) {
    throw const FormatException('MCP arguments must describe an object.');
  }
  return immutableJson(value);
}

void _validate(
  JsonObject item,
  List<OpenAIMcpTool> tools, [
  List<ProviderApprovalDecision> decisions = const [],
]) {
  final type = item['type'];
  if (!_mcpTypes.contains(type) ||
      item['id'] is! String ||
      (item['id'] as String).trim().isEmpty) {
    throw const FormatException('Invalid MCP output item.');
  }
  if (type == 'mcp_approval_response') {
    final matches = decisions
        .where(
          (decision) =>
              decision.provider == 'openai.responses' &&
              decision.providerRequestId == item['approval_request_id'],
        )
        .toList();
    if (matches.length != 1 ||
        item['approve'] != matches.single.approved ||
        (item['reason'] != null && item['reason'] != matches.single.reason)) {
      throw const FormatException('Uncorrelated MCP approval response.');
    }
    return;
  }
  if (item['server_label'] is! String) {
    throw const FormatException('MCP output requires a server label.');
  }
  mcpToolFor(tools, item['server_label'] as String);
  if (type == 'mcp_list_tools') {
    if (item['tools'] is! List ||
        (item['error'] != null && item['error'] is! String)) {
      throw const FormatException('Invalid MCP tool discovery result.');
    }
    final names = <Object?>{};
    for (final tool in item['tools'] as List) {
      if (tool is! Map ||
          tool['name'] is! String ||
          (tool['name'] as String).isEmpty ||
          !names.add(tool['name']) ||
          !tool.containsKey('input_schema')) {
        throw const FormatException('Invalid MCP tool descriptor.');
      }
    }
  } else {
    if (item['name'] is! String || (item['name'] as String).trim().isEmpty) {
      throw const FormatException('MCP tool name is required.');
    }
    _arguments(item);
    if (type == 'mcp_call' &&
        ((item['status'] != null &&
                !{
                  'completed',
                  'failed',
                  'incomplete',
                }.contains(item['status'])) ||
            (item['output'] != null && item['output'] is! String) ||
            (item['approval_request_id'] != null &&
                item['approval_request_id'] is! String) ||
            (item['error'] != null &&
                item['error'] is! String &&
                item['error'] is! Map))) {
      throw const FormatException(
        'Invalid or unfinished MCP execution result.',
      );
    }
  }
}

/// Reconcile provider-owned output before exposing any approval or local call.
final class McpOutput {
  final List<OpenAIMcpTool> tools;
  final _added = <int, JsonObject>{};
  final _done = <int, JsonObject>{};
  final _argumentDeltas = <int, StringBuffer>{};
  final _argumentDone = <int, String>{};
  final _itemIds = <int, String>{};
  final _progress = <int, String>{};
  final List<ProviderApprovalDecision> decisions;
  McpOutput(this.tools, this.decisions);

  void observe(JsonObject event) {
    final type = event['type'];
    if (type == 'response.output_item.added' ||
        type == 'response.output_item.done') {
      final item = event['item'];
      if (item is! JsonObject || !_mcpTypes.contains(item['type'])) return;
      final index = _index(event);
      final target = type == 'response.output_item.added' ? _added : _done;
      if (target.containsKey(index)) {
        throw const FormatException('Duplicate MCP item event.');
      }
      target[index] = immutableJson(item);
    } else if (type is String && type.startsWith('response.mcp_')) {
      final index = _index(event);
      if (event['item_id'] is! String ||
          (event['item_id'] as String).isEmpty ||
          (_itemIds[index] != null && _itemIds[index] != event['item_id'])) {
        throw const FormatException('MCP event item ID mismatch.');
      }
      _itemIds[index] = event['item_id'] as String;
      if (type == 'response.mcp_call_arguments.delta') {
        if (_argumentDone.containsKey(index) || event['delta'] is! String) {
          throw const FormatException('Invalid MCP argument delta.');
        }
        _argumentDeltas
            .putIfAbsent(index, StringBuffer.new)
            .write(event['delta']);
      } else if (type == 'response.mcp_call_arguments.done') {
        if (_argumentDone.containsKey(index) ||
            event['arguments'] is! String ||
            (_argumentDeltas[index] != null &&
                _argumentDeltas[index].toString() != event['arguments'])) {
          throw const FormatException('MCP argument stream mismatch.');
        }
        _argumentDone[index] = event['arguments'] as String;
      } else if ({
        'response.mcp_call.in_progress',
        'response.mcp_call.completed',
        'response.mcp_call.failed',
        'response.mcp_list_tools.in_progress',
        'response.mcp_list_tools.completed',
        'response.mcp_list_tools.failed',
      }.contains(type)) {
        final status = type.split('.').last;
        if (_progress[index] == 'completed' || _progress[index] == 'failed') {
          throw const FormatException('MCP progress after terminal.');
        }
        _progress[index] = status;
      } else {
        throw UnsupportedError('Unsupported MCP stream event.');
      }
    }
  }

  int _index(JsonObject event) {
    final index = event['output_index'];
    if (index is! int || index < 0) {
      throw const FormatException('Invalid MCP output index.');
    }
    return index;
  }

  void finish(List<JsonObject> output, {required bool completed}) {
    for (final index in {..._added.keys, ..._done.keys, ..._itemIds.keys}) {
      if (index >= output.length ||
          !_mcpTypes.contains(output[index]['type'])) {
        throw const FormatException('MCP event absent from terminal output.');
      }
      final item = output[index];
      final prior = _added[index];
      if (prior != null) {
        for (final key in ['id', 'type', 'server_label', 'name']) {
          if (prior[key] != null && prior[key] != item[key]) {
            throw const FormatException(
              'MCP added item differs from terminal.',
            );
          }
        }
      }
      if ((_done[index] != null && !jsonEquals(_done[index], item)) ||
          (_itemIds[index] != null && _itemIds[index] != item['id']) ||
          (_argumentDone[index] != null &&
              _argumentDone[index] != item['arguments']) ||
          (_argumentDeltas[index] != null &&
              _argumentDeltas[index].toString() != item['arguments']) ||
          (_progress[index] == 'failed' && item['status'] == 'completed') ||
          (_progress[index] == 'completed' && item['status'] == 'failed')) {
        throw const FormatException(
          'MCP streamed output differs from terminal.',
        );
      }
    }
    for (final item in output.where(
      (item) => _mcpTypes.contains(item['type']),
    )) {
      if (!completed) {
        throw const FormatException('MCP requires a completed response.');
      }
      _validate(item, tools, decisions);
    }
  }

  ProviderApprovalCall approval(JsonObject item) => ProviderApprovalCall(
    id: _localId(),
    name: item['name'] as String,
    arguments: _arguments(item),
    provider: 'openai.responses',
    serverLabel: item['server_label'] as String,
    providerRequestId: item['id'] as String,
  );
}

final _random = Random.secure();
String _localId() =>
    'mcp_${List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

/// Place private decisions immediately after their authoritative source turn.
final class McpHistory {
  final List<OpenAIMcpTool> tools;
  final List<ProviderApprovalDecision> decisions;
  final _seen = <String>{};
  final _requests = <String>{};
  McpHistory(this.tools, Iterable<ProviderApprovalDecision> decisions)
    : decisions = List.unmodifiable(decisions);

  List<JsonObject> replay(ChatMessage message, List<JsonObject> items) {
    final calls = message.toolCalls.whereType<ProviderApprovalCall>().toList();
    final requests = items
        .where((item) => item['type'] == 'mcp_approval_request')
        .toList();
    for (final item in items.where(
      (item) => _mcpTypes.contains(item['type']),
    )) {
      _validate(item, tools, decisions);
    }
    if (calls.length != requests.length) {
      throw const FormatException(
        'MCP replay does not match pending approvals.',
      );
    }
    final result = <JsonObject>[
      // Decisions were already sent after the source turn; keep echoes only in audit.
      ...items.where((item) => item['type'] != 'mcp_approval_response'),
    ];
    for (final item in requests) {
      final id = item['id'] as String;
      if (!_requests.add(id)) {
        throw const FormatException('Duplicate MCP replay request ID.');
      }
      final call = calls.where((call) => call.providerRequestId == id).single;
      if (call.provider != 'openai.responses' ||
          call.serverLabel != item['server_label'] ||
          call.name != item['name'] ||
          !jsonEquals(call.arguments, _arguments(item))) {
        throw const FormatException('MCP approval replay mismatch.');
      }
      final answer = decisions
          .where(
            (decision) =>
                decision.provider == 'openai.responses' &&
                decision.providerRequestId == id,
          )
          .toList();
      if (answer.length != 1 || !_seen.add(id)) {
        throw const FormatException(
          'MCP approval requires exactly one decision.',
        );
      }
      result.add({
        'type': 'mcp_approval_response',
        'approval_request_id': id,
        'approve': answer.single.approved,
        if (answer.single.reason != null) 'reason': answer.single.reason,
      });
    }
    return result;
  }

  void finish() {
    if (decisions.any(
          (decision) =>
              decision.provider != 'openai.responses' ||
              !_seen.contains(decision.providerRequestId),
        ) ||
        _seen.length != decisions.length) {
      throw const FormatException('Orphaned or duplicate MCP decision.');
    }
  }
}
