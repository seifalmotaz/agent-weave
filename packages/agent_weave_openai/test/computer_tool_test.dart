import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:test/test.dart';

JsonObject call({List<Object?>? checks}) => {
  'type': 'computer_call',
  'id': 'item',
  'call_id': 'call',
  'status': 'completed',
  'actions': [
    {'type': 'click', 'button': 'left', 'x': 1, 'y': 2},
    {'type': 'screenshot'},
  ],
  'pending_safety_checks': ?checks,
};
ToolContext<void> context({
  bool approved = false,
  String toolCallId = 'call',
}) => ToolContext(
  value: null,
  ownerId: 'o',
  threadId: 't',
  runId: 'r',
  toolCallId: toolCallId,
  cancellation: CancellationToken(),
  approved: approved,
);

void main() {
  test('unknown action and drag fields fail before the executor', () async {
    var executions = 0;
    final tool = openai.OpenAIComputerTool<void>(
      environmentId: 'env',
      execute: (_, _) {
        executions++;
        return openai.OpenAIComputerScreenshot.fileId('file');
      },
    );
    for (final action in [
      {
        'type': 'click',
        'x': 1,
        'y': 2,
        'button': 'left',
        'modifiers': ['ALT'],
      },
      {
        'type': 'drag',
        'path': [
          {'x': 1, 'y': 2, 'pressure': 0.5},
        ],
      },
    ]) {
      await expectLater(
        tool.invoke(call()..['actions'] = [action], context(approved: true)),
        throwsFormatException,
      );
    }
    expect(executions, 0);
  });

  test(
    'computer context identity is validated before invoking the executor',
    () async {
      var executions = 0;
      final tool = openai.OpenAIComputerTool<void>(
        environmentId: 'env',
        execute: (_, _) {
          executions++;
          return openai.OpenAIComputerScreenshot.url(
            'data:image/png;base64,aGVsbG8=',
          );
        },
      );
      await expectLater(
        tool.invoke(
          call(),
          context(approved: true, toolCallId: 'another-call'),
        ),
        throwsFormatException,
      );
      expect(executions, 0);
    },
  );

  test('all supported action parameters survive the typed driver boundary', () {
    final actions = <JsonObject>[
      {
        'type': 'click',
        'button': 'forward',
        'x': 1,
        'y': 2,
        'keys': ['SHIFT'],
      },
      {
        'type': 'double_click',
        'x': 3,
        'y': 4,
        'keys': ['ALT'],
      },
      {
        'type': 'drag',
        'path': [
          {'x': 1, 'y': 2},
          {'x': 3, 'y': 4},
        ],
        'keys': ['CTRL'],
      },
      {
        'type': 'keypress',
        'keys': ['CTRL', 'A'],
      },
      {
        'type': 'move',
        'x': 5,
        'y': 6,
        'keys': ['SHIFT'],
      },
      {'type': 'screenshot'},
      {
        'type': 'scroll',
        'x': 7,
        'y': 8,
        'scroll_x': -2,
        'scroll_y': 20,
        'keys': ['SHIFT'],
      },
      {'type': 'type', 'text': 'مرحبا Flutter'},
      {'type': 'wait'},
    ];
    final call = openai.OpenAIComputerCall.fromJson({
      'type': 'computer_call',
      'id': 'item',
      'call_id': 'call',
      'status': 'completed',
      'actions': actions,
    });
    expect(call.actions.map((action) => action.toJson()).toList(), actions);
    for (final action in call.actions) {
      final keys = action.toJson()['keys'];
      if (keys is List) {
        expect(() => keys.add('CHANGED'), throwsUnsupportedError);
      }
    }
  });

  test('validates all actions and approval before executor', () async {
    var count = 0;
    final tool = openai.OpenAIComputerTool<void>(
      environmentId: 'env',
      approval: openai.ComputerApproval.safetyChecks,
      execute: (input, context) {
        count++;
        expect(input.actions, hasLength(2));
        return openai.OpenAIComputerScreenshot(
          imageUrl: 'data:image/png;base64,AA==',
        );
      },
    );
    final checks = [
      {'id': 'check', 'code': 'unknown'},
    ];
    await expectLater(
      tool.invoke(call(checks: checks), context()),
      throwsStateError,
    );
    final invalid = call()
      ..['actions'] = [
        {'type': 'screenshot'},
        {'type': 'future'},
      ];
    await expectLater(tool.invoke(invalid, context()), throwsFormatException);
    expect(count, 0);
    final result =
        await tool.invoke(call(checks: checks), context(approved: true)) as Map;
    expect(result['acknowledged_safety_checks'], checks);
    expect(count, 1);
  });

  test(
    'serializes computer call output, retaining reasoning and omitting absent checks',
    () async {
      final tool = openai.OpenAIComputerTool<void>(
        environmentId: 'env',
        execute: (_, _) => openai.OpenAIComputerScreenshot(fileId: 'file'),
      );
      final raw = call();
      final nativeCall = NativeToolCall(
        id: 'call',
        name: 'computer',
        arguments: raw,
        provider: 'openai.responses',
      );
      JsonObject? captured;
      final model = openai.ResponsesProtocolModel(
        model: 'model',
        transport: (request, _) async* {
          captured = request.toJson();
          yield {
            'type': 'response.completed',
            'response': {
              'status': 'completed',
              'output': [raw],
            },
          };
        },
      );
      final events = await model
          .stream(
            ModelRequest(
              tools: [tool.definition],
              messages: [
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  toolCalls: [nativeCall],
                  providerData: {
                    'openai.responses': [
                      {'type': 'reasoning', 'id': 'reason'},
                      raw,
                    ],
                  },
                ),
                ChatMessage(
                  id: 'b',
                  role: MessageRole.tool,
                  toolCallId: 'call',
                  content: [
                    TextPart(
                      jsonEncode({
                        'output': {
                          'type': 'computer_screenshot',
                          'file_id': 'file',
                        },
                      }),
                    ),
                  ],
                ),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      expect((captured!['tools'] as List).single, {'type': 'computer'});
      final input = captured!['input'] as List;
      expect(input.first['type'], 'reasoning');
      expect(input.last, {
        'type': 'computer_call_output',
        'call_id': 'call',
        'output': {'type': 'computer_screenshot', 'file_id': 'file'},
      });
      expect(events.whereType<NativeToolCallReady>().single.call.id, 'call');
    },
  );

  test('rejects unknown namespaces and duplicate profiles', () async {
    final tool = openai.OpenAIComputerTool<void>(
      environmentId: 'env',
      execute: (_, _) => openai.OpenAIComputerScreenshot(fileId: 'f'),
    );
    final model = openai.ResponsesProtocolModel(
      model: 'm',
      providerDataKey: 'other',
      transport: (_, _) => const Stream.empty(),
    );
    await expectLater(
      model
          .stream(
            ModelRequest(messages: [], tools: [tool.definition]),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsUnsupportedError,
    );
    final openModel = openai.ResponsesProtocolModel(
      model: 'm',
      transport: (_, _) => const Stream.empty(),
    );
    await expectLater(
      openModel
          .stream(
            ModelRequest(
              messages: [],
              tools: [tool.definition, tool.definition],
            ),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsUnsupportedError,
    );
  });
  test('legacy profile and exact safety acknowledgements', () async {
    final tool = openai.OpenAIComputerTool<void>.preview(
      environmentId: 'env',
      width: 800,
      height: 600,
      environment: openai.ComputerEnvironment.browser,
      approval: openai.ComputerApproval.safetyChecks,
      execute: (_, _) => openai.OpenAIComputerScreenshot(fileId: 'f'),
    );
    final legacy = <String, Object?>{
      'type': 'computer_call',
      'id': 'i',
      'call_id': 'c',
      'status': 'completed',
      'action': {'type': 'wait'},
      'pending_safety_checks': [
        {'id': 'check', 'message': 'review'},
      ],
    };
    final result = await tool.invoke(
      legacy,
      context(approved: true, toolCallId: 'c'),
    );
    final native = NativeToolCall(
      id: 'c',
      name: 'computer',
      arguments: legacy,
      provider: 'openai.responses',
      requiresApproval: true,
    );
    final assistant = ChatMessage(
      id: 'a',
      role: MessageRole.assistant,
      toolCalls: [native],
      providerData: {
        'openai.responses': [legacy],
      },
    );
    JsonObject? captured;
    final model = openai.ResponsesProtocolModel(
      model: 'm',
      transport: (request, _) async* {
        captured = request.toJson();
        yield {
          'type': 'response.completed',
          'response': {'output': <Object?>[]},
        };
      },
    );
    Future<List<ModelEvent>> run(Object? output) => model
        .stream(
          ModelRequest(
            tools: [tool.definition],
            messages: [
              assistant,
              ChatMessage(
                id: 'b',
                role: MessageRole.tool,
                toolCallId: 'c',
                content: [TextPart(jsonEncode(output))],
              ),
            ],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    await run(result);
    expect((captured!['tools'] as List).single, {
      'type': 'computer_use_preview',
      'display_width': 800,
      'display_height': 600,
      'environment': 'browser',
    });
    expect(
      ((captured!['input'] as List).last as Map)['acknowledged_safety_checks'],
      legacy['pending_safety_checks'],
    );
    await expectLater(
      run({
        'output': {'type': 'computer_screenshot', 'file_id': 'f'},
        'acknowledged_safety_checks': [
          {'id': 'other'},
        ],
      }),
      throwsFormatException,
    );
    await expectLater(run({'error': 'failed'}), throwsFormatException);
  });

  test('computer item is never emitted before a terminal response', () async {
    final tool = openai.OpenAIComputerTool<void>(
      environmentId: 'env',
      execute: (_, _) => openai.OpenAIComputerScreenshot(fileId: 'f'),
    );
    final events = <ModelEvent>[];
    final model = openai.ResponsesProtocolModel(
      model: 'm',
      transport: (_, _) async* {
        yield {'type': 'response.output_item.done', 'item': call()};
      },
    );
    await expectLater(
      model
          .stream(
            ModelRequest(messages: [], tools: [tool.definition]),
            cancellation: CancellationToken(),
          )
          .map((event) {
            events.add(event);
            return event;
          })
          .toList(),
      throwsStateError,
    );
    expect(events.whereType<NativeToolCallReady>(), isEmpty);
  });
  test('provider extras stay private and drag data is immutable', () async {
    final raw = <String, Object?>{
      'type': 'computer_call',
      'id': 'i',
      'call_id': 'c',
      'status': 'completed',
      'private_extra': 'secret',
      'actions': [
        {
          'type': 'drag',
          'path': [
            {'x': 1, 'y': 2},
          ],
          'keys': ['shift'],
        },
      ],
      'pending_safety_checks': [
        {'id': 'check', 'private_extra': 'secret'},
      ],
    };
    final parsed = openai.OpenAIComputerCall.fromJson(raw);
    expect(jsonEncode(parsed.raw), isNot(contains('secret')));
    final drag = parsed.actions.single as openai.DragAction;
    expect(() => drag.path.add({'x': 2, 'y': 3}), throwsUnsupportedError);
    expect(() => drag.path.first['x'] = 4, throwsUnsupportedError);
    expect(() => drag.keys!.add('alt'), throwsUnsupportedError);
    final tool = openai.OpenAIComputerTool<void>(
      environmentId: 'env',
      execute: (_, _) => openai.OpenAIComputerScreenshot.url(
        'data:image/png;base64,AA==',
        detail: openai.ImageDetail.original,
      ),
    );
    final model = openai.ResponsesProtocolModel(
      model: 'm',
      transport: (_, _) async* {
        yield {
          'type': 'response.completed',
          'response': {
            'status': 'completed',
            'output': [raw],
          },
        };
      },
    );
    final events = await model
        .stream(
          ModelRequest(messages: [], tools: [tool.definition]),
          cancellation: CancellationToken(),
        )
        .toList();
    expect(
      jsonEncode(events.whereType<NativeToolCallReady>().single.call.arguments),
      isNot(contains('secret')),
    );
    expect(
      jsonEncode(events.whereType<ProviderOutput>().single.items),
      contains('secret'),
    );
    expect(
      openai.OpenAIComputerScreenshot.fileId(
        'f',
        detail: openai.ImageDetail.original,
      ).toJson()['detail'],
      'original',
    );
  });
  test('all preview environments serialize using their wire values', () async {
    for (final environment in openai.ComputerEnvironment.values) {
      final tool = openai.OpenAIComputerTool<void>.preview(
        environmentId: 'env',
        width: 800,
        height: 600,
        environment: environment,
        execute: (_, _) => openai.OpenAIComputerScreenshot.fileId('f'),
      );
      JsonObject? captured;
      final model = openai.ResponsesProtocolModel(
        model: 'm',
        transport: (request, _) async* {
          captured = request.toJson();
          yield {
            'type': 'response.completed',
            'response': {'status': 'completed', 'output': <Object?>[]},
          };
        },
      );
      await model
          .stream(
            ModelRequest(messages: [], tools: [tool.definition]),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(
        (captured!['tools'] as List).single['environment'],
        environment.name,
      );
    }
  });
  for (final status in ['failed', 'incomplete', 'in_progress']) {
    test('no computer event for response status $status', () async {
      final tool = openai.OpenAIComputerTool<void>(
        environmentId: 'env',
        execute: (_, _) => openai.OpenAIComputerScreenshot.fileId('f'),
      );
      final events = <ModelEvent>[];
      final model = openai.ResponsesProtocolModel(
        model: 'm',
        transport: (_, _) async* {
          yield {
            'type': 'response.completed',
            'response': {
              'status': status,
              'output': [call()],
            },
          };
        },
      );
      await expectLater(
        model
            .stream(
              ModelRequest(messages: [], tools: [tool.definition]),
              cancellation: CancellationToken(),
            )
            .map((event) {
              events.add(event);
              return event;
            })
            .toList(),
        throwsFormatException,
      );
      expect(events.whereType<NativeToolCallReady>(), isEmpty);
    });
  }
  test('rejects malformed screenshot data URLs', () {
    expect(
      () => openai.OpenAIComputerScreenshot.url('data:image/png;base64,!!!'),
      throwsFormatException,
    );
    expect(
      () => openai.OpenAIComputerScreenshot.url('data:image/png;base64,'),
      throwsFormatException,
    );
  });
}
