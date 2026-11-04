import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/src/computer_tool.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as api;
import 'package:test/test.dart';

Map<String, dynamic> call(String name, Map<String, dynamic> input) => {
  'type': 'tool_use',
  'id': 'id',
  'name': name,
  'toolset_name': 'computer',
  'input': input,
};

void main() {
  test('successful screenshot and zoom require image results', () async {
    var executions = 0;
    final tool = AnthropicComputerTool<void>(
      environmentId: 'desktop',
      execute: (_, _) {
        executions++;
        return AnthropicComputerResult.empty();
      },
    );
    final context = ToolContext<void>(
      value: null,
      ownerId: 'owner',
      threadId: 'thread',
      runId: 'run',
      toolCallId: 'id',
      cancellation: CancellationToken(),
      approved: true,
    );
    for (final (name, input) in <(String, JsonObject)>[
      ('screenshot', {}),
      (
        'zoom',
        {
          'region': [0, 0, 10, 10],
        },
      ),
    ]) {
      await expectLater(
        tool.invoke(call(name, input), context),
        throwsFormatException,
      );
      AnthropicComputerCall.fromJson(
        call(name, input),
      ).validateResult(AnthropicComputerResult.error('capture failed'));
    }
    expect(executions, 2);
  });

  final cases = <String, Map<String, dynamic>>{
    'key': {'text': 'A', 'repeat': 2},
    'hold_key': {'text': 'A', 'duration': 2},
    'type': {'text': 'x'},
    'cursor_position': {},
    'mouse_move': {
      'coordinate': [1, 2],
    },
    'left_mouse_down': {},
    'left_mouse_up': {},
    'left_click': {
      'coordinate': [1, 2],
      'text': 'shift',
    },
    'left_click_drag': {
      'coordinate': [1, 2],
      'start_coordinate': [3, 4],
      'text': 'shift',
    },
    'right_click': {},
    'middle_click': {},
    'double_click': {},
    'triple_click': {},
    'scroll': {'scroll_amount': 2, 'scroll_direction': 'down'},
    'wait': {'duration': 1},
    'screenshot': {},
    'zoom': {
      'region': [0, 0, 1, 1],
    },
  };
  test('parses every member and rejects unknown fields', () {
    for (final entry in cases.entries) {
      final parsed = AnthropicComputerCall.fromJson({
        ...call(entry.key, entry.value),
        'private': 'secret',
      });
      expect(parsed.id, 'id');
      expect(parsed.raw.containsKey('private'), false);
      expect(
        () => AnthropicComputerCall.fromJson(
          call(entry.key, {...entry.value, 'unknown': true}),
        ),
        throwsFormatException,
      );
      expect(() => parsed.raw['id'] = 'other', throwsUnsupportedError);
    }
  });
  test(
    'checks approval, identity, and disabled member before execution',
    () async {
      var calls = 0;
      final tool = AnthropicComputerTool<void>(
        environmentId: 'machine',
        configs: const api.ComputerToolsetConfigs(
          screenshot: api.ToolsetMemberConfig(enabled: false),
        ),
        execute: (call, context) {
          calls++;
          return AnthropicComputerResult.text('ok');
        },
      );
      ToolContext<void> context({bool approved = false, String id = 'id'}) =>
          ToolContext(
            value: null,
            ownerId: 'o',
            threadId: 't',
            runId: 'r',
            toolCallId: id,
            cancellation: CancellationToken(),
            approved: approved,
          );
      await expectLater(
        tool.invoke(call('screenshot', {}), context(approved: true)),
        throwsFormatException,
      );
      await expectLater(
        tool.invoke(
          call('wait', {'duration': 1}),
          context(id: 'wrong', approved: true),
        ),
        throwsFormatException,
      );
      await expectLater(
        tool.invoke(call('wait', {'duration': 1}), context()),
        throwsStateError,
      );
      expect(
        await tool.invoke(
          call('wait', {'duration': 1}),
          context(approved: true),
        ),
        {
          'content': [
            {'type': 'text', 'text': 'ok'},
          ],
        },
      );
      expect(calls, 1);
    },
  );
  test('validates config and results', () {
    expect(
      () => AnthropicComputerTool<void>(
        environmentId: 'machine',
        configs: const api.ComputerToolsetConfigs(
          key: api.ToolsetMemberConfig(deferLoading: true),
        ),
        execute: (_, _) => AnthropicComputerResult.empty(),
      ),
      throwsFormatException,
    );
    expect(
      () => AnthropicComputerResult(
        content: [
          api.InputContentBlock.thinking(thinking: 'x', signature: 's'),
        ],
      ),
      throwsArgumentError,
    );
    expect(AnthropicComputerResult.error('bad').toJson()['is_error'], true);
  });
  test('direct callers, limits, and sequential failure result', () {
    final tool = AnthropicComputerTool<void>(
      environmentId: 'machine',
      allowedCallers: ['direct'],
      execute: (_, _) => AnthropicComputerResult.empty(),
    );
    expect(tool.definition.definition['allowed_callers'], ['direct']);
    expect(
      () => AnthropicComputerTool<void>(
        environmentId: 'machine',
        allowedCallers: ['server'],
        execute: (_, _) => AnthropicComputerResult.empty(),
      ),
      throwsFormatException,
    );
    expect(
      () => AnthropicComputerCall.fromJson(
        call('key', {'text': 'a', 'repeat': 101}),
      ),
      throwsFormatException,
    );
    expect(
      () => AnthropicComputerCall.fromJson(
        call('hold_key', {'text': 'a', 'duration': 301}),
      ),
      throwsFormatException,
    );
    expect(
      () => AnthropicComputerCall.fromJson(call('wait', {'duration': 301})),
      throwsFormatException,
    );
    expect(
      tool.isFailure(AnthropicComputerResult.error('bad').toJson()),
      isTrue,
    );
    expect(
      tool.isFailure(AnthropicComputerResult.text('ok').toJson()),
      isFalse,
    );
    expect(tool.skippedResult(), {
      'content': [
        {
          'type': 'text',
          'text':
              'Not executed: an earlier computer action in this turn failed.',
        },
      ],
      'is_error': true,
    });
  });
  test('typed coordinates and result round trip preserve the wire values', () {
    final input = <num>[1, 2];
    final parsed = AnthropicComputerCall.fromJson(
      call('mouse_move', {'coordinate': input}),
    );
    input[0] = 9;
    expect((parsed.action as AnthropicComputerMove).coordinate, (x: 1, y: 2));
    expect((parsed.raw['input'] as Map)['coordinate'], [1, 2]);
    expect(
      () => AnthropicComputerCall.fromJson(
        call('mouse_move', {
          'coordinate': [1],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => AnthropicComputerCall.fromJson(
        call('zoom', {
          'region': [1, 2],
        }),
      ),
      throwsFormatException,
    );
    final scroll = AnthropicComputerCall.fromJson(
      call('scroll', {'scroll_amount': 1, 'scroll_direction': 'left'}),
    );
    expect(
      (scroll.action as AnthropicComputerScroll).direction,
      AnthropicComputerScrollDirection.left,
    );
    expect(
      () => AnthropicComputerCall.fromJson(
        call('scroll', {'scroll_amount': 1, 'scroll_direction': 'other'}),
      ),
      throwsFormatException,
    );
    final json = {
      'content': [
        {
          'type': 'image',
          'source': {'type': 'url', 'url': 'https://example.com/image.png'},
        },
      ],
      'is_error': true,
    };
    expect(AnthropicComputerResult.fromJson(json).toJson(), json);
    expect(
      () => AnthropicComputerResult.fromJson({
        'content': [
          {'type': 'text', 'text': 'x', 'unknown': true},
        ],
      }),
      throwsFormatException,
    );
  });
}
