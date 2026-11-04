import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

const schema = {
  'type': 'object',
  'properties': {
    'text': {'type': 'string'},
  },
  'required': ['text'],
  'additionalProperties': false,
};
Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    check(request.uri.path == '/v1/chat/completions', 'HTTP path');
    check(body['model'] == 'local', 'model');
    request.response.headers.contentType = ContentType('text', 'event-stream');
    request.response.write(
      'data: ${jsonEncode({
        'id': 'fixture',
        'object': 'chat.completion.chunk',
        'created': 0,
        'model': 'local',
        'choices': [
          {
            'index': 0,
            'delta': {'content': 'Hello from fixture'},
            'finish_reason': null,
          },
        ],
      })}\n\n',
    );
    request.response.write(
      'data: ${jsonEncode({
        'id': 'fixture',
        'object': 'chat.completion.chunk',
        'created': 0,
        'model': 'local',
        'choices': [
          {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': 'stop'},
        ],
      })}\n\n',
    );
    request.response.write('data: [DONE]\n\n');
    await request.response.close();
  });
  final client = openai.OpenAIClient(
    config: openai.OpenAIConfig(
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      authProvider: openai.ApiKeyProvider('fixture'),
    ),
  );
  try {
    final result = await generateText(
      model: openai.OpenAIChatModel(client: client, model: 'local'),
      prompt: 'Hello',
    );
    check(result.text == 'Hello from fixture', 'HTTP result');
    print('PASS real loopback HTTP');
  } finally {
    client.close();
    await server.close(force: true);
  }
  final token = CancellationToken()..cancel();
  try {
    await generateText(
      model: ScriptedChatModel(steps: []),
      prompt: 'hi',
      cancellation: token,
    );
    throw StateError('cancel unexpectedly succeeded');
  } on RunCancelled {
    print('PASS pre-cancelled generation');
  }
  final started = Completer<void>();
  final activeToken = CancellationToken();
  final active = generateText(
    model: WaitingModel(started),
    prompt: 'hello',
    cancellation: activeToken,
  );
  await started.future;
  activeToken.cancel();
  try {
    await active;
    throw StateError('active cancellation unexpectedly succeeded');
  } on RunCancelled {
    print('PASS in-flight cooperative cancellation');
  }
  for (final reject in [true, false]) {
    var sideEffects = 0;
    final store = MemoryRunStore();
    Tool<String, String, void> tool() => Tool(
      name: 'send',
      description: 'send',
      inputSchema: schema,
      outputSchema: const {'type': 'string'},
      needsApproval: true,
      decode: (json) => json['text'] as String,
      encode: (x) => x,
      execute: (x, c) {
        sideEffects++;
        return x;
      },
    );
    final first = AiAgent<void>(
      store: store,
      tools: [tool()],
      model: ScriptedChatModel(
        capabilities: const ModelCapabilities(tools: true),
        steps: [
          [
            ToolCallReady(
              ToolCall(
                id: 'call',
                name: 'send',
                arguments: {'text': 'original'},
              ),
            ),
            const ModelFinished(),
          ],
        ],
      ),
    );
    final paused = await first.generate(
      ChatRequest(
        threadId: 't',
        runId: 'one',
        messages: [ChatMessage.user('send', id: 'm')],
      ),
      ownerId: 'owner',
      context: null,
    );
    final nextModel = ScriptedChatModel(
      capabilities: const ModelCapabilities(tools: true),
      steps: [
        [const TextDelta('done'), const ModelFinished()],
      ],
    );
    final second = AiAgent<void>(
      store: store,
      tools: [tool()],
      model: nextModel,
    );
    final i = paused.interrupts.single;
    final result = await second.generate(
      ChatRequest(
        threadId: 't',
        runId: 'two',
        parentRunId: 'one',
        resume: [
          reject ? i.reject() : i.approve(editedArgs: {'text': 'edited'}),
        ],
      ),
      ownerId: 'owner',
      context: null,
    );
    check(result.text == 'done', 'resume');
    check(sideEffects == (reject ? 0 : 1), 'approval side effects');
    if (!reject) {
      check(
        nextModel.requests.single.messages.last.text.contains('edited'),
        'edited output',
      );
    }
    print('PASS ${reject ? 'reject' : 'edited approval'}');
  }
}

final class WaitingModel implements ChatModel {
  WaitingModel(this.started);
  final Completer<void> started;
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    started.complete();
    await cancellation.whenCancelled;
    cancellation.throwIfCancelled();
  }
}
