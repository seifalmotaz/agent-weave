import 'dart:convert';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;

Future<void> main() async {
  final legacy = api.AnthropicMcpServer.fromJson(
    {
      'type': 'url',
      'name': 'legacy',
      'url': 'https://example.com/mcp',
      'tool_configuration': {
        'enabled': true,
        'allowed_tools': ['read'],
      },
      'authorization_token': 'fixture-token',
    },
    beta: api.AnthropicMcpBeta.legacy20250404,
    credentialBindingId: 'fixture',
  );
  final modern = api.AnthropicMcpServer(
    name: 'modern',
    url: Uri.parse('https://example.com/mcp'),
    beta: api.AnthropicMcpBeta.client20251120,
    toolset: api.AnthropicMcpToolset(
      defaultConfig: api.AnthropicMcpToolConfig(
        enabled: false,
        deferLoading: true,
      ),
      configs: {
        'read': api.AnthropicMcpToolConfig(enabled: true, deferLoading: false),
      },
      cacheControl: {'type': 'ephemeral', 'ttl': '1h'},
    ),
  );
  final pinned = api.AnthropicMcpServer(
    name: 'pinned',
    url: Uri.parse('https://example.com/mcp'),
    beta: api.AnthropicMcpBeta.client20260915,
    toolset: api.AnthropicMcpToolset(
      tools: [
        {
          'name': 'read',
          'description': 'Read',
          'input_schema': {'type': 'object'},
        },
      ],
    ),
  );
  final resolved = await legacy.resolveDefinition();
  if (resolved['authorization_token'] != 'fixture-token' ||
      jsonEncode(legacy.contract).contains('fixture-token')) {
    throw StateError('MCP credential separation failed.');
  }
  print(
    jsonEncode({
      'legacy': legacy.definition,
      'legacyResolvedFields': resolved.keys.toList(),
      'modern': modern.definition,
      'toolset': modern.toolsetDefinition,
      'pinned': pinned.toolsetDefinition,
      'headers': [for (final beta in api.AnthropicMcpBeta.values) beta.header],
    }),
  );
}
