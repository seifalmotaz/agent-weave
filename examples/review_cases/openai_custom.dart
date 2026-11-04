import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void check(bool v, String m) {
  if (!v) throw StateError(m);
}

Future<void> main() async {
  for (final mode in ['approve', 'deny', 'invalid']) {
    final bodies = <Map<String, dynamic>>[];
    var effects = 0;
    final transport = MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      final item = {
        'type': 'custom_tool_call',
        'id': 'private-item',
        'call_id': 'call-1',
        'name': 'lookup',
        'input': mode == 'invalid' ? 'DROP TABLE' : 'TICKET-42',
        'status': 'completed',
        'private_field': 'PRIVATE-REPLAY',
      };
      final result = {
        'type': 'message',
        'id': 'answer',
        'role': 'assistant',
        'status': 'completed',
        'content': [
          {'type': 'output_text', 'text': 'Done', 'annotations': <Object?>[]},
        ],
      };
      final output = bodies.length == 1 ? [item] : [result];
      final ev = <Object?>[
        if (bodies.length == 1)
          {
            'type': 'response.output_item.done',
            'sequence_number': 0,
            'output_index': 0,
            'item': item,
          }
        else
          {'type': 'response.output_text.delta', 'delta': 'Done'},
        {
          'type': 'response.completed',
          'response': {'status': 'completed', 'output': output},
        },
      ];
      return http.Response(
        '${ev.map((e) => 'data: ${jsonEncode(e)}\n\n').join()}data: [DONE]\n\n',
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final client = api.OpenAIClient(
      config: const api.OpenAIConfig(
        authProvider: api.ApiKeyProvider('fixture'),
      ),
      streamClientFactory: () => transport,
    );
    final store = MemoryRunStore();
    AiAgent<void> agent() => AiAgent<void>(
      store: store,
      model: api.OpenAIResponsesModel.native(client: client, model: 'fixture'),
      tools: [
        api.OpenAICustomTool<void>(
          name: 'lookup',
          bindingId: 'support-v1',
          description: 'Read ticket status',
          needsApproval: true,
          format: api.OpenAICustomToolFormat.grammar(
            r'TICKET-[0-9]+',
            syntax: api.OpenAICustomGrammarSyntax.regex,
          ),
          execute: (input, context) {
            if (!RegExp(r'^TICKET-[0-9]+$').hasMatch(input)) {
              return api.OpenAICustomToolResult.error('Invalid ticket');
            }
            effects++;
            return api.OpenAICustomToolResult.text('open');
          },
        ),
      ],
    );
    try {
      final paused = await agent().generate(
        ChatRequest(
          threadId: 't',
          runId: 'first',
          messages: [ChatMessage.user('Look up ticket', id: 'm')],
        ),
        ownerId: 'owner',
        context: null,
      );
      check(
        paused.status == RunStatus.interrupted &&
            effects == 0 &&
            bodies.length == 1,
        '$mode did not pause',
      );
      final definition = (bodies.first['tools'] as List)
          .whereType<Map<dynamic, dynamic>>()
          .single;
      check(
        definition['type'] == 'custom' &&
            definition['name'] == 'lookup' &&
            definition['format']['syntax'] == 'regex' &&
            definition['format']['definition'] == r'TICKET-[0-9]+',
        'native grammar configuration missing',
      );
      final interrupt = paused.interrupts.single;
      check(
        jsonEncode(interrupt.call.arguments) ==
            jsonEncode({
              'input': mode == 'invalid' ? 'DROP TABLE' : 'TICKET-42',
            }),
        '$mode public arguments leaked extras: ${interrupt.call.arguments}',
      );
      final hydration = jsonEncode(
        chatHydration(await store.load(ownerId: 'owner', threadId: 't')),
      );
      check(
        !hydration.contains('PRIVATE-REPLAY') &&
            !hydration.contains('private-item'),
        'private output leaked',
      );
      final result = await agent().generate(
        ChatRequest(
          threadId: 't',
          runId: 'second',
          parentRunId: paused.runId,
          resume: [mode == 'deny' ? interrupt.reject() : interrupt.approve()],
        ),
        ownerId: 'owner',
        context: null,
      );
      check(
        result.text == 'Done' &&
            bodies.length == 2 &&
            effects == (mode == 'approve' ? 1 : 0),
        '$mode result/effects',
      );
      final items = (bodies.last['input'] as List)
          .whereType<Map<dynamic, dynamic>>()
          .toList();
      final original = items.singleWhere(
        (v) => v['type'] == 'custom_tool_call',
      );
      final output = items.singleWhere(
        (v) => v['type'] == 'custom_tool_call_output',
      );
      check(
        original['private_field'] == 'PRIVATE-REPLAY' &&
            original['input'] ==
                (mode == 'invalid' ? 'DROP TABLE' : 'TICKET-42'),
        'private replay lost',
      );
      check(
        output['output'] ==
                (mode == 'approve'
                    ? 'open'
                    : mode == 'deny'
                    ? 'Tool call declined.'
                    : 'Invalid ticket') &&
            output['call_id'] == 'call-1' &&
            !items.any((v) => v['type'] == 'function_call_output'),
        'wrong output format',
      );
      print('PASS $mode: effects=$effects, custom output=${output['output']}');
    } finally {
      client.close();
      transport.close();
    }
  }
}
