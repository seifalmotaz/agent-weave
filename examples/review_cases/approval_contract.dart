// Offline consumer review: dart run examples/review_cases/approval_contract.dart
import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

const low = 9007199254740992;
const high = 9007199254740993;
const value = 9007199254740995;
JsonObject input(int min, {bool reverse = false}) => reverse
    ? {
        'required': ['value'],
        'properties': {
          'value': {'minimum': min, 'type': 'integer'},
        },
        'type': 'object',
      }
    : {
        'type': 'object',
        'properties': {
          'value': {'type': 'integer', 'minimum': min},
        },
        'required': ['value'],
      };
JsonObject output(int min) => {'type': 'integer', 'minimum': min};

class Native implements AgentTool<void> {
  @override
  final NativeModelTool definition;
  final void Function() effect;
  Native(this.effect, int number)
    : definition = NativeModelTool(
        name: 'native',
        description: 'Native',
        inputSchema: input(low),
        provider: 'example',
        bindingId: 'binding',
        definition: {'limit': number},
      );
  @override
  JsonObject? get outputSchema => null;
  @override
  bool get needsApproval => true;
  @override
  bool get clientExecuted => false;
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<void> context) async {
    effect();
    return 'ok';
  }
}

class FailingModel implements ChatModel {
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    throw StateError('PRIVATE-PROVIDER-SECRET');
  }
}

Future<void> main() async {
  final failures = <String>[];
  void check(bool condition, String label) {
    if (!condition) failures.add(label);
  }

  var serial = 0;
  Future<void> scenario(String label, {required String change}) async {
    final store = MemoryRunStore();
    var effects = 0;
    final isNative = change == 'native';
    final isClient = change == 'client';
    final isBatch = change == 'batch';
    AgentTool<void> function(
      String name,
      int inputMin,
      int outputMin, {
      bool reverse = false,
    }) => Tool<int, int, void>(
      name: name,
      description: 'Effect',
      inputSchema: input(inputMin, reverse: reverse),
      outputSchema: output(outputMin),
      needsApproval: true,
      decode: (j) => j['value'] as int,
      encode: (x) => x,
      execute: (x, _) {
        effects++;
        return x;
      },
    );
    AgentTool<void> client() => ClientTool<void>(
      definition: ModelTool(
        name: 'first',
        description: 'Effect',
        inputSchema: input(low),
      ),
      outputSchema: const {'type': 'boolean'},
    );
    AgentTool<void> serverClient() => Tool<int, bool, void>(
      name: 'first',
      description: 'Effect',
      inputSchema: input(low),
      outputSchema: const {'type': 'boolean'},
      needsApproval: false,
      decode: (j) => j['value'] as int,
      encode: (x) => x,
      execute: (x, _) {
        effects++;
        return true;
      },
    );
    List<AgentTool<void>> tools({
      bool changed = false,
      bool reordered = false,
    }) => isNative
        ? [Native(() => effects++, changed ? high : low)]
        : [
            if (isClient && !changed)
              client()
            else if (isClient)
              serverClient()
            else
              function(
                'first',
                changed && change == 'input' ? high : low,
                changed && change == 'output' ? high : low,
                reverse: reordered,
              ),
            if (isBatch) function('second', changed ? high : low, low),
          ];
    ToolCall call(String name) =>
        ToolCall(id: name, name: name, arguments: {'value': value});
    final model = ScriptedChatModel(
      capabilities: const ModelCapabilities(tools: true),
      steps: [
        [
          if (isNative)
            NativeToolCallReady(
              NativeToolCall(
                id: 'native',
                name: 'native',
                arguments: {'value': value},
                provider: 'example',
                requiresApproval: true,
              ),
            )
          else ...[
            ToolCallReady(call('first')),
            if (isBatch) ToolCallReady(call('second')),
          ],
          const ModelFinished(),
        ],
        [const TextDelta('done'), const ModelFinished()],
      ],
    );
    AiAgent<void> agent(List<AgentTool<void>> bindings) =>
        AiAgent(model: model, store: store, tools: bindings);
    final paused = await agent(tools()).generate(
      ChatRequest(
        threadId: label,
        runId: '${serial++}',
        messages: [ChatMessage.user('start', id: 'u')],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(
      paused.status == RunStatus.interrupted && effects == 0,
      '$label initial pause',
    );
    final pausedState = (await store.load(ownerId: 'owner', threadId: label))!;
    final publicJson = jsonEncode({
      'hydration': chatHydration(pausedState),
      'events': await store.events(
        ownerId: 'owner',
        threadId: label,
        runId: paused.runId,
      ),
    });
    check(
      !publicJson.contains('toolContract'),
      '$label private contract exposed',
    );
    var lastRun = '';
    var lastEvents = '';
    final answers = [
      for (final interrupt in paused.interrupts)
        if (isClient)
          ResumeAnswer(interruptId: interrupt.id, value: true)
        else
          interrupt.approve(),
    ];
    Future<bool> resume(
      List<AgentTool<void>> bindings, {
      String owner = 'owner',
    }) async {
      lastRun = '${serial++}';
      try {
        final events = await agent(bindings)
            .run(
              ChatRequest(
                threadId: label,
                runId: lastRun,
                parentRunId: paused.runId,
                resume: answers,
              ),
              ownerId: owner,
              context: null,
            )
            .toList();
        lastEvents = jsonEncode(events.map((event) => event.json).toList());
        return events.last.type == 'RUN_FINISHED';
      } catch (_) {
        return false;
      }
    }

    if (change == 'legacy') {
      final state = (await store.load(ownerId: 'owner', threadId: label))!;
      final before = jsonEncode(state['messages']);
      for (final item in state['pending'] as List) {
        (item as Map).remove('toolContract');
      }
      await store.begin(
        ownerId: 'owner',
        threadId: label,
        runId: 'mutation-${serial++}',
        parentRunId: paused.runId,
      );
      await store.save(
        ownerId: 'owner',
        threadId: label,
        runId: 'mutation-${serial - 1}',
        state: state,
        release: true,
      );
      final accepted = await resume(tools());
      final after = await store.load(ownerId: 'owner', threadId: label);
      final legacyEvents = lastEvents;
      check(
        legacyEvents.contains('Start a new conversation.') &&
            !legacyEvents.contains('toolContract'),
        '$label public recovery diagnostic',
      );
      check(
        !accepted && effects == 0 && jsonEncode(after?['messages']) == before,
        '$label legacy rejected and history retained',
      );
    } else if (change == 'reorder') {
      check(
        await resume(tools(reordered: true)) && effects == 1,
        '$label equivalent key order',
      );
    } else {
      check(
        !await resume(tools(changed: true)) && effects == 0,
        '$label changed contract must reject before effects',
      );
      final changedEvents = lastEvents;
      check(
        changedEvents.contains('Start a new conversation.') &&
            !changedEvents.contains('toolContract'),
        '$label public change diagnostic',
      );
      if (effects == 0) {
        check(
          !await resume(tools(), owner: 'other') && effects == 0,
          '$label owner isolation',
        );
        check(
          await resume(tools()) &&
              effects ==
                  (isBatch
                      ? 2
                      : isClient
                      ? 0
                      : 1),
          '$label retry original contract',
        );
      }
    }
  }

  check(
    schemaHash(input(low)) == schemaHash(input(high)),
    'repro requires public hash collision',
  );
  for (final name in [
    'input',
    'output',
    'native',
    'client',
    'batch',
    'reorder',
    'legacy',
  ]) {
    try {
      await scenario(name, change: name);
    } catch (e) {
      failures.add('$name unexpected: $e');
    }
  }
  try {
    final model = ScriptedChatModel(
      capabilities: const ModelCapabilities(tools: true),
      steps: [
        [
          ToolCallReady(
            ToolCall(id: 'f', name: 'effect', arguments: {'value': value}),
          ),
          const ModelFinished(),
        ],
      ],
    );
    final store = MemoryRunStore();
    var effects = 0;
    AiAgent<void> futureAgent(int min) => AiAgent(
      model: model,
      store: store,
      tools: [
        Tool<int, int, void>(
          name: 'effect',
          description: 'Effect',
          inputSchema: input(min),
          outputSchema: output(low),
          needsApproval: true,
          decode: (j) => j['value'] as int,
          encode: (x) => x,
          execute: (x, _) {
            effects++;
            return x;
          },
        ),
      ],
    );
    final paused = await futureAgent(low).generate(
      ChatRequest(
        threadId: 'future',
        runId: 'future-one',
        messages: [ChatMessage.user('start', id: 'u')],
      ),
      ownerId: 'owner',
      context: null,
    );
    AgentRunException? changed;
    try {
      await futureAgent(high).generate(
        ChatRequest(
          threadId: 'future',
          runId: 'future-two',
          parentRunId: paused.runId,
          resume: [paused.interrupts.single.approve()],
        ),
        ownerId: 'owner',
        context: null,
      );
    } on AgentRunException catch (error) {
      changed = error;
    }
    check(
      changed != null &&
          changed.message ==
              'Execution configuration changed. Start a new conversation.' &&
          changed.toString().contains(changed.message) &&
          effects == 0,
      'Future-only recovery message',
    );
    AgentRunException? providerError;
    try {
      await AiAgent<void>(model: FailingModel()).generate(
        ChatRequest(
          threadId: 'provider',
          runId: 'provider-one',
          messages: [ChatMessage.user('start', id: 'u')],
        ),
        ownerId: 'owner',
        context: null,
      );
    } on AgentRunException catch (error) {
      providerError = error;
    }
    check(
      providerError != null &&
          !providerError.message.contains('PRIVATE-PROVIDER-SECRET') &&
          !providerError.toString().contains('PRIVATE-PROVIDER-SECRET') &&
          providerError.cause.toString().contains('PRIVATE-PROVIDER-SECRET'),
      'Future-only provider error redaction',
    );
  } catch (error) {
    failures.add('Future-only unexpected: $error');
  }
  if (failures.isNotEmpty) {
    for (final f in failures) {
      print('FAIL $f');
    }
    throw StateError('${failures.length} failures');
  }
  print(
    'PASS approval contract, collision guards, retry, batches, owner isolation and legacy',
  );
}
