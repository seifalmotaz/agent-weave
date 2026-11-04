import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

JsonObject custom({String input = 'α\nplain', String? namespace}) => {
  'type': 'custom_tool_call',
  'id': 'item-1',
  'call_id': 'call-1',
  'name': 'execute',
  'input': input,
  'status': 'completed',
  'namespace': ?namespace,
  'private_field': 'secret',
};
JsonObject terminal(List<JsonObject> output) => {
  'type': 'response.completed',
  'response': {'status': 'completed', 'output': output},
};

final class RawNativeTool implements AgentTool<void> {
  @override
  final NativeModelTool definition;
  RawNativeTool(JsonObject raw)
    : definition = NativeModelTool(
        name: 'local',
        description: 'fixture',
        inputSchema: const {'type': 'object'},
        provider: 'openai.responses',
        definition: raw,
        bindingId: 'fixture',
      );
  @override
  bool get clientExecuted => false;
  @override
  bool get needsApproval => false;
  @override
  JsonObject? get outputSchema => null;
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<void> context) async =>
      throw StateError('Must not execute');
}

void main() {
  test(
    'named custom choices allow documented top-level identity only',
    () async {
      final top = openai.OpenAICustomTool<void>(
        name: 'execute',
        bindingId: 'top',
        execute: (_, _) => openai.OpenAICustomToolResult.text('ok'),
      );
      final namespaced = openai.OpenAICustomTool<void>(
        name: 'execute',
        localName: 'ns_execute',
        namespace: openai.OpenAIToolNamespace(
          name: 'sandbox',
          description: 'Sandbox',
        ),
        bindingId: 'ns',
        execute: (_, _) => openai.OpenAICustomToolResult.text('ok'),
      );
      for (final typed in [false, true]) {
        openai.ResponsesProtocolModel model(Object choice) => typed
            ? openai.ResponsesProtocolModel(
                model: 'fixture',
                toolChoice: choice,
                transport: (_, _) => Stream.fromIterable([terminal([])]),
              )
            : openai.ResponsesProtocolModel.native(
                model: 'fixture',
                toolChoice: choice,
                transport: (_, _) => Stream.fromIterable([terminal([])]),
              );
        for (final choice in <JsonObject>[
          {'type': 'custom', 'name': 'execute', 'namespace': 'sandbox'},
          {'type': 'custom', 'name': 'execute', 'namespace': null},
          {
            'type': 'allowed_tools',
            'mode': 'auto',
            'tools': [
              {'type': 'custom', 'name': 'execute', 'namespace': 'sandbox'},
            ],
          },
        ]) {
          expect(
            () => AiAgent<void>(model: model(choice), tools: [top, namespaced]),
            throwsArgumentError,
          );
        }
        if (typed) {
          expect(
            () => AiAgent<void>(
              model: model({'type': 'custom', 'name': 'execute'}),
              tools: [top, namespaced],
            ),
            throwsA(
              isA<UnsupportedError>().having(
                (error) => error.message,
                'message',
                contains('ResponsesProtocolModel.native'),
              ),
            ),
          );
        } else {
          final agent = AiAgent<void>(
            model: model({'type': 'custom', 'name': 'execute'}),
            tools: [top, namespaced],
          );
          final result = await agent.generate(
            ChatRequest(
              threadId: 't',
              runId: 'r',
              messages: [ChatMessage.user('hi', id: 'u')],
            ),
            ownerId: 'o',
            context: null,
          );
          expect(result.status, RunStatus.completed);
        }
        expect(
          () => AiAgent<void>(
            model: model({'type': 'custom', 'name': 'execute'}),
            tools: [namespaced],
          ),
          throwsArgumentError,
        );
      }
    },
  );
  test(
    'completed custom history rejects forged replay and duplicate results',
    () async {
      var sent = 0;
      final model = openai.ResponsesProtocolModel.native(
        model: 'fixture',
        transport: (_, _) {
          sent++;
          return Stream.fromIterable([terminal([])]);
        },
      );
      ChatMessage assistant(JsonObject item) => ChatMessage(
        id: 'a',
        role: MessageRole.assistant,
        toolCalls: [
          NativeToolCall(
            id: 'call-1',
            name: 'old-alias',
            arguments: {'input': 'α\nplain'},
            provider: 'openai.responses',
          ),
        ],
        providerData: {
          'openai.responses': [item],
        },
      );
      ChatMessage result(String id) => ChatMessage(
        id: id,
        role: MessageRole.tool,
        toolCallId: 'call-1',
        content: [const TextPart('{"output":"ok","isError":false}')],
      );
      for (final messages in [
        [assistant(custom(input: 'forged')), result('r')],
        [assistant(custom()), result('r'), result('r2')],
        [result('r'), assistant(custom())],
      ]) {
        await expectLater(
          model
              .stream(
                ModelRequest(messages: messages),
                cancellation: CancellationToken(),
              )
              .toList(),
          throwsFormatException,
        );
      }
      expect(sent, 0);
    },
  );
  test(
    'completed custom history survives removal, alias changes and function reuse',
    () async {
      for (final variation in ['removed', 'alias', 'function']) {
        final store = MemoryRunStore();
        final bodies = <JsonObject>[];
        var effects = 0;
        final model = openai.ResponsesProtocolModel.native(
          model: 'fixture',
          transport: (body, _) {
            bodies.add(body);
            return Stream.fromIterable([
              terminal(bodies.length == 1 ? [custom()] : []),
            ]);
          },
        );
        AgentTool<void> customTool(String alias) =>
            openai.OpenAICustomTool<void>(
              name: 'execute',
              localName: alias,
              bindingId: 'local',
              execute: (_, _) {
                effects++;
                return openai.OpenAICustomToolResult.text('ok');
              },
            );
        final first = AiAgent<void>(
          store: store,
          model: model,
          tools: [customTool('execute')],
        );
        await first.generate(
          ChatRequest(
            threadId: 't',
            runId: 'r1',
            messages: [ChatMessage.user('hi', id: 'u1')],
          ),
          ownerId: 'o',
          context: null,
        );
        expect(effects, 1);
        expect(bodies.length, 2);
        final tools = <AgentTool<void>>[
          if (variation == 'alias') customTool('renamed'),
          if (variation == 'function')
            Tool<int, int, void>(
              name: 'execute',
              description: 'new function',
              inputSchema: const {'type': 'object'},
              decode: (_) => 1,
              encode: (v) => v,
              execute: (v, _) {
                effects++;
                return v;
              },
            ),
        ];
        final next = AiAgent<void>(store: store, model: model, tools: tools);
        final result = await next.generate(
          ChatRequest(
            threadId: 't',
            runId: 'r2',
            parentRunId: 'r1',
            messages: [ChatMessage.user('next', id: 'u2')],
          ),
          ownerId: 'o',
          context: null,
        );
        expect(result.status, RunStatus.completed);
        expect(effects, 1);
        expect(bodies.length, 3);
        final input = bodies.last['input'] as List;
        expect(
          input.whereType<Map<String, Object?>>().singleWhere(
            (e) => e['type'] == 'custom_tool_call',
          ),
          custom(),
        );
        expect(
          input.whereType<Map<String, Object?>>().singleWhere(
            (e) => e['type'] == 'custom_tool_call_output',
          )['output'],
          'ok',
        );
      }
    },
  );
  test('invalid custom sequence and added metadata never execute', () async {
    JsonObject delta(Object? sequence) => {
      'type': 'response.custom_tool_call_input.delta',
      'item_id': 'item-1',
      'output_index': 0,
      'delta': 'α\nplain',
      if (sequence != 'missing') 'sequence_number': sequence,
    };
    JsonObject added(JsonObject patch) => {
      'type': 'response.output_item.added',
      'sequence_number': 0,
      'output_index': 0,
      'item': {
        'type': 'custom_tool_call',
        'id': 'item-1',
        'call_id': 'call-1',
        'name': 'execute',
        'input': '',
        'status': 'in_progress',
        ...patch,
      },
    };
    for (final events in <List<JsonObject>>[
      [
        delta('missing'),
        terminal([custom()]),
      ],
      [
        delta(-1),
        terminal([custom()]),
      ],
      [
        delta(0.5),
        terminal([custom()]),
      ],
      [
        delta(2),
        delta(1),
        terminal([custom()]),
      ],
      [
        added({'input': 42}),
        terminal([custom()]),
      ],
      [
        added({'async': true}),
        terminal([custom()]),
      ],
      [
        added({
          'caller': {'type': 'program', 'caller_id': 'x'},
        }),
        terminal([custom()]),
      ],
      [
        added({
          'caller': {'type': 'direct'},
        }),
        terminal([custom()]),
      ],
      [
        added({'input': 'wrong'}),
        terminal([custom()]),
      ],
    ]) {
      var effects = 0;
      final model = openai.ResponsesProtocolModel.native(
        model: 'fixture',
        transport: (_, _) => Stream.fromIterable(events),
      );
      final agent = AiAgent<void>(
        model: model,
        tools: [
          openai.OpenAICustomTool<void>(
            name: 'execute',
            bindingId: 'local',
            execute: (_, _) {
              effects++;
              return openai.OpenAICustomToolResult.text('ok');
            },
          ),
        ],
      );
      await expectLater(
        agent.generate(
          ChatRequest(
            threadId: 't',
            runId: 'r',
            messages: [ChatMessage.user('hi', id: 'u')],
          ),
          ownerId: 'o',
          context: null,
        ),
        throwsA(isA<AgentRunException>()),
      );
      expect(effects, 0);
    }
  });
  test('added input prefix and remaining deltas reconcile', () async {
    var effects = 0;
    final model = openai.ResponsesProtocolModel.native(
      model: 'fixture',
      transport: (_, _) => Stream.fromIterable([
        {
          'type': 'response.output_item.added',
          'output_index': 0,
          'sequence_number': 1,
          'item': {
            'type': 'custom_tool_call',
            'id': 'item-1',
            'call_id': 'call-1',
            'name': 'execute',
            'input': 'α\n',
            'status': 'in_progress',
          },
        },
        {
          'type': 'response.custom_tool_call_input.delta',
          'output_index': 0,
          'sequence_number': 3,
          'item_id': 'item-1',
          'delta': 'plain',
        },
        {
          'type': 'response.custom_tool_call_input.done',
          'output_index': 0,
          'sequence_number': 5,
          'item_id': 'item-1',
          'input': 'α\nplain',
        },
        terminal([custom()]),
      ]),
    );
    final events = await model
        .stream(
          ModelRequest(
            messages: [],
            tools: [
              openai.OpenAICustomTool<void>(
                name: 'execute',
                bindingId: 'local',
                execute: (_, _) {
                  effects++;
                  return openai.OpenAICustomToolResult.text('ok');
                },
              ).definition,
            ],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    expect(events.whereType<NativeToolCallReady>().single.call.arguments, {
      'input': 'α\nplain',
    });
    expect(effects, 0);
  });
  test('explicit null result caller survives native replay', () async {
    final requests = <JsonObject>[];
    final model = openai.ResponsesProtocolModel.native(
      model: 'fixture',
      transport: (body, _) {
        requests.add(body);
        return Stream.fromIterable([
          terminal(requests.length == 1 ? [custom()] : []),
        ]);
      },
    );
    final agent = AiAgent<void>(
      model: model,
      tools: [
        openai.OpenAICustomTool<void>(
          name: 'execute',
          bindingId: 'local',
          execute: (_, _) => openai.OpenAICustomToolResult.fromJson({
            'output': 'ok',
            'isError': false,
            'caller': null,
          }),
        ),
      ],
    );
    await agent.generate(
      ChatRequest(
        threadId: 't',
        runId: 'r',
        messages: [ChatMessage.user('hi', id: 'u')],
      ),
      ownerId: 'o',
      context: null,
    );
    final input = requests.last['input'] as List;
    final output = input.whereType<Map<String, Object?>>().singleWhere(
      (v) => v['type'] == 'custom_tool_call_output',
    );
    expect(output.containsKey('caller'), true);
    expect(output['caller'], isNull);
    expect(output.containsKey('id'), false);
  });
  test(
    'registered deferred custom call follows private server tool search and approval',
    () async {
      final requests = <JsonObject>[];
      var effects = 0;
      final search = <String, Object?>{
        'type': 'tool_search_call',
        'id': 'search',
        'call_id': null,
        'execution': 'server',
        'status': 'completed',
        'arguments': {'query': 'tool'},
        'private_future': 'private',
      };
      final searchOutput = <String, Object?>{
        'type': 'tool_search_output',
        'id': 'search-output',
        'call_id': null,
        'execution': 'server',
        'status': 'completed',
        'tools': <Object?>[],
      };
      final model = openai.ResponsesProtocolModel.native(
        model: 'fixture',
        authorityBindingId: 'account',
        hostedTools: [
          openai.OpenAIHostedTool.fromJson({
            'type': 'tool_search',
            'execution': 'server',
          }),
        ],
        transport: (body, _) {
          requests.add(body);
          return Stream.fromIterable([
            terminal(
              requests.length == 1 ? [search, searchOutput, custom()] : [],
            ),
          ]);
        },
      );
      final agent = AiAgent<void>(
        model: model,
        tools: [
          openai.OpenAICustomTool<void>(
            name: 'execute',
            bindingId: 'local',
            deferLoading: true,
            needsApproval: true,
            execute: (_, _) {
              effects++;
              return openai.OpenAICustomToolResult.text('ok');
            },
          ),
        ],
      );
      final paused = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      );
      expect(paused.status, RunStatus.interrupted);
      expect(effects, 0);
      final tools = requests.first['tools'] as List;
      expect(
        tools.whereType<Map<String, Object?>>().singleWhere(
          (v) => v['type'] == 'custom',
        )['defer_loading'],
        true,
      );
      final result = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r2',
          parentRunId: 'r',
          resume: [paused.interrupts.single.approve()],
        ),
        ownerId: 'o',
        context: null,
      );
      expect(result.status, RunStatus.completed);
      expect(effects, 1);
      final replay = requests.last['input'] as List;
      expect(
        replay.whereType<Map<String, Object?>>().singleWhere(
          (v) => v['type'] == 'tool_search_call',
        ),
        search,
      );
      expect(
        replay.whereType<Map<String, Object?>>().singleWhere(
          (v) => v['type'] == 'tool_search_output',
        ),
        searchOutput,
      );
    },
  );
  test(
    'raw native custom declarations reject malformed known options before effects',
    () {
      final model = openai.ResponsesProtocolModel.native(
        model: 'fixture',
        transport: (_, _) => const Stream.empty(),
      );
      for (final fields in <JsonObject>[
        {
          'format': {'type': 'unknown'},
        },
        {
          'format': {'type': 'grammar', 'syntax': 'lark'},
        },
        {
          'format': {'type': 'grammar', 'syntax': 'unknown', 'definition': 'x'},
        },
        {'allowed_callers': <Object?>[]},
      ]) {
        expect(
          () => AiAgent<void>(
            model: model,
            tools: [
              RawNativeTool({'type': 'custom', 'name': 'execute', ...fields}),
            ],
          ),
          throwsA(anyOf(isA<ArgumentError>(), isA<UnsupportedError>())),
        );
      }
    },
  );
  test(
    'added-item identity drift and duplicate call IDs fail before execution',
    () async {
      for (final invalid in [
        [
          {
            'type': 'response.output_item.added',
            'output_index': 0,
            'sequence_number': 0,
            'item': {
              'type': 'custom_tool_call',
              'id': 'item-1',
              'call_id': 'wrong',
              'name': 'execute',
              'input': '',
              'status': 'in_progress',
            },
          },
          terminal([custom()]),
        ],
        [
          terminal([
            custom(),
            {...custom(), 'id': 'item-2'},
          ]),
        ],
      ]) {
        var executions = 0;
        final model = openai.ResponsesProtocolModel.native(
          model: 'fixture',
          transport: (_, _) => Stream.fromIterable(invalid),
        );
        final agent = AiAgent<void>(
          model: model,
          tools: [
            openai.OpenAICustomTool<void>(
              name: 'execute',
              bindingId: 'local',
              execute: (_, _) {
                executions++;
                return openai.OpenAICustomToolResult.text('ok');
              },
            ),
          ],
        );
        await expectLater(
          agent.generate(
            ChatRequest(
              threadId: 't',
              runId: 'r',
              messages: [ChatMessage.user('hi', id: 'u')],
            ),
            ownerId: 'o',
            context: null,
          ),
          throwsA(isA<AgentRunException>()),
        );
        expect(executions, 0);
      }
    },
  );
  test(
    'typed transport preserves unknown private custom replay fields',
    () async {
      final bodies = <JsonObject>[];
      final model = openai.ResponsesProtocolModel(
        model: 'fixture',
        transport: (request, _) {
          bodies.add(request.toJson());
          return Stream.fromIterable([
            terminal(bodies.length == 1 ? [custom()] : []),
          ]);
        },
      );
      final agent = AiAgent<void>(
        model: model,
        tools: [
          openai.OpenAICustomTool<void>(
            name: 'execute',
            bindingId: 'local',
            execute: (_, _) => openai.OpenAICustomToolResult.text('ok'),
          ),
        ],
      );
      final result = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      );
      expect(result.status, RunStatus.completed);
      final input = bodies.last['input'] as List;
      expect(
        input.whereType<Map<String, Object?>>().singleWhere(
          (item) => item['type'] == 'custom_tool_call',
        )['private_field'],
        'secret',
      );
    },
  );
  test(
    'same custom name in separate namespaces dispatches the matching alias',
    () async {
      var first = 0, second = 0;
      var requests = 0;
      final model = openai.ResponsesProtocolModel.native(
        model: 'fixture',
        transport: (_, _) {
          requests++;
          return Stream.fromIterable([
            terminal(requests == 1 ? [custom(namespace: 'second')] : []),
          ]);
        },
      );
      final agent = AiAgent<void>(
        model: model,
        tools: [
          openai.OpenAICustomTool<void>(
            name: 'execute',
            localName: 'first_execute',
            namespace: openai.OpenAIToolNamespace(
              name: 'first',
              description: 'first',
            ),
            bindingId: '1',
            execute: (_, _) {
              first++;
              return openai.OpenAICustomToolResult.text('ok');
            },
          ),
          openai.OpenAICustomTool<void>(
            name: 'execute',
            localName: 'second_execute',
            namespace: openai.OpenAIToolNamespace(
              name: 'second',
              description: 'second',
            ),
            bindingId: '2',
            execute: (_, _) {
              second++;
              return openai.OpenAICustomToolResult.text('ok');
            },
          ),
        ],
      );
      await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      );
      expect(first, 0);
      expect(second, 1);
      expect(requests, 2);
    },
  );
  test('custom and computer coexist with a local function', () async {
    JsonObject? sent;
    final model = openai.ResponsesProtocolModel.native(
      model: 'fixture',
      transport: (body, _) {
        sent = body;
        return Stream.fromIterable([terminal([])]);
      },
    );
    final agent = AiAgent<void>(
      model: model,
      tools: [
        openai.OpenAICustomTool<void>(
          name: 'execute',
          bindingId: 'local',
          execute: (_, _) => openai.OpenAICustomToolResult.text('ok'),
        ),
        openai.OpenAIComputerTool<void>(
          environmentId: 'env',
          execute: (_, _) =>
              openai.OpenAIComputerScreenshot.fileId('screenshot'),
        ),
        Tool<int, int, void>(
          name: 'double',
          description: 'double',
          inputSchema: const {'type': 'object'},
          decode: (_) => 1,
          encode: (v) => v,
          execute: (v, _) => v * 2,
        ),
      ],
    );
    await agent.generate(
      ChatRequest(
        threadId: 't',
        runId: 'r',
        messages: [ChatMessage.user('hi', id: 'u')],
      ),
      ownerId: 'o',
      context: null,
    );
    expect((sent!['tools'] as List).map((v) => v['type']), [
      'custom',
      'computer',
      'function',
    ]);
  });
  test(
    'typed protocol accepts custom definition only if SDK preserves it',
    () async {
      var sent = 0;
      final model = openai.ResponsesProtocolModel(
        model: 'fixture',
        transport: (request, _) {
          sent++;
          return Stream.fromIterable([terminal([])]);
        },
      );
      final tool = openai.OpenAICustomTool<void>(
        name: 'execute',
        bindingId: 'local',
        execute: (_, _) => openai.OpenAICustomToolResult.text('ok'),
      );
      final agent = AiAgent<void>(model: model, tools: [tool]);
      await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      );
      expect(sent, 1);
    },
  );
  test(
    'namespace registry groups tools and rejects ambiguous identities before dispatch',
    () async {
      final namespace = openai.OpenAIToolNamespace(
        name: 'sandbox',
        description: 'Sandbox',
      );
      final tools = [
        openai.OpenAICustomTool<void>(
          name: 'one',
          localName: 'first',
          namespace: namespace,
          bindingId: 'a',
          execute: (_, _) => openai.OpenAICustomToolResult.text('ok'),
        ),
        openai.OpenAICustomTool<void>(
          name: 'two',
          localName: 'second',
          namespace: namespace,
          bindingId: 'b',
          execute: (_, _) => openai.OpenAICustomToolResult.text('ok'),
        ),
      ];
      JsonObject? sent;
      final model = openai.ResponsesProtocolModel.native(
        model: 'fixture',
        transport: (body, _) {
          sent = body;
          return Stream.fromIterable([terminal([])]);
        },
      );
      await AiAgent<void>(model: model, tools: tools).generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      );
      final defs = sent!['tools'] as List;
      expect(defs.single['type'], 'namespace');
      expect((defs.single['tools'] as List).map((e) => e['name']), [
        'one',
        'two',
      ]);
      final duplicate = openai.OpenAICustomTool<void>(
        name: 'one',
        localName: 'third',
        namespace: namespace,
        bindingId: 'c',
        execute: (_, _) => openai.OpenAICustomToolResult.text('ok'),
      );
      expect(
        () => AiAgent<void>(model: model, tools: [...tools, duplicate]),
        throwsArgumentError,
      );
    },
  );
  test(
    'custom rejection sends a text error and continues without execution',
    () async {
      var calls = 0, executions = 0;
      final bodies = <JsonObject>[];
      final model = openai.ResponsesProtocolModel.native(
        model: 'fixture',
        transport: (body, _) {
          calls++;
          bodies.add(body);
          return Stream.fromIterable([
            terminal(calls == 1 ? [custom()] : []),
          ]);
        },
      );
      final agent = AiAgent<void>(
        model: model,
        tools: [
          openai.OpenAICustomTool<void>(
            name: 'execute',
            bindingId: 'local',
            needsApproval: true,
            execute: (_, _) {
              executions++;
              return openai.OpenAICustomToolResult.text('ok');
            },
          ),
        ],
      );
      final paused = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      );
      final result = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r2',
          parentRunId: 'r',
          resume: [paused.interrupts.single.reject()],
        ),
        ownerId: 'o',
        context: null,
      );
      expect(result.status, RunStatus.completed);
      expect(executions, 0);
      final input = bodies.last['input'] as List;
      expect(
        input.whereType<Map<String, Object?>>().singleWhere(
          (v) => v['type'] == 'custom_tool_call_output',
        )['output'],
        'Tool call declined.',
      );
    },
  );
  test(
    'public SDK streaming sends custom tool and exact output over HTTP',
    () async {
      final bodies = <Map<String, Object?>>[];
      var executions = 0;
      final item = custom();
      final client = openai.OpenAIClient(
        config: const openai.OpenAIConfig(
          authProvider: openai.ApiKeyProvider('fixture'),
        ),
        streamClientFactory: () => MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, Object?>);
          final event = bodies.length == 1 ? terminal([item]) : terminal([]);
          return http.Response(
            'data: ${jsonEncode(event)}\n\ndata: [DONE]\n\n',
            200,
            headers: {'content-type': 'text/event-stream; charset=utf-8'},
          );
        }),
      );
      addTearDown(client.close);
      final agent = AiAgent<void>(
        model: openai.OpenAIResponsesModel(client: client, model: 'fixture'),
        tools: [
          openai.OpenAICustomTool<void>(
            name: 'execute',
            bindingId: 'local',
            execute: (input, _) {
              executions++;
              return openai.OpenAICustomToolResult.text(
                input,
                id: 'output-1',
                caller: {'type': 'direct'},
              );
            },
          ),
        ],
      );
      final result = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      );
      expect(result.status, RunStatus.completed);
      expect(executions, 1);
      expect(bodies.length, 2);
      final input = bodies.last['input'] as List;
      expect(
        input.whereType<Map<String, Object?>>().singleWhere(
          (v) => v['type'] == 'custom_tool_call_output',
        ),
        {
          'type': 'custom_tool_call_output',
          'call_id': 'call-1',
          'output': 'α\nplain',
          'id': 'output-1',
          'caller': {'type': 'direct'},
        },
      );
    },
  );
  test('approval resumes custom text exactly with private replay', () async {
    var executions = 0;
    final bodies = <JsonObject>[];
    final item = custom();
    final model = openai.ResponsesProtocolModel.native(
      model: 'fixture',
      transport: (body, _) {
        bodies.add(body);
        if (bodies.length == 1) {
          return Stream.fromIterable([
            {
              'type': 'response.custom_tool_call_input.delta',
              'sequence_number': 0,
              'item_id': 'item-1',
              'output_index': 0,
              'delta': 'α\n',
            },
            {
              'type': 'response.custom_tool_call_input.delta',
              'sequence_number': 1,
              'item_id': 'item-1',
              'output_index': 0,
              'delta': 'plain',
            },
            {
              'type': 'response.custom_tool_call_input.done',
              'sequence_number': 2,
              'item_id': 'item-1',
              'output_index': 0,
              'input': 'α\nplain',
            },
            {
              'type': 'response.output_item.done',
              'sequence_number': 3,
              'output_index': 0,
              'item': item,
            },
            terminal([item]),
          ]);
        }
        return Stream.fromIterable([terminal([])]);
      },
    );
    final tool = openai.OpenAICustomTool<void>(
      name: 'execute',
      bindingId: 'local',
      needsApproval: true,
      execute: (input, _) {
        executions++;
        expect(input, 'α\nplain');
        return openai.OpenAICustomToolResult.text('exact\ntext');
      },
    );
    final agent = AiAgent<void>(model: model, tools: [tool]);
    final first = await agent
        .stream(
          ChatRequest(
            threadId: 't',
            runId: 'r',
            messages: [ChatMessage.user('hi', id: 'u')],
          ),
          ownerId: 'o',
          context: null,
        )
        .toList();
    final proposed = first.whereType<AgentToolCallReady>().single.call;
    expect(proposed.arguments, {'input': 'α\nplain'});
    final paused = (first.last as AgentRunFinished).result;
    expect(paused.status, RunStatus.interrupted);
    expect(executions, 0);
    final second = await agent
        .stream(
          ChatRequest(
            threadId: 't',
            runId: 'r2',
            parentRunId: 'r',
            resume: [paused.interrupts.single.approve()],
          ),
          ownerId: 'o',
          context: null,
        )
        .toList();
    expect(executions, 1);
    expect(bodies.length, 2);
    final input = bodies.last['input'] as List;
    expect(
      input.whereType<Map<String, Object?>>().singleWhere(
        (v) => v['type'] == 'custom_tool_call',
      ),
      item,
    );
    expect(
      input.whereType<Map<String, Object?>>().singleWhere(
        (v) => v['type'] == 'custom_tool_call_output',
      )['output'],
      'exact\ntext',
    );
    expect(second.whereType<AgentToolResult>().single.result, {
      'output': 'exact\ntext',
      'isError': false,
    });
  });
  test('contradictory custom fragments never invoke executor', () async {
    var executions = 0;
    final item = custom();
    final model = openai.ResponsesProtocolModel.native(
      model: 'fixture',
      transport: (_, _) => Stream.fromIterable([
        {
          'type': 'response.custom_tool_call_input.delta',
          'sequence_number': 0,
          'item_id': 'item-1',
          'output_index': 0,
          'delta': 'wrong',
        },
        terminal([item]),
      ]),
    );
    final agent = AiAgent<void>(
      model: model,
      tools: [
        openai.OpenAICustomTool<void>(
          name: 'execute',
          bindingId: 'local',
          execute: (_, _) {
            executions++;
            return openai.OpenAICustomToolResult.text('ok');
          },
        ),
      ],
    );
    await expectLater(
      agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      ),
      throwsA(isA<AgentRunException>()),
    );
    expect(executions, 0);
  });
}
