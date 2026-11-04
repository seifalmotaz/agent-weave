// Offline Anthropic MCP and application approval consumer.
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final requests = <Map<String, dynamic>>[];
  var effects = 0;
  var credentials = 0;
  final transport = MockClient((request) async {
    requests.add(jsonDecode(request.body) as Map<String, dynamic>);
    final blocks = requests.length == 1
        ? <Map<String, Object?>>[
            {
              'type': 'mcp_tool_use',
              'id': 'mcp-1',
              'name': 'search',
              'server_name': 'support',
              'input': {'query': '42'},
              'future': 'PRIVATE_REPLAY',
            },
            {
              'type': 'tool_use',
              'id': 'local-1',
              'name': 'escalate',
              'input': {'ticket': 42},
            },
          ]
        : <Map<String, Object?>>[
            {
              'type': 'mcp_tool_result',
              'tool_use_id': 'mcp-1',
              'is_error': false,
              'content': [
                {'type': 'text', 'text': 'PRIVATE_RESULT'},
              ],
            },
            {'type': 'text', 'text': 'Escalated'},
          ];
    final events = <Map<String, Object?>>[
      {
        'type': 'message_start',
        'message': {
          'id': 'message',
          'type': 'message',
          'role': 'assistant',
          'model': 'fixture',
          'content': <Object?>[],
          'usage': {'input_tokens': 5, 'output_tokens': 0},
        },
      },
      for (var i = 0; i < blocks.length; i++) ...[
        {'type': 'content_block_start', 'index': i, 'content_block': blocks[i]},
        {'type': 'content_block_stop', 'index': i},
      ],
      {
        'type': 'message_delta',
        'delta': {
          'stop_reason': requests.length == 1 ? 'tool_use' : 'end_turn',
          'stop_sequence': null,
        },
        'usage': {'output_tokens': 2},
      },
      {'type': 'message_stop'},
    ];
    return http.Response(
      events
          .map((e) => 'event: ${e['type']}\ndata: ${jsonEncode(e)}\n\n')
          .join(),
      200,
      headers: {'content-type': 'text/event-stream'},
    );
  });
  final client = anthropic.AnthropicNativeClient.withApiKey(
    apiKey: 'fixture',
    httpClient: transport,
  );
  final store = MemoryRunStore();
  AiAgent<void> agent({bool changed = false}) => AiAgent<void>(
    store: store,
    model: client.chatModel(
      model: 'fixture',
      authorityBindingId: 'fixture-provider-account',
      mcpServers: [
        anthropic.AnthropicMcpServer(
          name: 'support',
          url: Uri.parse(
            changed
                ? 'https://changed.invalid/mcp'
                : 'https://support.invalid/mcp',
          ),
          beta: anthropic.AnthropicMcpBeta.client20251120,
          toolset: anthropic.AnthropicMcpToolset(),
          credentialBindingId: 'support-account',
          authorizationToken: () => 'fixture-token-${++credentials}',
        ),
        anthropic.AnthropicMcpServer(
          name: 'lookup',
          url: Uri.parse('https://lookup.invalid/mcp'),
          beta: anthropic.AnthropicMcpBeta.client20251120,
          toolset: anthropic.AnthropicMcpToolset(),
        ),
      ],
    ),
    tools: [
      Tool<int, String, void>(
        name: 'escalate',
        description: 'Escalate a ticket after approval',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'ticket': {'type': 'integer'},
          },
          'required': ['ticket'],
          'additionalProperties': false,
        },
        outputSchema: const {'type': 'string'},
        needsApproval: true,
        decode: (json) => json['ticket'] as int,
        encode: (value) => value,
        execute: (ticket, context) {
          effects++;
          return 'Escalated $ticket';
        },
      ),
    ],
  );
  try {
    final paused = await agent().generate(
      ChatRequest(
        threadId: 'support',
        runId: 'first',
        messages: [
          ChatMessage.user('Find and escalate ticket 42', id: 'question'),
        ],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      paused.status == RunStatus.interrupted &&
          effects == 0 &&
          requests.length == 1,
      'Local tool must wait for approval',
    );
    final first = requests.single;
    check(
      (first['mcp_servers'] as List).length == 2 &&
          (first['tools'] as List)
                  .whereType<Map<dynamic, dynamic>>()
                  .where((v) => v['type'] == 'mcp_toolset')
                  .length ==
              2,
      'Expected two servers and toolsets',
    );
    final checkpoint = await store.load(ownerId: 'owner', threadId: 'support');
    final journal = jsonEncode(
      await store.events(ownerId: 'owner', threadId: 'support', runId: 'first'),
    );
    check(
      !jsonEncode(checkpoint).contains('fixture-token-') &&
          !journal.contains('fixture-token-') &&
          !journal.contains('PRIVATE_REPLAY'),
      'Credential or replay leaked into checkpoint or journal',
    );
    final history = jsonEncode(chatHydration(checkpoint));
    check(
      !history.contains('PRIVATE_REPLAY') &&
          !history.contains('fixture-token-'),
      'Private MCP state leaked to hydration',
    );
    try {
      await agent(changed: true).generate(
        ChatRequest(
          threadId: 'support',
          runId: 'changed',
          parentRunId: paused.runId,
          resume: [paused.interrupts.single.approve()],
        ),
        ownerId: 'owner',
        context: null,
      );
      throw StateError('Changed server was accepted');
    } on AgentRunException catch (error) {
      check(
        error.code == 'INVALID_INPUT' && effects == 0 && requests.length == 1,
        'Changed profile caused an effect or request',
      );
    }
    final completed = await agent().generate(
      ChatRequest(
        threadId: 'support',
        runId: 'approved',
        parentRunId: paused.runId,
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      completed.text == 'Escalated' &&
          effects == 1 &&
          requests.length == 2 &&
          credentials == 2,
      'Approved run did not complete once',
    );
    final replay = (requests.last['messages'] as List)
        .whereType<Map<dynamic, dynamic>>()
        .expand(
          (message) => message['content'] is List
              ? message['content'] as List
              : <Object?>[],
        )
        .whereType<Map<dynamic, dynamic>>()
        .singleWhere((block) => block['type'] == 'mcp_tool_use');
    check(
      jsonEncode(replay) ==
              jsonEncode({
                'type': 'mcp_tool_use',
                'id': 'mcp-1',
                'name': 'search',
                'server_name': 'support',
                'input': {'query': '42'},
                'future': 'PRIVATE_REPLAY',
              }) &&
          jsonEncode(requests.last).contains('fixture-token-2'),
      'Continuation lost exact native replay or refreshed credentials',
    );
    final finalHistory = jsonEncode(
      chatHydration(await store.load(ownerId: 'owner', threadId: 'support')),
    );
    check(
      !finalHistory.contains('PRIVATE_REPLAY') &&
          !finalHistory.contains('PRIVATE_RESULT') &&
          !finalHistory.contains('fixture-token-'),
      'Private MCP data leaked to hydration',
    );
    print(
      'PASS deferred MCP, local approval, profile guard and credential refresh',
    );
  } finally {
    client.close();
    transport.close();
  }
}
