import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

final actions = <(String, Map<String, Object?>)>[
  ('screenshot', {}),
  (
    'zoom',
    {
      'region': [0, 0, 10, 10],
    },
  ),
  (
    'left_click',
    {
      'coordinate': [1, 2],
      'text': 'shift',
    },
  ),
  ('right_click', {}),
  ('middle_click', {}),
  ('double_click', {}),
  ('triple_click', {}),
  (
    'left_click_drag',
    {
      'start_coordinate': [1, 2],
      'coordinate': [3, 4],
    },
  ),
  (
    'mouse_move',
    {
      'coordinate': [1, 2],
    },
  ),
  ('left_mouse_down', {}),
  ('left_mouse_up', {}),
  ('cursor_position', {}),
  ('scroll', {'scroll_direction': 'down', 'scroll_amount': 2}),
  ('type', {'text': 'hello'}),
  ('key', {'text': 'Return', 'repeat': 2}),
  ('hold_key', {'text': 'shift', 'duration': 1}),
  ('wait', {'duration': 1}),
];

Map<String, Object?> start() => {
  'type': 'message_start',
  'message': {
    'id': 'm',
    'type': 'message',
    'role': 'assistant',
    'model': 'fixture',
    'content': <Object?>[],
    'usage': {'input_tokens': 5, 'output_tokens': 0},
  },
};
Map<String, Object?> finish(String reason) => {
  'type': 'message_delta',
  'delta': {'stop_reason': reason, 'stop_sequence': null},
  'usage': {'output_tokens': 2},
};
List<Map<String, Object?>> message(
  List<Map<String, Object?>> calls, {
  String stopReason = 'tool_use',
  bool truncated = false,
}) => [
  start(),
  for (var i = 0; i < calls.length; i++) ...[
    {'type': 'content_block_start', 'index': i, 'content_block': calls[i]},
    {'type': 'content_block_stop', 'index': i},
  ],
  if (!truncated) ...[
    finish(stopReason),
    {'type': 'message_stop'},
  ],
];
Map<String, Object?> call(
  String name,
  Map<String, Object?> input,
  int id, {
  String toolset = 'computer',
}) => {
  'type': 'tool_use',
  'id': 'call-$id',
  'name': name,
  'toolset_name': toolset,
  'input': input,
  'private_extra': 'PRIVATE-CALL',
};
List<Map<String, Object?>> done() => [
  start(),
  {
    'type': 'content_block_start',
    'index': 0,
    'content_block': {'type': 'text', 'text': 'done'},
  },
  {'type': 'content_block_stop', 'index': 0},
  finish('end_turn'),
  {'type': 'message_stop'},
];

Future<void> main() async {
  for (final mode in [
    'all',
    'mixed',
    'mixed_error',
    'error_batch',
    'stale',
    'decline',
    'unknown',
    'unknown_field',
    'unknown_caller',
    'disabled',
    'truncated',
    'invalid_stop',
    'cancel',
  ]) {
    await journey(mode);
    print('PASS $mode');
  }
}

Future<void> journey(String mode) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bodies = <Map<String, dynamic>>[];
  final executed = <String>[];
  var terminalSent = false;
  var regularCount = 0;
  server.listen((request) async {
    final body =
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>;
    bodies.add(body);
    terminalSent = false;
    final before = executed.length;
    check(request.uri.path == '/v1/messages', 'Messages endpoint');
    final definitions = body['tools'] as List;
    check(
      definitions.any((d) => d['type'] == 'computer_toolset_20260801'),
      'missing toolset',
    );
    if (bodies.length > 1) {
      final messages = body['messages'] as List;
      final assistant = messages[messages.length - 2] as Map;
      final results = (messages.last as Map)['content'] as List;
      final calls = (assistant['content'] as List)
          .where((c) => c['type'] == 'tool_use')
          .toList();
      check(
        jsonEncode(assistant).contains('PRIVATE-CALL'),
        'private replay lost',
      );
      check(results.length == calls.length, 'batch result count');
      for (var i = 0; i < calls.length; i++) {
        check(
          results[i]['tool_use_id'] == calls[i]['id'],
          'result order/id: ${jsonEncode(calls)} => ${jsonEncode(results)}',
        );
        if (calls[i]['toolset_name'] == 'computer') {
          check(results[i]['toolset_name'] == 'computer', 'result toolset');
        }
      }
      if (mode == 'error_batch') {
        check(
          results.length == 3 && results.every((r) => r['is_error'] == true),
          'batch errors: ${jsonEncode(results)}',
        );
        check(
          jsonEncode(results.skip(1).toList()).contains('Not executed'),
          'batch halt message',
        );
      }
      if (mode == 'mixed_error') {
        check(
          results.length == 2 &&
              results[0]['is_error'] == true &&
              jsonEncode(results[1]).contains('Not executed'),
          'mixed failure results',
        );
      }
      if (mode != 'error_batch' &&
          mode != 'mixed_error' &&
          calls.any((c) => c['name'] == 'screenshot')) {
        check(jsonEncode(results).contains('image'), 'screenshot image result');
      }
    }
    List<Map<String, Object?>> events;
    final offset = (bodies.length - 1) * 3;
    if (mode == 'all' && offset < actions.length) {
      final batch = <Map<String, Object?>>[];
      for (var i = offset; i < actions.length && i < offset + 3; i++) {
        batch.add(call(actions[i].$1, actions[i].$2, i));
      }
      events = message(batch);
    } else if (bodies.length == 1) {
      final first = call('screenshot', {}, 0);
      if (mode == 'unknown') first['name'] = 'future_action';
      if (mode == 'unknown_field') first['input'] = {'surprise': true};
      if (mode == 'unknown_caller') first['caller'] = {'type': 'future'};
      if (mode == 'disabled') {
        first['name'] = 'zoom';
        first['input'] = {
          'region': [0, 0, 10, 10],
        };
      }
      events = message(
        [
          first,
          if (mode == 'error_batch') call('left_click', {}, 1),
          if (mode == 'error_batch') call('wait', {'duration': 1}, 2),
          if (mode == 'mixed' || mode == 'mixed_error')
            {
              'type': 'tool_use',
              'id': 'regular',
              'name': 'double',
              'input': {'value': 21},
            },
        ],
        stopReason: mode == 'invalid_stop' ? 'end_turn' : 'tool_use',
        truncated: mode == 'truncated',
      );
    } else {
      events = done();
    }
    request.response.headers.contentType = ContentType('text', 'event-stream');
    for (final event in events) {
      if (event['type'] == 'message_stop') {
        await request.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 10));
        check(executed.length == before, 'execution before message stop');
        terminalSent = true;
      }
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
  AiAgent<void> agent([String environment = 'desktop-1']) => AiAgent<void>(
    model: client.chatModel(model: 'fixture'),
    store: store,
    tools: [
      api.AnthropicComputerTool<void>(
        environmentId: environment,
        configs: mode == 'disabled'
            ? const api.ComputerToolsetConfigs(
                zoom: api.ToolsetMemberConfig(enabled: false),
              )
            : null,
        execute: (call, context) {
          check(
            terminalSent && context.approved,
            'executed before message stop or approval',
          );
          check(
            !call.raw.containsKey('private_extra'),
            'private data in callback',
          );
          check(call.id == context.toolCallId, 'callback id');
          executed.add(call.raw['name'] as String);
          if (mode == 'error_batch' || mode == 'mixed_error') {
            return api.AnthropicComputerResult.error('fixture failure');
          }
          return call.action is api.AnthropicComputerZoom ||
                  (call.action is api.AnthropicComputerEmptyAction &&
                      (call.action as api.AnthropicComputerEmptyAction).kind ==
                          api.AnthropicComputerEmpty.screenshot)
              ? api.AnthropicComputerResult.screenshot(
                  api.ImageSource.base64(
                    data: 'aGVsbG8=',
                    mediaType: api.ImageMediaType.png,
                  ),
                )
              : api.AnthropicComputerResult.text('OK');
        },
      ),
      if (mode == 'mixed' || mode == 'mixed_error')
        Tool<int, int, void>(
          name: 'double',
          description: 'Double',
          inputSchema: const {
            'type': 'object',
            'properties': {
              'value': {'type': 'integer'},
            },
            'required': ['value'],
          },
          outputSchema: const {'type': 'integer'},
          decode: (x) => x['value'] as int,
          encode: (x) => x,
          execute: (x, context) {
            regularCount++;
            return x * 2;
          },
        ),
    ],
  );
  try {
    final cancellation = CancellationToken();
    if (mode == 'cancel') cancellation.cancel();
    var result = await agent().generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'run-0',
        messages: [ChatMessage.user('Inspect', id: 'user')],
      ),
      ownerId: 'owner',
      context: null,
      cancellation: cancellation,
    );
    check(
      !{
        'unknown',
        'unknown_field',
        'unknown_caller',
        'disabled',
        'truncated',
        'invalid_stop',
        'cancel',
      }.contains(mode),
      'invalid accepted',
    );
    var n = 0;
    while (result.status == RunStatus.interrupted) {
      check(
        executed.length == (mode == 'all' ? n * 3 : 0),
        'execution before approval',
      );
      if (mode == 'mixed' || mode == 'mixed_error') {
        check(regularCount == 0, 'mixed tool before batch approval');
      }
      final stored = await store.load(ownerId: 'owner', threadId: 'thread');
      check(
        jsonEncode(stored).contains('PRIVATE-CALL'),
        'private data missing',
      );
      check(
        !jsonEncode(chatHydration(stored)).contains('PRIVATE-CALL'),
        'UI leaked private data',
      );
      try {
        result.interrupts.first.approve(editedArgs: {});
        throw StateError('native edit accepted');
      } catch (e) {
        check(
          !e.toString().contains('native edit accepted'),
          'native edit accepted',
        );
      }
      final previous = result;
      result = await agent(mode == 'stale' ? 'desktop-2' : 'desktop-1')
          .generate(
            ChatRequest(
              threadId: 'thread',
              runId: 'run-${++n}',
              parentRunId: previous.runId,
              resume: [
                for (final interrupt in previous.interrupts)
                  mode == 'decline' ? interrupt.reject() : interrupt.approve(),
              ],
            ),
            ownerId: 'owner',
            context: null,
          );
      if (mode == 'stale') throw StateError('stale accepted');
      if (mode == 'decline') {
        check(
          executed.isEmpty && bodies.length == 1 && regularCount == 0,
          'decline side effects',
        );
        return;
      }
    }
    check(result.text == 'done', 'final text');
    if (mode == 'all') {
      check(
        jsonEncode(executed) == jsonEncode(actions.map((e) => e.$1).toList()),
        'all action order',
      );
    } else {
      check(executed.length == 1, 'single computer action');
      if (mode == 'mixed') check(regularCount == 1, 'mixed regular tool');
      if (mode == 'mixed_error') {
        check(regularCount == 0, 'mixed tool after error');
      }
    }
  } catch (e) {
    if (!{
      'unknown',
      'unknown_field',
      'unknown_caller',
      'disabled',
      'truncated',
      'invalid_stop',
      'cancel',
      'stale',
      'decline',
    }.contains(mode)) {
      rethrow;
    }
    check(!e.toString().contains('accepted'), '$mode unexpectedly accepted');
    check(
      executed.isEmpty &&
          regularCount == 0 &&
          bodies.length == (mode == 'cancel' ? 0 : 1),
      '$mode side effects',
    );
    if (mode == 'decline') {
      try {
        await agent().generate(
          ChatRequest(
            threadId: 'thread',
            runId: 'later',
            messages: [ChatMessage.user('Again', id: 'again')],
          ),
          ownerId: 'owner',
          context: null,
        );
        throw StateError('declined thread reused');
      } catch (e) {
        check(
          !e.toString().contains('declined thread reused'),
          'declined thread reused',
        );
      }
      check(
        bodies.length == 1 && executed.isEmpty,
        'declined thread had side effects',
      );
    }
  } finally {
    client.close();
    await server.close(force: true);
  }
}
