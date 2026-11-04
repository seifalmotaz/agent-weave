import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

const marker = 'PRIVATE_MARKER_732';
const caps = ModelCapabilities(tools: true, structuredOutput: true);
const nested = {
  'type': 'object',
  'properties': {
    'customer': {
      'type': 'object',
      'properties': {
        'priority': {'type': 'integer'},
      },
      'required': ['priority'],
      'additionalProperties': false,
    },
  },
  'required': ['customer'],
  'additionalProperties': false,
};
void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

void inspect(AgentRunException e, String path) {
  check(
    !e.message.contains(marker),
    'public error leaked marker: ${e.message}',
  );
  final cause = e.cause;
  check(
    cause is SchemaValidationException,
    'expected SchemaValidationException, got $cause',
  );
  final issues = (cause as SchemaValidationException).issues;
  try {
    issues.clear();
    throw StateError('issues list is mutable');
  } on UnsupportedError {
    /* expected */
  }
  check(
    issues.any(
      (i) =>
          i.instancePath.contains(path) &&
          i.message.toLowerCase().contains('integer'),
    ),
    'missing useful $path integer issue: ${issues.map((i) => '${i.instancePath} ${i.schemaPath} ${i.message}').toList()}',
  );
  check(
    !cause.toString().contains(marker) && cause.source == null,
    'exception leaked',
  );
  print(
    'PASS ${e.code}: ${issues.map((i) => '${i.instancePath} ${i.schemaPath} ${i.message}').toList()}',
  );
}

Tool<Map<String, Object?>, Object?, void> tool({
  bool approval = false,
  bool invalidOutput = false,
}) => Tool(
  name: 'escalate',
  description: 'Escalate',
  needsApproval: approval,
  inputSchema: nested,
  outputSchema: invalidOutput ? nested : const {'type': 'string'},
  decode: (j) => j,
  encode: (v) => v,
  execute: (j, c) => invalidOutput
      ? {
          'customer': {'priority': marker},
        }
      : 'ok',
);
ScriptedChatModel callModel(Object? priority) => ScriptedChatModel(
  capabilities: caps,
  steps: [
    [
      ToolCallReady(
        ToolCall(
          id: 'call',
          name: 'escalate',
          arguments: {
            'customer': {'priority': priority},
          },
        ),
      ),
      const ModelFinished(),
    ],
  ],
);
Future<void> main() async {
  Object? editedFailure;
  try {
    await generateObject<Object?>(
      model: ScriptedChatModel(
        capabilities: caps,
        steps: [
          [
            const TextDelta('{"customer":{"priority":"$marker"}}'),
            const ModelFinished(),
          ],
        ],
      ),
      prompt: 'classify',
      schema: nested,
      decode: (j) => j,
    );
    throw StateError('structured accepted invalid');
  } on AgentRunException catch (e) {
    inspect(e, 'priority');
  }
  for (final output in [false, true]) {
    try {
      await AiAgent<void>(
        model: callModel(output ? 1 : marker),
        tools: [tool(invalidOutput: output)],
      ).generate(
        ChatRequest(
          threadId: 't',
          runId: 'r',
          messages: [ChatMessage.user('escalate', id: 'm')],
        ),
        ownerId: 'o',
        context: null,
      );
      throw StateError('tool accepted invalid');
    } on AgentRunException catch (e) {
      inspect(e, 'priority');
    }
  }
  final store = MemoryRunStore();
  final paused =
      await AiAgent<void>(
        store: store,
        model: callModel(1),
        tools: [tool(approval: true)],
      ).generate(
        ChatRequest(
          threadId: 't',
          runId: 'r1',
          messages: [ChatMessage.user('escalate', id: 'm')],
        ),
        ownerId: 'o',
        context: null,
      );
  try {
    await AiAgent<void>(
      store: store,
      model: ScriptedChatModel(capabilities: caps, steps: []),
      tools: [tool(approval: true)],
    ).generate(
      ChatRequest(
        threadId: 't',
        runId: 'r2',
        parentRunId: paused.runId,
        resume: [
          paused.interrupts.single.approve(
            editedArgs: {
              'customer': {'priority': marker},
            },
          ),
        ],
      ),
      ownerId: 'o',
      context: null,
    );
    throw StateError('edited invalid accepted');
  } on AgentRunException catch (e) {
    try {
      inspect(e, 'priority');
    } catch (failure) {
      editedFailure = failure;
      print('FAIL edited approval diagnostic: $failure');
    }
  }
  final hydrated = jsonEncode(
    chatHydration(await store.load(ownerId: 'o', threadId: 't')),
  );
  check(
    !hydrated.contains(marker),
    'edited input leaked into hydration: $hydrated',
  );
  print('PASS edited input absent from hydration');
  const secretSchema = {
    'type': 'object',
    'properties': {
      'status': {
        'type': 'string',
        'enum': ['SCHEMA_PRIVATE_ALLOWED_89'],
      },
    },
    'required': ['status'],
  };
  final secretStore = MemoryRunStore();
  final events =
      await AiAgent<void>(
            store: secretStore,
            model: ScriptedChatModel(
              capabilities: caps,
              steps: [
                [
                  ToolCallReady(
                    ToolCall(
                      id: 'secret-call',
                      name: 'secret',
                      arguments: {'status': 'not-allowed'},
                    ),
                  ),
                  const ModelFinished(),
                ],
              ],
            ),
            tools: [
              Tool<Map<String, Object?>, String, void>(
                name: 'secret',
                description: 'classify',
                inputSchema: secretSchema,
                outputSchema: const {'type': 'string'},
                decode: (j) => j,
                encode: (v) => v,
                execute: (j, c) => 'ok',
              ),
            ],
          )
          .run(
            ChatRequest(
              threadId: 'private',
              runId: 'run',
              messages: [ChatMessage.user('classify', id: 'user')],
            ),
            ownerId: 'o',
            context: null,
          )
          .toList();
  try {
    await AiAgent<void>(
      model: ScriptedChatModel(
        capabilities: caps,
        steps: [
          [
            ToolCallReady(
              ToolCall(
                id: 'c',
                name: 'secret',
                arguments: {'status': 'not-allowed'},
              ),
            ),
            const ModelFinished(),
          ],
        ],
      ),
      tools: [
        Tool<Map<String, Object?>, String, void>(
          name: 'secret',
          description: 'classify',
          inputSchema: secretSchema,
          outputSchema: const {'type': 'string'},
          decode: (j) => j,
          encode: (v) => v,
          execute: (j, c) => 'ok',
        ),
      ],
    ).generate(
      ChatRequest(
        threadId: 'private2',
        runId: 'r',
        messages: [ChatMessage.user('classify', id: 'm')],
      ),
      ownerId: 'o',
      context: null,
    );
    throw StateError('enum invalid accepted');
  } on AgentRunException catch (e) {
    check(
      !e.message.contains('SCHEMA_PRIVATE_ALLOWED_89') &&
          !e.cause.toString().contains('SCHEMA_PRIVATE_ALLOWED_89'),
      'private schema in default errors',
    );
    check(e.cause is SchemaValidationException, 'missing schema diagnostic');
  }
  final public =
      jsonEncode(events.map((e) => e.json).toList()) +
      jsonEncode(
        chatHydration(
          await secretStore.load(ownerId: 'o', threadId: 'private'),
        ),
      );
  check(
    !public.contains('SCHEMA_PRIVATE_ALLOWED_89'),
    'private schema leaked into public events or hydration',
  );
  print('PASS private schema absent from events and hydration');
  if (editedFailure != null) {
    throw StateError('Edited approval diagnostics failed: $editedFailure');
  }
}
