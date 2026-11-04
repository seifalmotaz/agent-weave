import 'dart:convert';

import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:test/test.dart';

void main() {
  final base = <String, Object?>{
    'type': 'mcp',
    'server_label': 'docs',
    'server_url': 'https://example.com/mcp',
  };

  test(
    'SDK and native shapes preserve options and immutable snapshots',
    () async {
      final typed = openai.OpenAIMcpTool(
        const openai.McpTool(
          serverLabel: 'docs',
          serverUrl: 'https://example.com/mcp',
          allowedTools: ['search'],
          requireApproval: 'always',
        ),
      );
      expect(typed.definition['allowed_tools'], ['search']);
      final input = {
        ...base,
        'future': {'value': 1},
        'allowed_tools': {
          'read_only': true,
          'tool_names': ['search'],
        },
      };
      final tool = openai.OpenAIMcpTool.fromJson(input);
      (input['future'] as Map)['value'] = 2;
      expect((tool.definition['future'] as Map)['value'], 1);
      expect(
        () => (tool.definition['future'] as Map)['value'] = 3,
        throwsUnsupportedError,
      );
      expect(
        () => (tool.contract['definition'] as Map)['type'] = 'bad',
        throwsUnsupportedError,
      );
      expect(await tool.resolveDefinition(), tool.definition);
      final nullCredentials = openai.OpenAIMcpTool.fromJson({
        ...base,
        'authorization': null,
        'headers': null,
      });
      expect(nullCredentials.definition.containsKey('authorization'), isFalse);
      expect(nullCredentials.definition.containsKey('headers'), isFalse);
      expect(
        await nullCredentials.resolveDefinition(),
        nullCredentials.definition,
      );
      expect(
        openai.OpenAIMcpTool.fromJson({
          ...base,
          'server_url': 'https://example.com/mcp?version=1',
        }).definition['server_url'],
        'https://example.com/mcp?version=1',
      );
    },
  );

  test('literal credentials are isolated and bound to identity', () async {
    final headers = {'X-Key': 'secret-header'};
    final tool = openai.OpenAIMcpTool.fromJson({
      ...base,
      'authorization': 'secret-token',
      'headers': headers,
    }, credentialBindingId: 'account-1');
    headers['X-Key'] = 'changed';
    expect(jsonEncode(tool.definition), isNot(contains('secret')));
    expect(jsonEncode(tool.contract), isNot(contains('secret')));
    expect((await tool.resolveDefinition())['headers'], {
      'X-Key': 'secret-header',
    });
    expect((await tool.resolveDefinition())['authorization'], 'secret-token');
    final other = openai.OpenAIMcpTool.fromJson(
      base,
      credentialBindingId: 'account-2',
    );
    expect(tool.contract, isNot(other.contract));
  });

  test(
    'resolver refreshes credentials each time and snapshots headers',
    () async {
      var token = 'first';
      final headers = {'x': 'old'};
      final frozen = openai.OpenAIMcpCredentials(headers: headers);
      headers['x'] = 'new';
      expect(frozen.headers['x'], 'old');
      final tool = openai.OpenAIMcpTool.fromJson(
        base,
        credentialBindingId: 'account',
        credentials: () async =>
            openai.OpenAIMcpCredentials(authorization: token),
      );
      expect((await tool.resolveDefinition())['authorization'], 'first');
      token = 'second';
      expect((await tool.resolveDefinition())['authorization'], 'second');
      expect(
        jsonDecode(jsonEncode(await tool.resolveDefinition()))['authorization'],
        'second',
      );
      expect(jsonEncode(tool.contract), isNot(contains('second')));
    },
  );

  test('accepts connector, tunnel and approval policy forms', () {
    for (final address in ['connector_id', 'tunnel_id']) {
      for (final approval in [
        'always',
        'never',
        <String, Object?>{},
        {
          'always': {
            'tool_names': ['write'],
          },
          'never': {'read_only': true},
        },
      ]) {
        final tool = openai.OpenAIMcpTool.fromJson({
          'type': 'mcp',
          'server_label': 's',
          address: 'value',
          'require_approval': approval,
        });
        expect(tool.definition['require_approval'], approval);
      }
    }
  });

  test('rejects invalid boundary values and ambiguous credentials', () {
    final invalid = <Map<String, Object?>>[
      {...base, 'type': 'other'},
      {...base, 'server_label': ''},
      {...base, 'server_url': null},
      {...base, 'server_url': 'https://user:secret@example.com/mcp'},
      {...base, 'server_url': 'https://example.com/mcp#secret'},
      {...base, 'server_url': 'ftp://example.com/mcp'},
      {...base, 'server_url': 'https://'},
      {...base, 'server_url': 'https://example.com/a b'},
      {...base, 'allowed_callers': []},
      {
        ...base,
        'allowed_callers': ['unknown'],
      },
      {...base, 'connector_id': 'also'},
      {...base, 'allowed_tools': 2},
      {
        ...base,
        'allowed_tools': {
          'tool_names': [1],
        },
      },
      {...base, 'require_approval': 'sometimes'},
      {
        ...base,
        'require_approval': {
          'never': {'read_only': 1},
        },
      },
      {...base, 'defer_loading': 'yes'},
      {
        ...base,
        'headers': {'x': 1},
      },
      {...base, 'authorization': 'secret'},
    ];
    for (final input in invalid) {
      expect(
        () => openai.OpenAIMcpTool.fromJson(input),
        throwsArgumentError,
        reason: '$input',
      );
    }
    expect(
      () => openai.OpenAIMcpTool.fromJson(
        {...base, 'authorization': 'x'},
        credentialBindingId: 'id',
        credentials: () => openai.OpenAIMcpCredentials(),
      ),
      throwsArgumentError,
    );
  });
}
