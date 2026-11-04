import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';
import 'native_core_test.dart' show NativeTool;
import 'runtime_test.dart' as f;

final class SequentialTool extends NativeTool
    implements SequentialNativeTool<String> {
  final List<int> effects;
  final bool approval;
  final bool failFirst;
  final bool? expectedApproval;
  SequentialTool(
    this.effects, {
    this.approval = false,
    this.failFirst = true,
    this.expectedApproval,
  }) : super((_) {});
  @override
  bool get needsApproval => approval;
  @override
  bool isFailure(Object? result) => result is Map && result['failed'] == true;
  @override
  Object? skippedResult() => {'failed': true, 'skipped': true};
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<String> context) async {
    final value = input['count'] as int;
    effects.add(value);
    expect(context.approved, expectedApproval ?? approval);
    return {'failed': failFirst && value == 1};
  }
}

NativeToolCall call(int count, {bool approval = false}) => NativeToolCall(
  id: 'native-$count',
  name: 'computer',
  arguments: {'count': count},
  provider: 'example',
  requiresApproval: approval,
);

void main() {
  test(
    'failed native action skips later ordinary effects in the same turn',
    () async {
      final effects = <int>[];
      final store = MemoryRunStore();
      final agent = AiAgent<String>(
        store: store,
        tools: [
          SequentialTool(effects),
          f.tool(
            execute: (_, _) => fail('Later ordinary effect must not execute'),
          ),
        ],
        model: f.FakeModel([
          [
            NativeToolCallReady(call(1)),
            f.call(),
            NativeToolCallReady(call(2)),
            const ModelFinished(),
          ],
          [const ModelFinished()],
        ]),
      );
      await agent.generate(f.request(), ownerId: 'owner', context: 'x');
      expect(effects, [1]);
      final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      final results = (state['messages'] as List)
          .map((m) => ChatMessage.fromJson(Map<String, Object?>.from(m as Map)))
          .where((m) => m.role == MessageRole.tool)
          .toList();
      expect(results, hasLength(3));
      expect(jsonDecode(results[1].text), {
        'error': 'Not executed: an earlier native action in this turn failed.',
      });
      expect(jsonDecode(results[2].text), {'failed': true, 'skipped': true});
    },
  );

  for (final approval in [false, true]) {
    test(
      'failure skips later calls and resets next turn, approval=$approval',
      () async {
        final effects = <int>[];
        final store = MemoryRunStore();
        final agent = AiAgent<String>(
          store: store,
          tools: [SequentialTool(effects, approval: approval)],
          model: f.FakeModel([
            [
              NativeToolCallReady(call(1)),
              NativeToolCallReady(call(2)),
              const ModelFinished(),
            ],
            [NativeToolCallReady(call(3)), const ModelFinished()],
            [const ModelFinished()],
          ]),
        );
        var result = await agent.generate(
          f.request(),
          ownerId: 'owner',
          context: 'x',
        );
        var generation = 0;
        while (result.status == RunStatus.interrupted) {
          expect(approval, true);
          generation++;
          result = await agent.generate(
            f.request(
              run: 'resume-$generation',
              parent: result.runId,
              text: null,
              resume: result.interrupts.map((i) => i.approve()).toList(),
            ),
            ownerId: 'owner',
            context: 'x',
          );
        }
        expect(effects, [1, 3]);
        final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
        final messages = (state['messages'] as List).map(
          (m) => ChatMessage.fromJson(Map<String, Object?>.from(m as Map)),
        );
        final skipped = messages.singleWhere((m) => m.toolCallId == 'native-2');
        expect(jsonDecode(skipped.text), {'failed': true, 'skipped': true});
      },
    );
  }

  for (final forced in [false, true]) {
    test(
      'native approval pauses mixed ordinary effects, forced=$forced',
      () async {
        final order = <int>[];
        final native = SequentialTool(
          order,
          approval: !forced,
          expectedApproval: true,
          failFirst: false,
        );
        final agent = AiAgent<String>(
          tools: [
            native,
            f.tool(
              execute: (n, context) {
                expect(context.approved, true);
                order.add(n);
                return n;
              },
            ),
          ],
          model: f.FakeModel([
            [
              NativeToolCallReady(call(1, approval: forced)),
              f.call(),
              const ModelFinished(),
            ],
            [const ModelFinished()],
          ]),
        );
        final first = await agent.generate(
          f.request(),
          ownerId: 'owner',
          context: 'x',
        );
        expect(first.interrupts, hasLength(2));
        expect(order, isEmpty);
        await agent.generate(
          f.request(
            run: 'resume',
            parent: first.runId,
            text: null,
            resume: first.interrupts.map((i) => i.approve()).toList(),
          ),
          ownerId: 'owner',
          context: 'x',
        );
        expect(order, [1, 2]);
      },
    );
  }

  test('pending approval binds the sequential result policy', () async {
    final store = MemoryRunStore();
    final original = AiAgent<String>(
      store: store,
      tools: [SequentialTool([], approval: true)],
      model: f.FakeModel([
        [NativeToolCallReady(call(1)), const ModelFinished()],
      ]),
    );
    final first = await original.generate(
      f.request(),
      ownerId: 'owner',
      context: 'x',
    );
    var effects = 0;
    final changed = AiAgent<String>(
      store: store,
      tools: [NativeTool((_) => effects++)],
      model: f.FakeModel([]),
    );
    final events = await f.run(
      changed,
      f.request(
        run: 'changed',
        parent: first.runId,
        text: null,
        resume: [first.interrupts.single.approve()],
      ),
    );
    expect(events.last.json['code'], 'INVALID_INPUT');
    expect(effects, 0);
  });
}
