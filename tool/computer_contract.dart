import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;

Future<void> main() async {
  api.OpenAIComputerScreenshot execute(
    api.OpenAIComputerCall _,
    ToolContext<void> _,
  ) => api.OpenAIComputerScreenshot.fileId('file');
  final tool = api.OpenAIComputerTool<void>(
    environmentId: 'env',
    execute: execute,
  );
  final previews = [
    for (final environment in api.ComputerEnvironment.values)
      api.OpenAIComputerTool<void>.preview(
        environmentId: 'env',
        width: 800,
        height: 600,
        environment: environment,
        execute: execute,
      ).definition.definition,
  ];
  final call = api.OpenAIComputerCall.fromJson({
    'type': 'computer_call',
    'id': 'item',
    'call_id': 'call',
    'status': 'completed',
    'actions': [
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
      {'type': 'type', 'text': 'text'},
      {'type': 'wait'},
    ],
  });
  final context = ToolContext<void>(
    value: null,
    ownerId: 'o',
    threadId: 't',
    runId: 'r',
    toolCallId: 'call',
    cancellation: CancellationToken(),
    approved: true,
  );
  final withCheck = {
    ...call.raw,
    'pending_safety_checks': [
      {'id': 'check', 'code': 'warning', 'message': 'review'},
    ],
  };
  final result = {
    'ga': tool.definition.definition,
    'preview': previews,
    'call': call.raw,
    'screenshots': [
      api.OpenAIComputerScreenshot.url(
        'https://example.com/image.png',
        detail: api.ImageDetail.original,
      ).toJson(),
      api.OpenAIComputerScreenshot.fileId(
        'file',
        detail: api.ImageDetail.original,
      ).toJson(),
    ],
    'output': await tool.invoke(call.raw, context),
    'outputWithCheck': await tool.invoke(withCheck, context),
  };
  final file = File('.dart_tool/computer-options.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(result));
}
