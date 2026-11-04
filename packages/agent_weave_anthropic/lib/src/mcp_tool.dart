import 'dart:async';
import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';

/// Messages MCP connector wire versions.
enum AnthropicMcpBeta {
  legacy20250404('mcp-client-2025-04-04'),
  client20251120('mcp-client-2025-11-20'),
  client20260915('mcp-client-2026-09-15');

  final String header;
  const AnthropicMcpBeta(this.header);
}

/// Per-tool configuration for an MCP toolset.
final class AnthropicMcpToolConfig {
  final JsonObject definition;

  AnthropicMcpToolConfig({bool? enabled, bool? deferLoading})
    : this.fromJson({'enabled': ?enabled, 'defer_loading': ?deferLoading});

  AnthropicMcpToolConfig.fromJson(JsonObject value)
    : definition = _snapshot(value) {
    for (final key in ['enabled', 'defer_loading']) {
      if (definition.containsKey(key) && definition[key] is! bool) {
        throw ArgumentError('Invalid MCP tool configuration.');
      }
    }
  }
}

/// Tool selection and optional pinned discovery for one MCP server.
final class AnthropicMcpToolset {
  final JsonObject definition;

  AnthropicMcpToolset({
    AnthropicMcpToolConfig? defaultConfig,
    Map<String, AnthropicMcpToolConfig> configs = const {},
    JsonObject? cacheControl,
    List<JsonObject>? tools,
  }) : this.fromJson({
         if (defaultConfig != null) 'default_config': defaultConfig.definition,
         if (configs.isNotEmpty)
           'configs': {
             for (final e in configs.entries) e.key: e.value.definition,
           },
         'cache_control': ?cacheControl,
         'tools': ?tools,
       });

  AnthropicMcpToolset.fromJson(JsonObject value)
    : definition = _snapshot(value) {
    if (definition.containsKey('type') && definition['type'] != 'mcp_toolset') {
      throw ArgumentError('Invalid MCP toolset type.');
    }
    if (definition.containsKey('mcp_server_name') &&
        !_nonempty(definition['mcp_server_name'])) {
      throw ArgumentError('Invalid MCP toolset server name.');
    }
    final defaults = definition['default_config'];
    if (definition.containsKey('default_config')) {
      AnthropicMcpToolConfig.fromJson(_object(defaults));
    }
    final configs = definition['configs'];
    if (configs != null) {
      for (final entry in _object(configs).entries) {
        if (!_nonempty(entry.key)) {
          throw ArgumentError('Invalid MCP tool name.');
        }
        AnthropicMcpToolConfig.fromJson(_object(entry.value));
      }
    }
    final cache = definition['cache_control'];
    if (cache != null) {
      final config = _object(cache);
      if (config['type'] != 'ephemeral' ||
          (config['ttl'] != null && !{'5m', '1h'}.contains(config['ttl']))) {
        throw ArgumentError('Invalid MCP cache control.');
      }
    }
    final tools = definition['tools'];
    if (tools != null) {
      if (tools is! List) throw ArgumentError('Invalid pinned MCP tools.');
      final names = <String>{};
      for (final raw in tools) {
        final tool = _object(raw);
        if (!_nonempty(tool['name']) ||
            !names.add(tool['name'] as String) ||
            (tool['description'] != null && tool['description'] is! String) ||
            tool['input_schema'] is! Map) {
          throw ArgumentError('Invalid pinned MCP tool.');
        }
      }
    }
  }
}

/// An owner-bound server and its provider-managed tool selection.
final class AnthropicMcpServer {
  final String name;
  final AnthropicMcpBeta beta;
  final JsonObject definition;
  final JsonObject? toolsetDefinition;
  final JsonObject contract;
  final FutureOr<String> Function()? _authorizationToken;

  factory AnthropicMcpServer({
    required String name,
    required Uri url,
    required AnthropicMcpBeta beta,
    AnthropicMcpToolset? toolset,
    JsonObject? legacyToolConfiguration,
    String? credentialBindingId,
    FutureOr<String> Function()? authorizationToken,
  }) => AnthropicMcpServer.fromJson(
    {
      'type': 'url',
      'name': name,
      'url': url.toString(),
      'tool_configuration': ?legacyToolConfiguration,
    },
    beta: beta,
    toolset: toolset?.definition,
    credentialBindingId: credentialBindingId,
    authorizationToken: authorizationToken,
  );

  factory AnthropicMcpServer.fromJson(
    JsonObject input, {
    required AnthropicMcpBeta beta,
    JsonObject? toolset,
    String? credentialBindingId,
    FutureOr<String> Function()? authorizationToken,
  }) {
    final json = _copy(input);
    final name = json['name'];
    final url = json['url'];
    if (json['type'] != 'url' || !_nonempty(name) || !_validUrl(url)) {
      throw ArgumentError('Invalid MCP server definition.');
    }
    final rawToken = json.remove('authorization_token');
    if (rawToken != null && rawToken is! String) {
      throw ArgumentError('Invalid MCP authorization.');
    }
    if (rawToken != null && authorizationToken != null) {
      throw ArgumentError('Use literal authorization or a resolver, not both.');
    }
    if ((rawToken != null || authorizationToken != null) &&
        !_nonempty(credentialBindingId)) {
      throw ArgumentError(
        'MCP authorization requires a stable credential binding.',
      );
    }
    if (credentialBindingId != null && !_nonempty(credentialBindingId)) {
      throw ArgumentError('Invalid MCP credential binding.');
    }
    if (rawToken is String) _validateToken(rawToken);
    JsonObject? set;
    if (beta == AnthropicMcpBeta.legacy20250404) {
      if (toolset != null) {
        throw ArgumentError('Legacy MCP does not use toolsets.');
      }
      final legacy = json['tool_configuration'];
      if (legacy != null) {
        final config = _object(legacy);
        if ((config['enabled'] != null && config['enabled'] is! bool) ||
            (config['allowed_tools'] != null &&
                !_stringList(config['allowed_tools']))) {
          throw ArgumentError('Invalid legacy MCP tool configuration.');
        }
      }
    } else {
      if (json['tool_configuration'] != null) {
        throw ArgumentError(
          'Modern MCP does not use legacy tool configuration.',
        );
      }
      json.remove('tool_configuration');
      final value = AnthropicMcpToolset.fromJson(toolset ?? {}).definition;
      if (value['mcp_server_name'] != null &&
          value['mcp_server_name'] != name) {
        throw ArgumentError('MCP toolset server does not match.');
      }
      if (beta != AnthropicMcpBeta.client20260915 && value['tools'] != null) {
        throw ArgumentError('Pinned MCP tools require the 2026 beta.');
      }
      set = _snapshot({
        ...value,
        'type': 'mcp_toolset',
        'mcp_server_name': name,
      });
    }
    final definition = _snapshot(json);
    final contract = _snapshot({
      'v': 1,
      'beta': beta.header,
      'server': definition,
      'toolset': set,
      'credentialBindingId': credentialBindingId,
    });
    return AnthropicMcpServer._(
      name as String,
      beta,
      definition,
      set,
      contract,
      authorizationToken ??
          (rawToken == null ? null : () => rawToken as String),
    );
  }

  AnthropicMcpServer._(
    this.name,
    this.beta,
    this.definition,
    this.toolsetDefinition,
    this.contract,
    this._authorizationToken,
  );

  /// Resolves fresh authorization only when preparing an outbound request.
  Future<JsonObject> resolveDefinition() async {
    if (_authorizationToken == null) return {...definition};
    try {
      final token = await _authorizationToken();
      _validateToken(token);
      return {...definition, 'authorization_token': token};
    } catch (_) {
      throw StateError('MCP authorization resolution failed.');
    }
  }
}

/// Reject duplicate names or incompatible connector beta modes.
void validateAnthropicMcpServers(List<AnthropicMcpServer> servers) {
  final names = <String>{};
  AnthropicMcpBeta? beta;
  for (final server in servers) {
    if (!names.add(server.name) || (beta != null && server.beta != beta)) {
      throw ArgumentError(
        'MCP servers require unique names and one beta mode.',
      );
    }
    beta = server.beta;
  }
}

/// Merge comma-separated header values without dropping unrelated betas.
List<String> mergeAnthropicMcpBetas(
  Iterable<String> existing,
  AnthropicMcpBeta beta,
) {
  final result = <String>{};
  for (final value in existing) {
    for (final item in value.split(',')) {
      final flag = item.trim();
      if (flag.isEmpty) continue;
      if (flag.startsWith('mcp-client-') && flag != beta.header) {
        throw ArgumentError('Conflicting MCP beta headers.');
      }
      result.add(flag);
    }
  }
  result.add(beta.header);
  return List.unmodifiable(result);
}

JsonObject _copy(JsonObject value) =>
    jsonDecode(jsonEncode(value)) as JsonObject;
JsonObject _snapshot(JsonObject value) => immutableJson(_copy(value));
JsonObject _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw ArgumentError('Expected an MCP JSON object.');
  }
  return value;
}

bool _nonempty(Object? value) => value is String && value.trim().isNotEmpty;
bool _stringList(Object? value) =>
    value is List && value.every((v) => v is String);
bool _validUrl(Object? value) {
  if (value is! String || value.contains(RegExp(r'\s'))) return false;
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      !uri.authority.contains('@') &&
      !uri.hasFragment;
}

void _validateToken(String value) {
  if (value.trim().isEmpty || value.contains(RegExp(r'[\r\n\x00]'))) {
    throw ArgumentError('Invalid MCP authorization.');
  }
}
