import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';
import 'runtime_test.dart' as f;

const secret = 'PRIVATE_ENUM_MARKER';
const schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'a/b~c': {
      'type': 'array',
      'items': {'type': 'integer'},
    },
    'choice': {
      'enum': [secret],
    },
  },
  'required': ['missing'],
  'additionalProperties': false,
};
void main() {
  test('validator paths, distinct keywords and redaction are preserved', () {
    try {
      validateSchema(schema, {
        'a/b~c': ['PRIVATE_INPUT'],
        'choice': 'PRIVATE_INPUT',
        'extra': true,
      });
      fail('Expected validation error');
    } on SchemaValidationException catch (error) {
      expect(error, isA<FormatException>());
      expect(error.message, 'Value does not match the declared JSON Schema.');
      expect(error.source, isNull);
      expect(error.offset, isNull);
      expect(error.toString(), isNot(contains('PRIVATE')));
      expect(
        error.issues.any(
          (e) =>
              e.instancePath == '/a/b~c/0' &&
              e.schemaPath == '/properties/a/b~c/items',
        ),
        true,
      );
      expect(error.issues.any((e) => e.schemaPath == '/required'), true);
      expect(
        error.issues.any((e) => e.schemaPath == '/additionalProperties'),
        true,
      );
      expect(
        error.issues.any(
          (e) => e.instancePath == '/choice' && e.message.contains('enum'),
        ),
        true,
      );
      expect(
        error.issues.any((e) => e.message.contains('PRIVATE_INPUT')),
        true,
      );
      expect(() => error.issues.clear(), throwsUnsupportedError);
    }
    try {
      validateSchema({'type': 'integer'}, 'x');
      fail('Expected validation error');
    } on SchemaValidationException catch (error) {
      expect(error.issues.single.instancePath, '');
      expect(error.issues.single.schemaPath, '');
    }
    final original = [
      const SchemaValidationIssue(
        instancePath: '/a',
        schemaPath: '/b',
        message: 'secret',
      ),
    ];
    final copy = SchemaValidationException(original);
    original.clear();
    expect(copy.issues, hasLength(1));
    expect(copy.toString(), isNot(contains('secret')));
  });

  test('tool input and output validation preserve typed diagnostics', () async {
    final tool = Tool<Object?, Object?, void>(
      name: 'tool',
      description: '',
      inputSchema: const {
        'type': 'object',
        'required': ['ok'],
      },
      outputSchema: const {'type': 'integer'},
      decode: (x) => x,
      encode: (x) => x,
      execute: (_, _) => 'bad',
    );
    final context = ToolContext<void>(
      value: null,
      ownerId: 'o',
      threadId: 't',
      runId: 'r',
      toolCallId: 'c',
      cancellation: CancellationToken(),
    );
    await expectLater(
      tool.invoke({}, context),
      throwsA(isA<SchemaValidationException>()),
    );
    await expectLater(
      tool.invoke({'ok': true}, context),
      throwsA(isA<SchemaValidationException>()),
    );
  });

  test(
    'structured output cause is private while stream and Future stay safe',
    () async {
      Object? observed;
      AiAgent<String> agent(MemoryRunStore store) => AiAgent<String>(
        model: f.FakeModel([
          [
            const TextDelta('{"choice":"PRIVATE_INPUT"}'),
            const ModelFinished(),
          ],
        ]),
        store: store,
        outputSchema: const {
          'type': 'object',
          'properties': {
            'choice': {
              'enum': [secret],
            },
          },
        },
        onError: (error, _) => observed = error,
      );
      final store = MemoryRunStore();
      final events = await f.run(agent(store));
      expect(events.last.type, 'RUN_ERROR');
      final streamed = events.last.json['message'];
      expect(streamed, 'Invalid input or provider output.');
      expect(observed, isA<SchemaValidationException>());
      expect((observed as SchemaValidationException).issues, isNotEmpty);
      expect(
        jsonEncode(events.map((e) => e.json).toList()),
        isNot(contains(secret)),
      );
      expect(
        jsonEncode(
          chatHydration(await store.load(ownerId: 'owner', threadId: 'thread')),
        ),
        isNot(contains(secret)),
      );
      try {
        await agent(
          MemoryRunStore(),
        ).generate(f.request(), ownerId: 'owner', context: 'x');
        fail('Expected failure');
      } on AgentRunException catch (error) {
        expect(error.code, 'INVALID_OUTPUT');
        expect(error.message, streamed);
        expect(error.cause, isA<SchemaValidationException>());
        expect(error.toString(), isNot(contains(secret)));
        expect(error.toString(), isNot(contains('PRIVATE_INPUT')));
      }
    },
  );

  test('resume validation errors are typed and do not execute tool', () async {
    var effects = 0;
    Object? observed;
    final model = f.FakeModel([
      [f.call(), const ModelFinished()],
    ]);
    final store = MemoryRunStore();
    final agent = AiAgent<String>(
      model: model,
      store: store,
      tools: [
        f.tool(
          approval: true,
          execute: (v, _) {
            effects++;
            return v;
          },
        ),
      ],
      onError: (error, _) => observed = error,
    );
    final paused = await agent.generate(
      f.request(),
      ownerId: 'owner',
      context: 'x',
    );
    final events = await f.run(
      agent,
      f.request(
        run: 'resume',
        parent: 'run',
        text: null,
        resume: [
          ResumeAnswer(
            interruptId: paused.interrupts.single.id,
            value: {'approved': 'PRIVATE_INPUT'},
          ),
        ],
      ),
    );
    expect(events.last.type, 'RUN_ERROR');
    expect(observed, isA<SchemaValidationException>());
    expect(events.last.json['message'], 'Invalid input or provider output.');
    expect(
      jsonEncode(events.map((e) => e.json).toList()),
      isNot(contains('PRIVATE_INPUT')),
    );
    expect(effects, 0);
  });
  test(
    'edited arguments expose nested validation path before effects',
    () async {
      const input = {
        'type': 'object',
        'properties': {
          'customer': {
            'type': 'object',
            'properties': {
              'priority': {'type': 'integer'},
            },
          },
        },
      };
      var effects = 0;
      Object? observed;
      final tool = Tool<JsonObject, int, String>(
        name: 'edit',
        description: '',
        inputSchema: input,
        outputSchema: const {'type': 'integer'},
        needsApproval: true,
        decode: (x) => x,
        encode: (x) => x,
        execute: (_, _) {
          effects++;
          return 1;
        },
      );
      final model = f.FakeModel([
        [
          ToolCallReady(
            ToolCall(
              id: 'c',
              name: 'edit',
              arguments: {
                'customer': {'priority': 1},
              },
            ),
          ),
          const ModelFinished(),
        ],
        [const ModelFinished()],
      ]);
      final store = MemoryRunStore();
      final agent = AiAgent<String>(
        model: model,
        store: store,
        tools: [tool],
        onError: (error, _) => observed = error,
      );
      final paused = await agent.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final events = await f.run(
        agent,
        f.request(
          run: 'bad',
          parent: 'run',
          text: null,
          resume: [
            ResumeAnswer(
              interruptId: paused.interrupts.single.id,
              value: {
                'approved': true,
                'editedArgs': {
                  'customer': {'priority': 'bad'},
                },
              },
            ),
          ],
        ),
      );
      expect(events.last.type, 'RUN_ERROR');
      expect(effects, 0);
      expect(
        (observed as SchemaValidationException).issues.any(
          (e) => e.instancePath == '/customer/priority',
        ),
        true,
      );
      final retry = await f.run(
        agent,
        f.request(
          run: 'retry',
          parent: 'run',
          text: null,
          resume: [
            ResumeAnswer(
              interruptId: paused.interrupts.single.id,
              value: {
                'approved': true,
                'editedArgs': {
                  'customer': {'priority': 2},
                },
              },
            ),
          ],
        ),
      );
      expect(retry.last.type, 'RUN_FINISHED');
      expect(effects, 1);
    },
  );
  test(
    'entire approval batch validates envelope and edited arguments before effects',
    () async {
      var effects = 0;
      Tool<JsonObject, int, String> tool(String name) => Tool(
        name: name,
        description: '',
        inputSchema: const {},
        outputSchema: const {'type': 'integer'},
        needsApproval: true,
        decode: (v) => v,
        encode: (v) => v,
        execute: (_, _) {
          effects++;
          return 1;
        },
      );
      final model = f.FakeModel([
        [
          ToolCallReady(ToolCall(id: 'one', name: 'a', arguments: {})),
          ToolCallReady(ToolCall(id: 'two', name: 'b', arguments: {})),
          const ModelFinished(),
        ],
        [const ModelFinished()],
      ]);
      final store = MemoryRunStore();
      final agent = AiAgent<String>(
        model: model,
        store: store,
        tools: [tool('a'), tool('b')],
      );
      final paused = await agent.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final first = paused.interrupts[0].id;
      final second = paused.interrupts[1].id;
      final invalid = [
        {'approved': true, 'editedArgs': 'not-an-object'},
        {'approved': false, 'editedArgs': <String, Object?>{}},
        {'approved': true, 'unexpected': true},
      ];
      for (var i = 0; i < invalid.length; i++) {
        final events = await f.run(
          agent,
          f.request(
            run: 'bad-$i',
            parent: 'run',
            text: null,
            resume: [
              ResumeAnswer(interruptId: first, value: true),
              ResumeAnswer(interruptId: second, value: invalid[i]),
            ],
          ),
        );
        expect(events.last.type, 'RUN_ERROR');
        expect(effects, 0);
      }
      final retry = await f.run(
        agent,
        f.request(
          run: 'good',
          parent: 'run',
          text: null,
          resume: [
            ResumeAnswer(interruptId: first, value: true),
            ResumeAnswer(
              interruptId: second,
              value: {
                'approved': true,
                'editedArgs': {'ok': 1},
              },
            ),
          ],
        ),
      );
      expect(retry.last.type, 'RUN_FINISHED');
      expect(effects, 2);
    },
  );

  test(
    'local refs work when edited arguments are validated directly',
    () async {
      final schema = <String, Object?>{
        r'$defs': {
          'priority': {'type': 'integer'},
        },
        'type': 'object',
        'properties': {
          'priority': {r'$ref': r'#/$defs/priority'},
        },
      };
      var effects = 0;
      final tool = Tool<JsonObject, int, String>(
        name: 'local',
        description: '',
        inputSchema: schema,
        outputSchema: const {'type': 'integer'},
        needsApproval: true,
        decode: (v) => v,
        encode: (v) => v,
        execute: (_, _) {
          effects++;
          return 1;
        },
      );
      final model = f.FakeModel([
        [
          ToolCallReady(
            ToolCall(id: 'c', name: 'local', arguments: {'priority': 1}),
          ),
          const ModelFinished(),
        ],
        [const ModelFinished()],
      ]);
      final agent = AiAgent<String>(model: model, tools: [tool]);
      final paused = await agent.generate(
        f.request(),
        ownerId: 'owner',
        context: 'x',
      );
      final events = await f.run(
        agent,
        f.request(
          run: 'resume',
          parent: 'run',
          text: null,
          resume: [
            ResumeAnswer(
              interruptId: paused.interrupts.single.id,
              value: {
                'approved': true,
                'editedArgs': {'priority': 2},
              },
            ),
          ],
        ),
      );
      expect(events.last.type, 'RUN_FINISHED');
      expect(effects, 1);
    },
  );
}
