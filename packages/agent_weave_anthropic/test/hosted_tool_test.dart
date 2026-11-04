import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;
import 'package:test/test.dart';
import 'chat_test.dart' as f;

final search = api.AnthropicHostedTool(const api.WebSearchTool(maxUses: 2));
final code = api.AnthropicHostedTool(api.CodeExecutionBuiltInTool());
Map<String, Object?> server(
  String id, {
  String name = 'web_search',
  Object? input = const <String, Object?>{},
}) => {
  'type': 'server_tool_use',
  'id': id,
  'name': name,
  'input': input,
  'caller': {'type': 'direct'},
  'unknown': 42,
};
Map<String, Object?> result(
  String id, {
  String type = 'web_search_tool_result',
}) => {
  'type': type,
  'tool_use_id': id,
  'content': {'type': 'fixture_error', 'error_code': 'fixture'},
};
List<JsonObject> response(
  List<JsonObject> content, {
  String reason = 'end_turn',
  Object? container,
}) => [
  f.start(),
  for (var i = 0; i < content.length; i++) ...[
    f.block(i, content[i]),
    f.stop(i),
  ],
  {
    'type': 'message_delta',
    'delta': {'stop_reason': reason, 'container': container},
    'usage': {'output_tokens': 3},
  },
  f.done,
];
Future<List<ModelEvent>> invoke(
  List<JsonObject> frames, {
  ModelRequest? request,
  List<api.AnthropicHostedTool>? tools,
  JsonObject Function(JsonObject)? configure,
  Map<String, JsonObject> functionToolOptions = const {},
  void Function(JsonObject)? sent,
}) async =>
    api.AnthropicProtocolModel(
          model: 'fixture',
          authorityBindingId: 'fixture-authority',
          functionToolOptions: functionToolOptions,
          hostedTools: tools ?? [search],
          configure: configure,
          transport: (body, _) async* {
            sent?.call(body);
            yield* Stream.fromIterable(frames);
          },
        )
        .stream(
          request ?? ModelRequest(messages: []),
          cancellation: CancellationToken(),
        )
        .toList();
ChatMessage history(List<ModelEvent> events) => ChatMessage(
  id: 'a',
  role: MessageRole.assistant,
  toolCalls: [for (final e in events.whereType<ToolCallReady>()) e.call],
  providerData: {
    for (final e in events.whereType<ProviderOutput>()) e.provider: e.items,
  },
);

void main() {
  test('hosted SDK options snapshot; unknown native options survive', () {
    final domains = ['example.com'];
    final tool = api.AnthropicHostedTool(
      api.WebSearchTool(allowedDomains: domains),
    );
    domains.add('changed.com');
    expect(tool.definition['allowed_domains'], ['example.com']);
    expect(
      () => (tool.definition['allowed_domains'] as List).add('no'),
      throwsUnsupportedError,
    );
    final raw = api.AnthropicHostedTool.fromJson({
      'type': 'web_search_20260318',
      'name': 'web_search',
      'future': {'nested': true},
    });
    expect((raw.definition['future'] as Map)['nested'], true);
    for (final invalid in <JsonObject>[
      {},
      {'type': 'bash_20250124', 'name': 'bash'},
      {'type': 'web_search_20250305', 'name': 'other'},
      {'type': 'web_search_20250305', 'name': 'web_search', 'input_schema': {}},
      {
        'type': 'web_search_20250305',
        'name': 'web_search',
        'allowed_domains': [],
        'blocked_domains': [],
      },
    ]) {
      expect(
        () => api.AnthropicHostedTool.fromJson(invalid),
        throwsArgumentError,
      );
    }
  });

  test(
    'every pinned hosted result family retains raw data without local calls',
    () async {
      for (final (name, type, tools) in [
        ('web_search', 'web_search_tool_result', [search]),
        (
          'web_fetch',
          'web_fetch_tool_result',
          [api.AnthropicHostedTool(api.WebFetchTool())],
        ),
        ('code_execution', 'code_execution_tool_result', [code]),
        ('bash_code_execution', 'bash_code_execution_tool_result', [code]),
        (
          'text_editor_code_execution',
          'text_editor_code_execution_tool_result',
          [code],
        ),
        (
          'tool_search_tool_regex',
          'tool_search_tool_result',
          [
            api.AnthropicHostedTool.fromJson({
              'type': 'tool_search_tool_regex_20251119',
              'name': 'tool_search_tool_regex',
            }),
          ],
        ),
      ]) {
        final blocks = [
          server('s', name: name, input: ['opaque']),
          result('s', type: type),
          {'type': 'container_upload', 'file_id': 'file', 'unknown': 5},
        ];
        final events = await invoke(response(blocks), tools: tools);
        expect(events.whereType<ToolCallReady>(), isEmpty);
        expect(events.whereType<NativeToolCallReady>(), isEmpty);
        expect(events.whereType<ProviderOutput>().first.items, blocks);
        expect(
          events.last,
          isA<ModelFinished>().having(
            (v) => v.continueTurn,
            'continuation',
            false,
          ),
        );
      }
    },
  );

  test(
    'server JSON deltas complete without producing an application call',
    () async {
      final frames = [
        f.start(),
        f.block(0, server('s')),
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"q":'},
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'input_json_delta', 'partial_json': '"search"}'},
        },
        f.stop(0),
        f.block(1, result('s')),
        f.stop(1),
        f.finish('end_turn'),
        f.done,
      ];
      final events = await invoke(frames);
      expect(events.whereType<ProviderOutput>().first.items.first['input'], {
        'q': 'search',
      });
      expect(events.whereType<ToolCallReady>(), isEmpty);
    },
  );

  test(
    'paused container and exact tools survive native continuation',
    () async {
      final paused = await invoke(
        response(
          [server('s')],
          reason: 'pause_turn',
          container: {'id': 'container', 'unknown': true},
        ),
      );
      expect((paused.last as ModelFinished).continueTurn, true);
      JsonObject? sent;
      await invoke(
        response([result('s')]),
        request: ModelRequest(messages: [history(paused)]),
        sent: (body) => sent = body,
      );
      expect(sent!['container'], 'container');
      expect(
        (sent!['messages'] as List).single['content'],
        history(paused).providerData['anthropic.messages'],
      );
      for (final configure in <JsonObject Function(JsonObject)>[
        (body) => {...body, 'container': 'different'},
        (body) => {...body, 'container': null},
        (body) => {
          ...body,
          'tools': [
            {
              'type': 'web_search_20250305',
              'name': 'web_search',
              'max_uses': 99,
            },
          ],
        },
      ]) {
        await expectLater(
          invoke(
            response([result('s')]),
            request: ModelRequest(messages: [history(paused)]),
            configure: configure,
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        invoke(
          response([result('s')]),
          request: ModelRequest(messages: [history(paused)]),
          tools: [],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'hosted definitions cannot collide with each other or local tools',
    () async {
      await expectLater(
        invoke(response([]), tools: [search, search]),
        throwsArgumentError,
      );
      await expectLater(
        invoke(
          response([]),
          request: ModelRequest(
            messages: [],
            tools: [
              FunctionModelTool(
                name: 'web_search',
                description: 'Local',
                inputSchema: {'type': 'object'},
              ),
            ],
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'invalid hosted references and terminal state fail before any call is emitted',
    () async {
      for (final blocks in <List<JsonObject>>[
        [result('missing')],
        [server('s'), result('s'), result('s')],
        [server('s'), result('s', type: 'web_fetch_tool_result')],
        [server('s')],
        [server('s'), server('s')],
        [server('s', name: 'unknown')],
        [
          {
            'type': 'mcp_tool_use',
            'id': 'mcp',
            'name': 'tool',
            'input': <String, Object?>{},
          },
        ],
      ]) {
        await expectLater(
          invoke(response(blocks)),
          throwsA(anyOf(isA<FormatException>(), isA<UnsupportedError>())),
        );
      }
      final clientCall = {
        'type': 'tool_use',
        'id': 'local',
        'name': 'local',
        'input': <String, Object?>{},
      };
      await expectLater(
        invoke(response([clientCall], reason: 'pause_turn')),
        throwsFormatException,
      );
      await expectLater(
        invoke(response([server('s'), result('s')]), tools: []),
        throwsFormatException,
      );
    },
  );

  test(
    'mixed tool history requires every client result and no user text',
    () async {
      final blocks = [
        server('s'),
        {
          'type': 'tool_use',
          'id': 'local',
          'name': 'local',
          'input': <String, Object?>{},
        },
      ];
      final mixed = await invoke(response(blocks, reason: 'tool_use'));
      for (final content in [
        [ChatMessage.user('Injected', id: 'u')],
        [
          ChatMessage(
            id: 'r',
            role: MessageRole.tool,
            toolCallId: 'wrong',
            content: [const TextPart('ok')],
          ),
        ],
        [
          ChatMessage(
            id: 'r',
            role: MessageRole.tool,
            toolCallId: 'local',
            content: [const TextPart('ok')],
          ),
          ChatMessage.user('Injected', id: 'u'),
        ],
      ]) {
        await expectLater(
          invoke(
            response([result('s')]),
            request: ModelRequest(messages: [history(mixed), ...content]),
          ),
          throwsFormatException,
        );
      }
      await invoke(
        response([result('s')]),
        request: ModelRequest(
          messages: [
            history(mixed),
            ChatMessage(
              id: 'r',
              role: MessageRole.tool,
              toolCallId: 'local',
              content: [const TextPart('ok')],
            ),
          ],
        ),
      );
    },
  );

  test(
    'programmatic calls require an opted-in local tool and active code ID',
    () async {
      final request = ModelRequest(
        messages: [],
        tools: [
          FunctionModelTool(
            name: 'local',
            description: 'Local',
            inputSchema: {'type': 'object'},
          ),
        ],
      );
      final blocks = [
        server('code', name: 'code_execution'),
        {
          'type': 'tool_use',
          'id': 'local-call',
          'name': 'local',
          'input': <String, Object?>{},
          'caller': {'type': 'code_execution_20260120', 'tool_id': 'code'},
        },
      ];
      await expectLater(
        invoke(
          response(blocks, reason: 'tool_use', container: {'id': 'c'}),
          request: request,
          tools: [code],
        ),
        throwsFormatException,
      );
      final events = await invoke(
        response(blocks, reason: 'tool_use', container: {'id': 'c'}),
        request: request,
        tools: [code],
        functionToolOptions: const {
          'local': {
            'allowed_callers': ['code_execution_20260120'],
            'defer_loading': true,
          },
        },
      );
      expect(events.whereType<ToolCallReady>().single.call.name, 'local');
      final bad = [
        server('code', name: 'code_execution'),
        result('code', type: 'code_execution_tool_result'),
        blocks.last,
      ];
      await expectLater(
        invoke(
          response(bad, reason: 'tool_use'),
          request: request,
          tools: [code],
          functionToolOptions: const {
            'local': {
              'allowed_callers': ['code_execution_20260120'],
            },
          },
        ),
        throwsFormatException,
      );
    },
  );

  test('completed server IDs cannot be reused on later turns', () async {
    final events = await invoke(response([server('s'), result('s')]));
    await expectLater(
      invoke(
        response([server('s'), result('s')]),
        request: ModelRequest(messages: [history(events)]),
      ),
      throwsFormatException,
    );
    expect(
      jsonEncode(
        chatHydration({
          'messages': [history(events).toJson()],
        }),
      ),
      isNot(contains('anthropic.messages')),
    );
  });
  test(
    'new caller option alias accepts canonical response tag and requires container',
    () async {
      final request = ModelRequest(
        messages: [],
        tools: [
          FunctionModelTool(
            name: 'local',
            description: 'Local',
            inputSchema: {'type': 'object'},
          ),
        ],
      );
      final blocks = [
        server('code', name: 'code_execution'),
        <String, Object?>{
          'type': 'tool_use',
          'id': 'local',
          'name': 'local',
          'input': <String, Object?>{},
          'caller': {'type': 'code_execution_20260120', 'tool_id': 'code'},
        },
      ];
      const functionOptions = <String, JsonObject>{
        'local': {
          'allowed_callers': ['code_execution_20260521'],
        },
      };
      final tools = [
        api.AnthropicHostedTool.fromJson({
          'type': 'code_execution_20260521',
          'name': 'code_execution',
        }),
      ];
      final events = await invoke(
        response(blocks, reason: 'tool_use', container: {'id': 'c'}),
        request: request,
        tools: tools,
        functionToolOptions: functionOptions,
      );
      expect(events.whereType<ToolCallReady>(), hasLength(1));
      await expectLater(
        invoke(
          response(blocks, reason: 'tool_use'),
          request: request,
          tools: tools,
          functionToolOptions: functionOptions,
        ),
        throwsFormatException,
      );
    },
  );
}
