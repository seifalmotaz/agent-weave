import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Map<String, Object?> start() => {
  'type': 'message_start',
  'message': {
    'id': 'msg',
    'type': 'message',
    'role': 'assistant',
    'model': 'fixture',
    'content': <Object?>[],
    'usage': {'input_tokens': 5, 'output_tokens': 0},
  },
};
List<Map<String, Object?>> reply(
  List<Map<String, Object?>> blocks,
  String reason, {
  bool eof = false,
}) => [
  start(),
  for (var i = 0; i < blocks.length; i++) ...[
    {'type': 'content_block_start', 'index': i, 'content_block': blocks[i]},
    {'type': 'content_block_stop', 'index': i},
  ],
  if (!eof) ...[
    {
      'type': 'message_delta',
      'delta': {'stop_reason': reason, 'stop_sequence': null},
      'usage': {'output_tokens': 2},
    },
    {'type': 'message_stop'},
  ],
];
Map<String, Object?> serverCall() => {
  'type': 'server_tool_use',
  'id': 'srv-1',
  'name': 'web_search',
  'input': {'query': 'Dart'},
  'private_extra': 'PRIVATE-SERVER',
};
Map<String, Object?> serverResult() => {
  'type': 'web_search_tool_result',
  'tool_use_id': 'srv-1',
  'content': [
    {
      'type': 'web_search_result',
      'url': 'https://example.org',
      'title': 'Dart',
      'encrypted_content': 'PRIVATE-ENCRYPTED',
      'page_age': '1 day',
    },
  ],
};
Map<String, Object?> citedText() => {
  'type': 'text',
  'text': 'A source.',
  'citations': [
    {
      'type': 'web_search_result_location',
      'url': 'https://example.org',
      'title': 'Dart',
      'cited_text': 'source',
      'encrypted_index': 'PRIVATE-INDEX',
    },
  ],
};

Future<void> main() async {
  for (final mode in [
    'replay',
    'mixed',
    'limit',
    'eof',
    'malformed',
    'unconfigured',
    'cancel',
  ]) {
    await journey(mode);
    print('PASS $mode');
  }
  for (final caller in ['code_execution_20260120', 'code_execution_20260521']) {
    await programmatic(caller);
    print('PASS programmatic $caller');
  }
}

Future<void> journey(String mode) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, dynamic>>[];
  var executed = 0;
  final cancellation = CancellationToken();
  server.listen((request) async {
    bodies.add(
      jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>,
    );
    final n = bodies.length;
    var events = <Map<String, Object?>>[];
    if (mode == 'limit' && n <= 2) {
      events = reply([serverCall()..['id'] = 'srv-$n'], 'pause_turn');
    } else if (mode == 'limit') {
      events = reply([
        serverResult()..['tool_use_id'] = 'srv-1',
        serverResult()..['tool_use_id'] = 'srv-2',
        citedText(),
      ], 'end_turn');
    } else if (n == 1) {
      events = reply([serverCall()], 'pause_turn', eof: mode == 'eof');
      if (mode == 'malformed') events = reply([serverCall()], 'unknown_reason');
      if (mode == 'unconfigured') {
        events = reply([
          serverCall()..['name'] = 'code_execution',
        ], 'pause_turn');
      }
    } else if (n == 2 && mode == 'mixed') {
      events = reply([
        serverResult(),
        citedText(),
        {
          'type': 'tool_use',
          'id': 'app-1',
          'name': 'double',
          'input': {'value': 21},
        },
      ], 'tool_use');
    } else if (n == 2) {
      events = reply([serverResult(), citedText()], 'end_turn');
    } else {
      events = reply([
        {'type': 'text', 'text': '42'},
      ], 'end_turn');
    }
    if (n == 1 && mode == 'mixed') {
      events[events.length - 2]['delta'] = {
        'stop_reason': 'pause_turn',
        'stop_sequence': null,
        'container': {
          'id': 'container-1',
          'expires_at': '2099-01-01T00:00:00Z',
        },
      };
    }
    request.response.headers.contentType = ContentType('text', 'event-stream');
    for (final event in events) {
      request.response.write(
        'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
      );
    }
    await request.response.close();
    if (mode == 'cancel' && n == 1) cancellation.cancel();
  });
  final client = api.AnthropicNativeClient.withApiKey(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}',
  );
  final store = MemoryRunStore();
  AiAgent<void> agent() => AiAgent<void>(
    model: client.chatModel(
      authorityBindingId: 'example-anthropic-account',
      model: 'fixture',
      hostedTools: [
        api.AnthropicHostedTool(const api.WebSearchTool(maxUses: 3)),
      ],
    ),
    store: store,
    maxSteps: mode == 'limit' ? 2 : 8,
    tools: [
      if (mode == 'mixed')
        Tool<int, int, void>(
          name: 'double',
          description: 'Double a number',
          needsApproval: true,
          inputSchema: const {
            'type': 'object',
            'properties': {
              'value': {'type': 'integer'},
            },
            'required': ['value'],
          },
          decode: (v) => v['value'] as int,
          encode: (v) => v,
          execute: (v, context) {
            executed++;
            return v * 2;
          },
        ),
    ],
  );
  try {
    AgentResult? result;
    Object? failure;
    try {
      result = await agent().generate(
        ChatRequest(
          threadId: 'thread',
          runId: 'one',
          messages: [ChatMessage.user('Search', id: 'user')],
        ),
        ownerId: 'owner',
        context: null,
        cancellation: cancellation,
      );
    } catch (e) {
      failure = e;
    }
    if (mode == 'eof' ||
        mode == 'malformed' ||
        mode == 'unconfigured' ||
        mode == 'limit' ||
        mode == 'cancel') {
      check(failure != null, '$mode should fail');
      check(
        bodies.length == (mode == 'limit' ? 2 : 1),
        '$mode extra requests: ${bodies.length}',
      );
      check(executed == 0, '$mode executed app tool');
      if (mode == 'limit') {
        final checkpoint = await store.load(
          ownerId: 'owner',
          threadId: 'thread',
        );
        check(
          jsonEncode(checkpoint).contains('PRIVATE-SERVER'),
          'step-limit checkpoint lost pause',
        );
        check(
          failure is AgentRunException && failure.result.usages.length == 2,
          'step-limit usage: $failure ${(failure is AgentRunException) ? failure.result.usages.length : -1}',
        );
        var rejected = false;
        try {
          await agent().generate(
            ChatRequest(
              threadId: 'thread',
              runId: 'wrong',
              messages: [ChatMessage.user('New request', id: 'new')],
            ),
            ownerId: 'owner',
            context: null,
          );
        } catch (_) {
          rejected = true;
        }
        check(
          rejected && bodies.length == 2,
          'new user message accepted during pause',
        );
        final resumed = await agent().generate(
          ChatRequest(threadId: 'thread', runId: 'resume'),
          ownerId: 'owner',
          context: null,
        );
        check(
          resumed.text == 'A source.' && bodies.length == 3,
          'resume after step limit',
        );
        check(
          jsonEncode(bodies.last['messages']).contains('srv-2'),
          'resume after limit lost checkpoint',
        );
      }
      return;
    }
    check(failure == null && result != null, '$mode failed: $failure');
    check(bodies.length == 2, '$mode pause continuation count');
    check(
      jsonEncode(bodies[0]['tools']).contains('web_search_20250305'),
      'hosted tool definition',
    );
    check(
      jsonEncode(bodies[1]['messages']).contains('PRIVATE-SERVER'),
      'pause lost server call',
    );
    if (mode == 'mixed') {
      check(
        bodies[1]['container'] == 'container-1',
        'container missing on pause continuation',
      );
      check(
        result!.status == RunStatus.interrupted &&
            result.interrupts.length == 1 &&
            executed == 0,
        'app approval',
      );
      final stored = await store.load(ownerId: 'owner', threadId: 'thread');
      check(
        jsonEncode(stored).contains('PRIVATE-ENCRYPTED'),
        'checkpoint lost hosted result',
      );
      check(
        !jsonEncode(chatHydration(stored)).contains('PRIVATE-ENCRYPTED'),
        'private hosted result leaked',
      );
      result = await agent().generate(
        ChatRequest(
          threadId: 'thread',
          runId: 'two',
          parentRunId: result.runId,
          resume: [result.interrupts.single.approve()],
        ),
        ownerId: 'owner',
        context: null,
      );
      check(
        executed == 1 && result.text == '42' && bodies.length == 3,
        'approval continuation',
      );
      check(
        bodies[2]['container'] == 'container-1',
        'container missing on recreated approval resume',
      );
      final history = jsonEncode(bodies[2]['messages']);
      check(
        history.contains('PRIVATE-SERVER') &&
            history.contains('PRIVATE-ENCRYPTED') &&
            history.contains('PRIVATE-INDEX') &&
            history.contains('app-1'),
        'recreated replay lost blocks or result',
      );
    } else {
      check(result!.text == 'A source.', 'answer text');
      check(
        result.usage?.inputTokens == 10 && result.usage?.outputTokens == 4,
        'pause usage accumulation',
      );
      final stored = await store.load(ownerId: 'owner', threadId: 'thread');
      check(
        !jsonEncode(chatHydration(stored)).contains('PRIVATE-ENCRYPTED'),
        'private hosted result leaked',
      );
      await agent().generate(
        ChatRequest(
          threadId: 'thread',
          runId: 'two',
          messages: [ChatMessage.user('Follow up', id: 'next')],
        ),
        ownerId: 'owner',
        context: null,
      );
      final history = jsonEncode(bodies[2]['messages']);
      check(
        history.contains('PRIVATE-SERVER') &&
            history.contains('PRIVATE-ENCRYPTED') &&
            history.contains('PRIVATE-INDEX'),
        'follow-up replay',
      );
    }
  } finally {
    client.close();
    await server.close(force: true);
  }
}

Future<void> programmatic(String allowedCaller) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, dynamic>>[];
  var executions = 0;
  server.listen((request) async {
    bodies.add(
      jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>,
    );
    final events = bodies.length == 1
        ? reply([
            {
              'type': 'server_tool_use',
              'id': 'code-1',
              'name': 'code_execution',
              'input': {'code': 'call double'},
            },
            {
              'type': 'tool_use',
              'id': 'app-1',
              'name': 'double',
              'input': {'value': 21},
              'caller': {
                'type': 'code_execution_20260120',
                'tool_id': 'code-1',
              },
            },
          ], 'tool_use')
        : reply([
            {
              'type': 'code_execution_tool_result',
              'tool_use_id': 'code-1',
              'content': {
                'type': 'code_execution_result',
                'stdout': '42',
                'stderr': '',
                'return_code': 0,
                'content': <Object?>[],
              },
            },
            {'type': 'text', 'text': '42'},
          ], 'end_turn');
    if (bodies.length == 1) {
      events[events.length - 2]['delta'] = {
        'stop_reason': 'tool_use',
        'container': {'id': 'code-container'},
      };
    }
    request.response.headers.contentType = ContentType('text', 'event-stream');
    for (final event in events) {
      request.response.write(
        'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
      );
    }
    await request.response.close();
  });
  final client = api.AnthropicNativeClient.withApiKey(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}',
  );
  final store = MemoryRunStore();
  AiAgent<void> agent() => AiAgent<void>(
    model: client.chatModel(
      authorityBindingId: 'example-anthropic-account',
      model: 'fixture',
      hostedTools: [api.AnthropicHostedTool(api.CodeExecutionBuiltInTool())],
      functionToolOptions: {
        'double': {
          'allowed_callers': [allowedCaller],
          'defer_loading': true,
        },
      },
    ),
    store: store,
    tools: [
      Tool<int, int, void>(
        name: 'double',
        description: 'Double',
        needsApproval: true,
        inputSchema: const {
          'type': 'object',
          'properties': {
            'value': {'type': 'integer'},
          },
          'required': ['value'],
        },
        decode: (v) => v['value'] as int,
        encode: (v) => v,
        execute: (v, context) {
          executions++;
          return v * 2;
        },
      ),
    ],
  );
  try {
    final paused = await agent().generate(
      ChatRequest(
        threadId: 'programmatic',
        runId: 'one',
        messages: [ChatMessage.user('Calculate', id: 'user')],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      paused.status == RunStatus.interrupted &&
          executions == 0 &&
          paused.interrupts.length == 1,
      'programmatic approval',
    );
    final result = await agent().generate(
      ChatRequest(
        threadId: 'programmatic',
        runId: 'two',
        parentRunId: paused.runId,
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      result.text == '42' && executions == 1 && bodies.length == 2,
      'programmatic continuation',
    );
    check(
      bodies.last['container'] == 'code-container',
      'programmatic container replay',
    );
    final replay = jsonEncode(bodies.last['messages']);
    check(
      replay.contains('code-1') &&
          replay.contains('code_execution_20260120') &&
          replay.contains('app-1'),
      'programmatic caller replay',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}
