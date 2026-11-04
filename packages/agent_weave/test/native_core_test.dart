import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';
import 'runtime_test.dart' as fixture;

class NativeTool implements AgentTool<String> {
  @override
  final NativeModelTool definition;
  final void Function(ToolContext<String>) execute;
  NativeTool(this.execute, {String target = 'one'})
    : definition = NativeModelTool(
        name: 'computer',
        description: '',
        inputSchema: fixture.inputSchema,
        provider: 'example',
        definition: {'type': 'computer'},
        bindingId: target,
      );
  @override
  JsonObject? get outputSchema => null;
  @override
  bool get needsApproval => false;
  @override
  bool get clientExecuted => false;
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<String> context) async {
    execute(context);
    return 'ok';
  }
}

NativeToolCall nativeCall({
  String provider = 'example',
  bool approval = true,
}) => NativeToolCall(
  id: 'native',
  name: 'computer',
  arguments: {'count': 1},
  provider: provider,
  requiresApproval: approval,
);

void main() {
  test(
    'native definitions cannot bypass approval through a client executor',
    () {
      expect(
        () => AiAgent<String>(
          model: fixture.FakeModel([]),
          tools: [
            ClientTool<String>(definition: NativeTool((_) {}).definition),
          ],
        ),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'variants preserve legacy and native round trips and snapshot definitions',
    () {
      final legacy = ToolCall(id: 'id', name: 'name', arguments: {});
      expect(ToolCall.fromJson(legacy.toJson()), isA<FunctionToolCall>());
      final native = nativeCall();
      final restored = ToolCall.fromJson(native.toJson()) as NativeToolCall;
      expect(restored.provider, 'example');
      expect(restored.requiresApproval, true);
      final wire = <String, Object?>{
        'nested': <String, Object?>{'x': 1},
      };
      final tool = NativeModelTool(
        name: 'n',
        description: '',
        inputSchema: {},
        provider: 'p',
        definition: wire,
      );
      final request = ModelRequest(messages: [], tools: [tool]);
      (wire['nested'] as Map)['x'] = 2;
      expect((request.tools.single as NativeModelTool).definition['nested'], {
        'x': 1,
      });
    },
  );

  test(
    'native forced approval, no edits, changed definition and approved context',
    () async {
      final contexts = <bool>[];
      final model = fixture.FakeModel([
        [NativeToolCallReady(nativeCall()), const ModelFinished()],
        [const ModelFinished()],
      ]);
      final store = MemoryRunStore();
      final agent = AiAgent<String>(
        model: model,
        store: store,
        tools: [NativeTool((c) => contexts.add(c.approved))],
      );
      final first = await agent.generate(
        fixture.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final interrupt = first.interrupts.single;
      final state = (await store.load(ownerId: 'owner', threadId: 'thread'))!;
      final terminal = (state['events'] as List).last as Map;
      final wireInterrupt =
          ((terminal['outcome'] as Map)['interrupts'] as List).single as Map;
      final schema = Map<String, Object?>.from(
        wireInterrupt['responseSchema'] as Map,
      );
      final binding =
          ((wireInterrupt['metadata'] as Map)['tanstack:interruptBinding']
              as Map);
      expect((schema['properties'] as Map).keys, ['approved']);
      expect(schemaHash(schema), binding['responseSchemaHash']);
      expect(contexts, isEmpty);
      expect(
        () => interrupt.approve(editedArgs: {'count': 2}),
        throwsStateError,
      );
      final bad = await fixture.run(
        agent,
        fixture.request(
          run: 'bad',
          parent: 'run',
          text: null,
          resume: [
            ResumeAnswer(
              interruptId: interrupt.id,
              value: {
                'approved': true,
                'editedArgs': {'count': 2},
              },
            ),
          ],
        ),
      );
      expect(bad.last.type, 'RUN_ERROR');
      expect(contexts, isEmpty);
      final changed = AiAgent<String>(
        model: model,
        store: store,
        tools: [NativeTool((c) => contexts.add(c.approved), target: 'two')],
      );
      final mismatch = await fixture.run(
        changed,
        fixture.request(
          run: 'changed',
          parent: 'run',
          text: null,
          resume: [interrupt.approve()],
        ),
      );
      expect(mismatch.last.type, 'RUN_ERROR');
      final result = await fixture.run(
        agent,
        fixture.request(
          run: 'ok',
          parent: 'run',
          text: null,
          resume: [interrupt.approve()],
        ),
      );
      expect(result.last.type, 'RUN_FINISHED');
      expect(contexts, [true]);
    },
  );

  test('mismatched provider is rejected before execution', () async {
    var executed = false;
    final agent = AiAgent<String>(
      model: fixture.FakeModel([
        [
          NativeToolCallReady(nativeCall(provider: 'other')),
          const ModelFinished(),
        ],
      ]),
      tools: [NativeTool((_) => executed = true)],
    );
    final result = await fixture.run(agent);
    expect(result.last.type, 'RUN_ERROR');
    expect(executed, false);
  });

  test(
    'decline closes thread without a fabricated output or execution',
    () async {
      var executed = false;
      final model = fixture.FakeModel([
        [NativeToolCallReady(nativeCall()), const ModelFinished()],
      ]);
      final agent = AiAgent<String>(
        model: model,
        tools: [NativeTool((_) => executed = true)],
      );
      final first = await agent.generate(
        fixture.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final events = await fixture.run(
        agent,
        fixture.request(
          run: 'decline',
          parent: 'run',
          text: null,
          resume: [first.interrupts.single.reject()],
        ),
      );
      expect(events.last.type, 'RUN_FINISHED');
      final state = (await agent.store.load(
        ownerId: 'owner',
        threadId: 'thread',
      ))!;
      expect(state['nativeContinuationClosed'], isNotNull);
      expect(
        (state['messages'] as List).where((m) => (m as Map)['role'] == 'tool'),
        isEmpty,
      );
      final followup = await fixture.run(agent, fixture.request(run: 'again'));
      expect(followup.last.type, 'RUN_ERROR');
      expect(executed, false);
      expect(model.requests, hasLength(1));
    },
  );
  test(
    'batch rejects edited native arguments before executing other approvals',
    () async {
      var executions = 0;
      final model = fixture.FakeModel([
        [
          fixture.call(),
          NativeToolCallReady(nativeCall()),
          const ModelFinished(),
        ],
      ]);
      final agent = AiAgent<String>(
        model: model,
        tools: [
          fixture.tool(
            approval: true,
            execute: (n, c) {
              executions++;
              return n;
            },
          ),
          NativeTool((_) => executions++),
        ],
      );
      final first = await agent.generate(
        fixture.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final answers = [
        for (final interrupt in first.interrupts)
          interrupt.call is NativeToolCall
              ? ResumeAnswer(
                  interruptId: interrupt.id,
                  value: {
                    'approved': true,
                    'editedArgs': {'count': 2},
                  },
                )
              : interrupt.approve(),
      ];
      final events = await fixture.run(
        agent,
        fixture.request(run: 'bad', parent: 'run', text: null, resume: answers),
      );
      expect(events.last.type, 'RUN_ERROR');
      expect(executions, 0);
    },
  );

  test(
    'ordinary invocation receives unapproved context and native kind cannot call function',
    () async {
      bool? approved;
      final agent = AiAgent<String>(
        model: fixture.FakeModel([
          [fixture.call(), const ModelFinished()],
          [const ModelFinished()],
        ]),
        tools: [
          fixture.tool(
            execute: (n, c) {
              approved = c.approved;
              return n;
            },
          ),
        ],
      );
      await fixture.run(agent);
      expect(approved, false);
      final wrong = AiAgent<String>(
        model: fixture.FakeModel([
          [
            ToolCallReady(
              ToolCall(id: 'x', name: 'computer', arguments: {'count': 1}),
            ),
            const ModelFinished(),
          ],
        ]),
        tools: [NativeTool((_) => fail('must not execute'))],
      );
      expect((await fixture.run(wrong)).last.type, 'RUN_ERROR');
    },
  );
}
