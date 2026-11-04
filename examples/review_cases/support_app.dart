import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

void check(bool ok, String label) {
  if (!ok) throw StateError(label);
}

const schema = {
  'type': 'object',
  'properties': {
    'ticket': {'type': 'integer'},
  },
  'required': ['ticket'],
  'additionalProperties': false,
};
const caps = ModelCapabilities(tools: true, structuredOutput: true);
Future<void> main() async {
  final chatModel = ScriptedChatModel(
    steps: [
      [
        const TextDelta('We can help.'),
        const TokenUsage(inputTokens: 4, outputTokens: 3),
        const ModelFinished(),
      ],
    ],
  );
  final chat = await generateText(model: chatModel, prompt: 'My order is late');
  check(chat.text == 'We can help.' && chat.usage?.outputTokens == 3, 'chat');
  check(
    chatModel.requests.single.messages.single.text == 'My order is late',
    'request',
  );
  print('PASS support chat and usage');

  final store = MemoryRunStore();
  final sent = <int>[];
  Tool<int, String, String> tool() => Tool(
    name: 'escalate',
    description: 'Escalate a ticket',
    needsApproval: true,
    inputSchema: schema,
    outputSchema: const {'type': 'string'},
    decode: (j) => j['ticket'] as int,
    encode: (v) => v,
    execute: (ticket, ctx) {
      check(
        ctx.value == 'support' &&
            ctx.ownerId == 'owner' &&
            ctx.idempotencyKey.isNotEmpty,
        'context',
      );
      sent.add(ticket);
      return 'escalated';
    },
  );
  final first = AiAgent<String>(
    store: store,
    tools: [tool()],
    model: ScriptedChatModel(
      capabilities: caps,
      steps: [
        [
          ToolCallReady(
            ToolCall(id: 'call', name: 'escalate', arguments: {'ticket': 42}),
          ),
          const ModelFinished(),
        ],
      ],
    ),
  );
  final paused = await first.generate(
    ChatRequest(
      threadId: 'support',
      runId: 'r1',
      messages: [ChatMessage.user('Escalate ticket 42', id: 'm1')],
    ),
    ownerId: 'owner',
    context: 'support',
  );
  check(paused.status == RunStatus.interrupted && sent.isEmpty, 'pause');
  final nextModel = ScriptedChatModel(
    capabilities: caps,
    steps: [
      [const TextDelta('Escalated.'), const ModelFinished()],
    ],
  );
  final resumed =
      await AiAgent<String>(
        store: store,
        tools: [tool()],
        model: nextModel,
      ).generate(
        ChatRequest(
          threadId: 'support',
          runId: 'r2',
          parentRunId: paused.runId,
          resume: [paused.interrupts.single.approve()],
        ),
        ownerId: 'owner',
        context: 'support',
      );
  check(sent.single == 42 && resumed.text == 'Escalated.', 'resume');
  check(
    nextModel.requests.single.messages.any((m) => m.role == MessageRole.tool),
    'tool history',
  );
  print('PASS typed tool and recreated approval');

  final object = await generateObject<int>(
    model: ScriptedChatModel(
      capabilities: caps,
      steps: [
        [const TextDelta('{"ticket":42}'), const ModelFinished()],
      ],
    ),
    prompt: 'Extract ticket',
    schema: schema,
    decode: (j) => (j as Map<String, Object?>)['ticket'] as int,
  );
  check(object.value == 42, 'object');
  try {
    await generateObject<int>(
      model: ScriptedChatModel(
        capabilities: caps,
        steps: [
          [const TextDelta('{"ticket":"bad"}'), const ModelFinished()],
        ],
      ),
      prompt: 'Extract ticket',
      schema: schema,
      decode: (j) => (j as Map<String, Object?>)['ticket'] as int,
    );
    throw StateError('invalid accepted');
  } on AgentRunException catch (e) {
    check(e.code == 'INVALID_OUTPUT', 'invalid output code ${e.code}');
    print(
      'PASS invalid output: ${e.code}, message=${e.message}, cause=${e.cause}',
    );
  }
  try {
    await generateText(
      model: ScriptedChatModel(steps: []),
      prompt: 'cancel',
      cancellation: CancellationToken()..cancel(),
    );
    throw StateError('cancel accepted');
  } on RunCancelled {
    print('PASS cancellation');
  }
  final ref = OutputReference(
    provider: 'openai',
    source: FileCitationSource(
      provider: 'openai',
      fileId: 'file-42',
      filename: 'guide.pdf',
    ),
    partStart: 0,
    partEnd: 5,
    position: FileListPosition(0),
  );
  final result = await generateText(
    model: ScriptedChatModel(
      steps: [
        [const TextDelta('Guide'), ReferenceReady(ref), const ModelFinished()],
      ],
    ),
    prompt: 'Find guide',
  );
  final message = result.responseMessages.single;
  final file = message.references.single.source as FileCitationSource;
  check(
    file.fileId == 'file-42' &&
        file.filename == 'guide.pdf' &&
        message.text.substring(
              message.references.single.partStart,
              message.references.single.partEnd,
            ) ==
            'Guide',
    'reference',
  );
  print('PASS file reference and text context');
}
