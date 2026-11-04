import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const approval = <String, Object?>{
  'type': 'mcp_approval_request',
  'id': 'private-request',
  'server_label': 'desk',
  'name': 'escalate',
  'arguments': '{"ticket":42}',
};
const execution = <String, Object?>{
  'type': 'mcp_call',
  'id': 'call',
  'server_label': 'desk',
  'name': 'escalate',
  'arguments': '{"ticket":42}',
  'output': 'ok',
  'status': 'completed',
};
openai.OpenAIMcpTool tool() => openai.OpenAIMcpTool.fromJson({
  'type': 'mcp',
  'server_label': 'desk',
  'server_url': 'https://desk.example.invalid/mcp',
  'require_approval': 'always',
});
JsonObject terminal(List<JsonObject> output) => {
  'type': 'response.completed',
  'response': {'status': 'completed', 'output': output},
};
Future<List<ModelEvent>> events(
  List<JsonObject> stream, {
  List<openai.OpenAIMcpTool>? tools,
}) =>
    openai.ResponsesProtocolModel.native(
          model: 'fixture',
          mcpTools: tools ?? [tool()],
          transport: (_, _) => Stream.fromIterable(stream),
        )
        .stream(ModelRequest(messages: []), cancellation: CancellationToken())
        .toList();

void main() {
  test(
    'MCP stream reconciles done, discovery, arguments and private items',
    () async {
      final discovery = <String, Object?>{
        'type': 'mcp_list_tools',
        'id': 'list',
        'server_label': 'desk',
        'tools': [
          {
            'name': 'escalate',
            'input_schema': {'type': 'object'},
          },
        ],
        'private_future': {'opaque': true},
      };
      final output = [discovery, execution, approval];
      final result = await events([
        {
          'type': 'response.mcp_call_arguments.delta',
          'item_id': 'call',
          'output_index': 1,
          'delta': '{"ticket":',
        },
        {
          'type': 'response.mcp_call_arguments.delta',
          'item_id': 'call',
          'output_index': 1,
          'delta': '42}',
        },
        {
          'type': 'response.mcp_call_arguments.done',
          'item_id': 'call',
          'output_index': 1,
          'arguments': '{"ticket":42}',
        },
        for (var i = 0; i < output.length; i++)
          {
            'type': 'response.output_item.done',
            'output_index': i,
            'item': output[i],
          },
        terminal(output),
      ]);
      expect(result.first, isA<ProviderExecutionStarting>());
      final call = result.whereType<ProviderApprovalReady>().single.call;
      expect(call.id, isNot(contains('private-request')));
      expect(call.providerRequestId, 'private-request');
      expect(call.arguments, {'ticket': 42});
      expect(result.whereType<ProviderOutput>().first.items, output);
      expect(result.whereType<NativeToolCallReady>(), isEmpty);
      expect(result.whereType<ToolCallReady>(), isEmpty);
    },
  );

  for (final bad in <String, JsonObject>{
    'unconfigured server': {...approval, 'server_label': 'other'},
    'empty ID': {...approval, 'id': ''},
    'invalid JSON': {...approval, 'arguments': '{'},
    'nonobject arguments': {...approval, 'arguments': '[]'},
    'missing name': {...approval}..remove('name'),
    'unfinished execution': {...execution, 'status': 'in_progress'},
    'malformed discovery': {
      'type': 'mcp_list_tools',
      'id': 'list',
      'server_label': 'desk',
      'tools': [<String, Object?>{}],
    },
  }.entries) {
    test('reject ${bad.key} before approval events', () async {
      final seen = <ModelEvent>[];
      await expectLater(
        events([
          terminal([bad.value]),
        ]).then(seen.addAll),
        throwsA(anything),
      );
      expect(seen.whereType<ProviderApprovalReady>(), isEmpty);
    });
  }

  test('MCP configuration and namespace cannot be bypassed', () async {
    expect(
      () => openai.ResponsesProtocolModel.native(
        model: 'm',
        mcpTools: [tool(), tool()],
        transport: (_, _) => const Stream.empty(),
      ),
      throwsArgumentError,
    );
    var dispatched = false;
    final model = openai.ResponsesProtocolModel.native(
      model: 'm',
      configure: (body) => {
        ...body,
        'tools': [tool().definition],
      },
      transport: (_, _) async* {
        dispatched = true;
        yield terminal([]);
      },
    );
    await expectLater(
      model
          .stream(ModelRequest(messages: []), cancellation: CancellationToken())
          .toList(),
      throwsA(anything),
    );
    expect(dispatched, false);
    await expectLater(
      events([
        terminal([approval]),
      ], tools: []),
      throwsFormatException,
    );
  });

  test('conflicting MCP streams and missing terminals are rejected', () async {
    for (final stream in <List<JsonObject>>[
      [
        {
          'type': 'response.output_item.done',
          'output_index': 0,
          'item': {...approval, 'arguments': '{}'},
        },
        terminal([approval]),
      ],
      [
        {
          'type': 'response.output_item.added',
          'output_index': 0,
          'item': {...approval, 'server_label': 'other'},
        },
        terminal([approval]),
      ],
      [
        {
          'type': 'response.output_item.done',
          'output_index': 1,
          'item': approval,
        },
        terminal([approval]),
      ],
      [
        terminal([approval, approval]),
      ],
      [
        {
          'type': 'response.incomplete',
          'response': {
            'status': 'incomplete',
            'output': [approval],
          },
        },
      ],
      [
        {
          'type': 'response.output_item.done',
          'output_index': 0,
          'item': approval,
        },
      ],
      [
        terminal([approval]),
        terminal([approval]),
      ],
    ]) {
      await expectLater(events(stream), throwsA(anything));
    }
  });

  test(
    'replay decisions use exact private requests and reject orphan state',
    () async {
      final call = ProviderApprovalCall(
        id: 'local',
        name: 'escalate',
        arguments: {'ticket': 42},
        provider: 'openai.responses',
        serverLabel: 'desk',
        providerRequestId: 'private-request',
      );
      final message = ChatMessage(
        id: 'prior',
        role: MessageRole.assistant,
        toolCalls: [call],
        providerData: {
          'openai.responses': [approval],
        },
      );
      JsonObject? sent;
      final model = openai.ResponsesProtocolModel.native(
        model: 'm',
        mcpTools: [tool()],
        transport: (body, _) async* {
          sent = body;
          yield terminal([]);
        },
      );
      const decision = ProviderApprovalDecision(
        provider: 'openai.responses',
        providerRequestId: 'private-request',
        approved: false,
      );
      await model
          .stream(
            ModelRequest(
              messages: [message],
              providerApprovalDecisions: [decision],
            ),
            cancellation: CancellationToken(),
          )
          .drain<void>();
      expect(sent!['input'], [
        approval,
        {
          'type': 'mcp_approval_response',
          'approval_request_id': 'private-request',
          'approve': false,
        },
      ]);
      for (final request in [
        ModelRequest(messages: [message]),
        ModelRequest(messages: [], providerApprovalDecisions: [decision]),
        ModelRequest(
          messages: [message],
          providerApprovalDecisions: [decision, decision],
        ),
      ]) {
        await expectLater(
          model
              .stream(request, cancellation: CancellationToken())
              .drain<void>(),
          throwsFormatException,
        );
      }
    },
  );

  test('known response metadata cannot reintroduce MCP credentials', () async {
    final model = openai.ResponsesProtocolModel.native(
      model: 'm',
      mcpTools: [tool()],
      transport: (_, _) async* {
        yield {
          'type': 'response.completed',
          'response': {
            'status': 'completed',
            'output': <Object?>[],
            'tools': [
              {
                ...tool().definition,
                'authorization': 'SECRET',
                'headers': {'key': 'SECRET'},
              },
            ],
          },
        };
      },
    );
    final output = await model
        .stream(ModelRequest(messages: []), cancellation: CancellationToken())
        .where((e) => e is ProviderOutput)
        .toList();
    final metadata = (output.last as ProviderOutput).items.single;
    expect(jsonEncode(metadata), isNot(contains('SECRET')));
    expect((metadata['tools'] as List).single, tool().definition);
  });

  test(
    'MCP approval echo and reason correlate with the private decision',
    () async {
      final message = ChatMessage(
        id: 'prior',
        role: MessageRole.assistant,
        toolCalls: [
          ProviderApprovalCall(
            id: 'local',
            name: 'escalate',
            arguments: {'ticket': 42},
            provider: 'openai.responses',
            serverLabel: 'desk',
            providerRequestId: 'private-request',
          ),
        ],
        providerData: {
          'openai.responses': [approval],
        },
      );
      const decision = ProviderApprovalDecision(
        provider: 'openai.responses',
        providerRequestId: 'private-request',
        approved: false,
        reason: 'Not permitted',
      );
      final request = ModelRequest(
        messages: [message],
        providerApprovalDecisions: [decision],
      );
      JsonObject? sent;
      final echo = <String, Object?>{
        'id': 'echo',
        'type': 'mcp_approval_response',
        'approval_request_id': 'private-request',
        'approve': false,
        'reason': 'Not permitted',
      };
      final model = openai.ResponsesProtocolModel.native(
        model: 'm',
        mcpTools: [tool()],
        transport: (body, _) async* {
          sent = body;
          yield terminal([echo]);
        },
      );
      final result = await model
          .stream(request, cancellation: CancellationToken())
          .toList();
      expect((sent!['input'] as List).last, {
        'type': 'mcp_approval_response',
        'approval_request_id': 'private-request',
        'approve': false,
        'reason': 'Not permitted',
      });
      expect(result.whereType<ProviderOutput>().first.items, [echo]);
      expect(result.whereType<ProviderApprovalReady>(), isEmpty);
      for (final bad in [
        {...echo, 'approve': true},
        {...echo, 'approval_request_id': 'unknown'},
      ]) {
        final invalid = openai.ResponsesProtocolModel.native(
          model: 'm',
          mcpTools: [tool()],
          transport: (_, _) async* {
            yield terminal([bad]);
          },
        );
        await expectLater(
          invalid.stream(request, cancellation: CancellationToken()).toList(),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'third turn replays an echoed decision once, preserving audit',
    () async {
      final first = ChatMessage(
        id: 'first',
        role: MessageRole.assistant,
        toolCalls: [
          ProviderApprovalCall(
            id: 'local',
            name: 'escalate',
            arguments: {'ticket': 42},
            provider: 'openai.responses',
            serverLabel: 'desk',
            providerRequestId: 'private-request',
          ),
        ],
        providerData: {
          'openai.responses': [approval],
        },
      );
      final echo = <String, Object?>{
        'id': 'echo',
        'type': 'mcp_approval_response',
        'approval_request_id': 'private-request',
        'approve': true,
      };
      final second = ChatMessage(
        id: 'second',
        role: MessageRole.assistant,
        providerData: {
          'openai.responses': [echo, execution],
        },
      );
      JsonObject? sent;
      final model = openai.ResponsesProtocolModel.native(
        model: 'm',
        mcpTools: [tool()],
        transport: (body, _) async* {
          sent = body;
          yield terminal([]);
        },
      );
      await model
          .stream(
            ModelRequest(
              messages: [
                first,
                second,
                ChatMessage.user('Next', id: 'u'),
              ],
              providerApprovalDecisions: [
                const ProviderApprovalDecision(
                  provider: 'openai.responses',
                  providerRequestId: 'private-request',
                  approved: true,
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .drain<void>();
      expect(
        (sent!['input'] as List).where(
          (item) => item['type'] == 'mcp_approval_response',
        ),
        hasLength(1),
      );
      expect(second.providerData['openai.responses']!.first, echo);
    },
  );

  test('MCP binding includes every server and hosted tool', () {
    final call = ProviderApprovalCall(
      id: 'local',
      name: 'escalate',
      arguments: {},
      provider: 'openai.responses',
      serverLabel: 'desk',
      providerRequestId: 'private',
    );
    openai.ResponsesProtocolModel model(List<openai.OpenAIMcpTool> tools) =>
        openai.ResponsesProtocolModel.native(
          model: 'm',
          mcpTools: tools,
          transport: (_, _) => const Stream.empty(),
        );
    final original = model([tool()]).approvalContract(call);
    final added = model([
      tool(),
      openai.OpenAIMcpTool.fromJson({
        'type': 'mcp',
        'server_label': 'other',
        'server_url': 'https://other.example.invalid',
        'require_approval': 'never',
      }),
    ]).approvalContract(call);
    expect(jsonEquals(original, added), false);
  });

  test('cancellation at provider checkpoint prevents dispatch', () async {
    final token = CancellationToken();
    var dispatched = false;
    final model = openai.ResponsesProtocolModel.native(
      model: 'm',
      mcpTools: [tool()],
      transport: (_, _) async* {
        dispatched = true;
        yield terminal([]);
      },
    );
    Future<void> consume() async {
      await for (final event in model.stream(
        ModelRequest(messages: []),
        cancellation: token,
      )) {
        if (event is ProviderExecutionStarting) token.cancel();
      }
    }

    await expectLater(consume(), throwsA(isA<RunCancelled>()));
    expect(dispatched, false);
  });

  test('SDK streaming never retries an uncertain MCP request', () async {
    var attempts = 0;
    final client = openai.OpenAIClient(
      config: const openai.OpenAIConfig(
        authProvider: openai.ApiKeyProvider('fixture'),
      ),
      streamClientFactory: () => MockClient((_) async {
        attempts++;
        return http.Response('unavailable', 503);
      }),
    );
    addTearDown(client.close);
    final store = MemoryRunStore();
    AiAgent<void> agent() => AiAgent<void>(
      store: store,
      model: openai.OpenAIResponsesModel(
        client: client,
        model: 'm',
        mcpTools: [tool()],
      ),
    );
    await expectLater(
      agent().generate(
        ChatRequest(
          threadId: 't',
          runId: 'first',
          messages: [ChatMessage.user('Act', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      ),
      throwsA(isA<AgentRunException>()),
    );
    expect(attempts, 1);
    expect(
      (await store.load(
        ownerId: 'o',
        threadId: 't',
      ))!['providerApprovalIndeterminate'],
      true,
    );
    await expectLater(
      agent().generate(
        ChatRequest(threadId: 't', runId: 'retry', parentRunId: 'first'),
        ownerId: 'o',
        context: null,
      ),
      throwsA(isA<AgentRunException>()),
    );
    expect(attempts, 1);
  });
}
