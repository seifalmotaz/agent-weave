import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

final actions = <Object?>[
  {'type': 'click', 'button': 'left', 'x': 1, 'y': 2},
  {'type': 'double_click', 'x': 1, 'y': 2},
  {
    'type': 'drag',
    'path': [
      {'x': 1, 'y': 2},
      {'x': 3, 'y': 4},
    ],
  },
  {
    'type': 'keypress',
    'keys': ['ENTER'],
  },
  {'type': 'move', 'x': 3, 'y': 4},
  {'type': 'screenshot'},
  {'type': 'scroll', 'x': 1, 'y': 2, 'scroll_x': 0, 'scroll_y': 10},
  {'type': 'type', 'text': 'hello'},
  {'type': 'wait'},
];
final reasoning = <String, Object?>{
  'type': 'reasoning',
  'id': 'reason',
  'summary': <Object?>[],
  'encrypted_content': 'PRIVATE-OPAQUE',
};
JsonObject call({bool legacy = false, bool safety = false}) => {
  'type': 'computer_call',
  'id': 'item-id',
  'call_id': 'call-id',
  'status': 'completed',
  'private_extra': 'PRIVATE-CALL',
  if (legacy) 'action': {'type': 'wait'} else 'actions': actions,
  if (legacy || safety)
    'pending_safety_checks': safety
        ? [
            {'id': 'check', 'message': 'review'},
          ]
        : <Object?>[],
};

class Session {
  final String user;
  Session(this.user);
}

Future<void> main() async {
  await wrongKinds();
  for (final mode in [
    'default',
    'safety',
    'legacy',
    'benign',
    'reject',
    'stale',
    'invalid',
    'unknown_action_key',
    'unknown_modifier',
    'unknown_drag_key',
    'truncated',
    'malformed',
    'edited',
    'cancel',
  ]) {
    await journey(mode);
    print('PASS $mode');
  }
}

Future<void> journey(String mode) async {
  final bodies = <Map<String, Object?>>[];
  var executions = 0;
  var terminalSent = false;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final raw = call(
    legacy: mode == 'legacy',
    safety: mode == 'safety' || mode == 'legacy',
  );
  if (mode == 'invalid') {
    raw['actions'] = [
      {'type': 'screenshot'},
      {'type': 'unknown'},
    ];
  }
  if (mode == 'unknown_action_key') {
    raw['actions'] = [
      {'type': 'click', 'button': 'left', 'x': 1, 'y': 2, 'surprise': true},
    ];
  }
  if (mode == 'unknown_modifier') {
    raw['actions'] = [
      {
        'type': 'click',
        'button': 'left',
        'x': 1,
        'y': 2,
        'modifiers': ['SHIFT'],
      },
    ];
  }
  if (mode == 'unknown_drag_key') {
    raw['actions'] = [
      {
        'type': 'drag',
        'path': [
          {'x': 1, 'y': 2, 'surprise': true},
        ],
      },
    ];
  }
  server.listen((req) async {
    bodies.add(
      jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, Object?>,
    );
    check(req.uri.path == '/v1/responses', 'Responses path');
    req.response.headers.contentType = ContentType('text', 'event-stream');
    void send(Object event) =>
        req.response.write('data: ${jsonEncode(event)}\n\n');
    if (mode == 'malformed') {
      req.response.add([100, 97, 116, 97, 58, 32, 255, 10, 10]);
      await req.response.close();
      return;
    }
    if (bodies.length == 1) {
      send({
        'type': 'response.output_item.done',
        'sequence_number': 0,
        'output_index': 1,
        'item': raw,
      });
      await req.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      check(executions == 0, 'Executed before terminal event');
      if (mode != 'truncated') {
        terminalSent = true;
        send({
          'type': 'response.completed',
          'sequence_number': 1,
          'response': {
            'id': 'r1',
            'object': 'response',
            'created_at': 0,
            'status': 'completed',
            'model': 'local',
            'output': [reasoning, raw],
          },
        });
      }
    } else {
      send({
        'type': 'response.output_text.delta',
        'sequence_number': 0,
        'item_id': 'final',
        'output_index': 0,
        'content_index': 0,
        'delta': 'done',
      });
      send({
        'type': 'response.completed',
        'sequence_number': 1,
        'response': {
          'id': 'r2',
          'object': 'response',
          'created_at': 0,
          'status': 'completed',
          'model': 'local',
          'output': <Object?>[],
        },
      });
    }
    req.response.write('data: [DONE]\n\n');
    await req.response.close();
  });
  final client = openai.OpenAIClient(
    config: openai.OpenAIConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      authProvider: openai.ApiKeyProvider('fixture'),
    ),
  );
  final store = MemoryRunStore();
  openai.OpenAIComputerTool<Session> tool(String environment) {
    openai.OpenAIComputerScreenshot execute(
      openai.OpenAIComputerCall call,
      ToolContext<Session> ctx,
    ) {
      check(terminalSent, 'Executor before terminal');
      check(
        ctx.value.user == 'trusted' && ctx.idempotencyKey.isNotEmpty,
        'Context/idempotency',
      );
      check(mode == 'benign' || ctx.approved, 'Missing approval');
      check(call.actions.length == (mode == 'legacy' ? 1 : 9), 'Whole batch');
      if (mode != 'legacy') {
        check(
          jsonEncode(call.actions.map((a) => a.toJson()['type']).toList()) ==
              jsonEncode(actions.map((a) => (a as Map)['type']).toList()),
          'Action order',
        );
      }
      executions++;
      return openai.OpenAIComputerScreenshot(fileId: 'fresh-$executions');
    }

    if (mode == 'legacy') {
      return openai.OpenAIComputerTool<Session>.preview(
        environmentId: environment,
        width: 800,
        height: 600,
        environment: openai.ComputerEnvironment.browser,
        approval: openai.ComputerApproval.safetyChecks,
        execute: execute,
      );
    }
    return openai.OpenAIComputerTool<Session>(
      environmentId: environment,
      approval: mode == 'benign' || mode == 'safety'
          ? openai.ComputerApproval.safetyChecks
          : openai.ComputerApproval.always,
      execute: execute,
    );
  }

  AiAgent<Session> agent([String env = 'desktop-1']) => AiAgent(
    model: openai.OpenAIResponsesModel(client: client, model: 'local'),
    store: store,
    tools: [tool(env)],
  );
  try {
    try {
      final token = CancellationToken();
      if (mode == 'cancel') token.cancel();
      final paused = await agent().generate(
        ChatRequest(
          threadId: 'thread',
          runId: 'one',
          messages: [ChatMessage.user('Inspect', id: 'user')],
        ),
        ownerId: 'owner',
        context: Session('trusted'),
        cancellation: token,
      );
      if ({
        'invalid',
        'unknown_action_key',
        'unknown_modifier',
        'unknown_drag_key',
        'truncated',
        'malformed',
      }.contains(mode)) {
        throw StateError('Invalid stream accepted');
      }
      if (mode == 'benign') {
        check(executions == 1 && bodies.length == 2, 'Benign auto execution');
        return;
      }
      check(
        paused.status == RunStatus.interrupted && executions == 0,
        'Approval pause',
      );
      final stored = await store.load(ownerId: 'owner', threadId: 'thread');
      check(
        jsonEncode(stored).contains('PRIVATE-CALL'),
        'Computer item absent from private store',
      );
      final hydration = jsonEncode(chatHydration(stored));
      check(
        !hydration.contains('PRIVATE-OPAQUE') &&
            !hydration.contains('PRIVATE-CALL'),
        'Private provider data leaked',
      );
      if (mode == 'edited') {
        try {
          paused.interrupts.single.approve(editedArgs: {'actions': []});
          throw StateError('Edit accepted');
        } catch (e) {
          check(!e.toString().contains('Edit accepted'), 'Edit accepted');
        }
        check(executions == 0 && bodies.length == 1, 'Edit side effects');
        return;
      }
      final resumed = await agent(mode == 'stale' ? 'desktop-2' : 'desktop-1')
          .generate(
            ChatRequest(
              threadId: 'thread',
              runId: 'two',
              parentRunId: paused.runId,
              resume: [
                mode == 'reject'
                    ? paused.interrupts.single.reject()
                    : paused.interrupts.single.approve(),
              ],
            ),
            ownerId: 'owner',
            context: Session('trusted'),
          );
      if (mode == 'stale') throw StateError('Stale environment approved');
      if (mode == 'reject') {
        check(executions == 0 && bodies.length == 1, 'Reject side effects');
        return;
      }
      check(
        resumed.text == 'done' && executions == 1 && bodies.length == 2,
        'Resume',
      );
      final input = bodies.last['input'] as List;
      check(
        jsonEncode(input).contains('PRIVATE-OPAQUE'),
        'Opaque reasoning not replayed',
      );
      check(
        jsonEncode(input).contains('PRIVATE-CALL'),
        'Opaque computer item not replayed',
      );
      final output = input.last as Map;
      check(
        output['type'] == 'computer_call_output' &&
            output['call_id'] == 'call-id',
        'Output call id',
      );
      check(
        (output['output'] as Map)['file_id'] == 'fresh-1',
        'Fresh screenshot',
      );
      check(
        output.containsKey('acknowledged_safety_checks') ==
            (mode == 'legacy' || mode == 'safety'),
        'Safety acknowledgement',
      );
    } catch (error) {
      if (!{
        'invalid',
        'unknown_action_key',
        'unknown_modifier',
        'unknown_drag_key',
        'truncated',
        'malformed',
        'stale',
        'reject',
        'cancel',
      }.contains(mode)) {
        rethrow;
      }
      check(
        executions == 0 && bodies.length == (mode == 'cancel' ? 0 : 1),
        '$mode side effects',
      );
      if (mode == 'reject') {
        try {
          await agent().generate(
            ChatRequest(
              threadId: 'thread',
              runId: 'three',
              messages: [ChatMessage.user('Again', id: 'again')],
            ),
            ownerId: 'owner',
            context: Session('trusted'),
          );
          throw StateError('Reuse accepted');
        } catch (e) {
          check(
            !e.toString().contains('Reuse accepted'),
            'Rejected thread reused',
          );
        }
        check(
          bodies.length == 1 && executions == 0,
          'Rejected thread reached provider',
        );
      }
      check(
        !error.toString().contains('accepted') &&
            !error.toString().contains('approved'),
        '$mode did not reject',
      );
    }
  } finally {
    client.close();
    await server.close(force: true);
  }
}

Future<void> wrongKinds() async {
  for (final event in [
    ToolCallReady(ToolCall(id: 'c', name: 'computer', arguments: call())),
    NativeToolCallReady(
      NativeToolCall(
        id: 'c',
        name: 'computer',
        arguments: call(),
        provider: 'other',
      ),
    ),
  ]) {
    var count = 0;
    final agent = AiAgent<void>(
      model: ScriptedChatModel(
        capabilities: const ModelCapabilities(tools: true),
        steps: [
          [event, const ModelFinished()],
        ],
      ),
      tools: [
        openai.OpenAIComputerTool<void>(
          environmentId: 'env',
          execute: (_, _) {
            count++;
            return openai.OpenAIComputerScreenshot(fileId: 'f');
          },
        ),
      ],
    );
    try {
      await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('go', id: 'u')],
        ),
        ownerId: 'o',
        context: null,
      );
      throw StateError('wrong kind accepted');
    } catch (e) {
      check(
        !e.toString().contains('wrong kind accepted') && count == 0,
        'wrong kind side effects',
      );
    }
  }
  print('PASS wrong tool kinds');
}
