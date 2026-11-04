import 'dart:convert';
import 'package:agent_weave_anthropic/src/mcp_tool.dart';
import 'package:test/test.dart';

void main() {
  final server = <String, Object?>{
    'type': 'url',
    'name': 'docs',
    'url': 'https://example.com/mcp',
  };
  test('modern options and unknown fields snapshot immutably', () async {
    final options = <String, Object?>{
      'type': 'mcp_toolset',
      'mcp_server_name': 'docs',
      'default_config': {'enabled': false, 'defer_loading': true, 'future': 1},
      'configs': {
        'read': {'enabled': true, 'defer_loading': false},
      },
      'cache_control': {'type': 'ephemeral', 'ttl': '1h'},
      'tools': [
        {
          'name': 'read',
          'description': 'Read',
          'input_schema': {'type': 'object'},
        },
      ],
      'future': {
        'nested': [1],
      },
    };
    final config = AnthropicMcpServer.fromJson(
      {...server, 'future': true},
      beta: AnthropicMcpBeta.client20260915,
      toolset: options,
    );
    (options['future'] as Map)['nested'] = <int>[];
    expect((config.toolsetDefinition!['future'] as Map)['nested'], [1]);
    expect(config.contract['beta'], 'mcp-client-2026-09-15');
    expect(config.definition['future'], true);
    expect(await config.resolveDefinition(), config.definition);
    expect(
      () => (config.toolsetDefinition!['future'] as Map)['nested'] = <int>[],
      throwsUnsupportedError,
    );
  });
  test('typed server and toolset use the same modern wire definition', () {
    final config = AnthropicMcpServer(
      name: 'docs',
      url: Uri.parse('https://example.com/mcp'),
      beta: AnthropicMcpBeta.client20251120,
      toolset: AnthropicMcpToolset(
        defaultConfig: AnthropicMcpToolConfig(enabled: false),
        configs: {
          'read': AnthropicMcpToolConfig(enabled: true, deferLoading: true),
        },
        cacheControl: {'type': 'ephemeral'},
      ),
    );
    expect(config.toolsetDefinition, {
      'type': 'mcp_toolset',
      'mcp_server_name': 'docs',
      'default_config': {'enabled': false},
      'configs': {
        'read': {'enabled': true, 'defer_loading': true},
      },
      'cache_control': {'type': 'ephemeral'},
    });
  });
  test('legacy server config stays distinct', () {
    final config = AnthropicMcpServer.fromJson({
      ...server,
      'tool_configuration': {
        'enabled': true,
        'allowed_tools': ['read'],
        'future': 2,
      },
    }, beta: AnthropicMcpBeta.legacy20250404);
    expect(config.toolsetDefinition, isNull);
    expect((config.definition['tool_configuration'] as Map)['allowed_tools'], [
      'read',
    ]);
    expect(
      () => AnthropicMcpServer.fromJson(
        server,
        beta: AnthropicMcpBeta.legacy20250404,
        toolset: {},
      ),
      throwsArgumentError,
    );
    expect(
      () => AnthropicMcpServer.fromJson(
        config.definition,
        beta: AnthropicMcpBeta.client20251120,
      ),
      throwsArgumentError,
    );
  });
  test('literal and rotating credentials never enter snapshots', () async {
    final literal = AnthropicMcpServer.fromJson(
      {...server, 'authorization_token': 'secret'},
      beta: AnthropicMcpBeta.client20251120,
      credentialBindingId: 'owner',
    );
    expect(jsonEncode(literal.contract), isNot(contains('secret')));
    expect(jsonEncode(literal.definition), isNot(contains('secret')));
    expect(
      (await literal.resolveDefinition())['authorization_token'],
      'secret',
    );
    var token = 'first';
    final dynamic = AnthropicMcpServer.fromJson(
      server,
      beta: AnthropicMcpBeta.client20251120,
      credentialBindingId: 'owner',
      authorizationToken: () async => token,
    );
    expect((await dynamic.resolveDefinition())['authorization_token'], 'first');
    token = 'second';
    expect(
      (await dynamic.resolveDefinition())['authorization_token'],
      'second',
    );
    expect(literal.contract, dynamic.contract);
    final changed = AnthropicMcpServer.fromJson(
      server,
      beta: AnthropicMcpBeta.client20251120,
      credentialBindingId: 'other',
      authorizationToken: () => token,
    );
    expect(changed.contract, isNot(literal.contract));
    final failed = AnthropicMcpServer.fromJson(
      server,
      beta: AnthropicMcpBeta.client20251120,
      credentialBindingId: 'owner',
      authorizationToken: () => throw StateError('private-token'),
    );
    await expectLater(
      failed.resolveDefinition(),
      throwsA(
        predicate(
          (e) => e is StateError && !e.toString().contains('private-token'),
        ),
      ),
    );
  });
  test('rejects malformed, incompatible and ambiguous inputs', () {
    for (final invalid in [
      {...server, 'type': 'other'},
      {...server, 'name': ''},
      {...server, 'url': 'http://example.com'},
      {...server, 'url': 'https://user:secret@example.com'},
      {...server, 'url': 'https://example.com/#secret'},
      {...server, 'url': 'https://example.com/a b'},
      {...server, 'url': 'https://'},
      {...server, 'authorization_token': 1},
      {...server, 'authorization_token': 'secret'},
    ]) {
      expect(
        () => AnthropicMcpServer.fromJson(
          invalid,
          beta: AnthropicMcpBeta.client20251120,
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => AnthropicMcpServer.fromJson(
        {...server, 'authorization_token': 'x'},
        beta: AnthropicMcpBeta.client20251120,
        credentialBindingId: 'id',
        authorizationToken: () => 'y',
      ),
      throwsArgumentError,
    );
    for (final invalid in [
      {'type': 'bad'},
      {
        'default_config': {'enabled': 'yes'},
      },
      {
        'configs': {
          'a': {'defer_loading': 1},
        },
      },
      {
        'cache_control': {'type': 'bad'},
      },
      {
        'tools': [
          {'name': 'a', 'input_schema': <Object?>[]},
        ],
      },
      {
        'tools': [
          {'name': 'a', 'input_schema': <String, Object?>{}},
          {'name': 'a', 'input_schema': <String, Object?>{}},
        ],
      },
    ]) {
      expect(() => AnthropicMcpToolset.fromJson(invalid), throwsArgumentError);
    }
    expect(
      () => AnthropicMcpServer.fromJson(
        server,
        beta: AnthropicMcpBeta.client20251120,
        toolset: {'tools': []},
      ),
      throwsArgumentError,
    );
    expect(
      () => AnthropicMcpServer.fromJson(
        server,
        beta: AnthropicMcpBeta.client20251120,
        toolset: {'mcp_server_name': 'other'},
      ),
      throwsArgumentError,
    );
    expect(
      () => AnthropicMcpServer.fromJson({
        ...server,
        'tool_configuration': {'enabled': 'yes'},
      }, beta: AnthropicMcpBeta.legacy20250404),
      throwsArgumentError,
    );
  });
  test('server collections and beta headers reject conflicts', () {
    AnthropicMcpServer create(String name, AnthropicMcpBeta beta) =>
        AnthropicMcpServer.fromJson({...server, 'name': name}, beta: beta);
    final a = create('a', AnthropicMcpBeta.client20251120);
    validateAnthropicMcpServers([a, create('b', a.beta)]);
    expect(() => validateAnthropicMcpServers([a, a]), throwsArgumentError);
    expect(
      () => validateAnthropicMcpServers([
        a,
        create('b', AnthropicMcpBeta.client20260915),
      ]),
      throwsArgumentError,
    );
    expect(
      mergeAnthropicMcpBetas(['other, mcp-client-2025-11-20', 'other'], a.beta),
      ['other', 'mcp-client-2025-11-20'],
    );
    expect(
      () => mergeAnthropicMcpBetas(['mcp-client-2026-09-15'], a.beta),
      throwsArgumentError,
    );
  });
}
