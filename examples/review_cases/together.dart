// Offline consumer exercise: dart --enable-asserts run examples/review_cases/together.dart
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_together/agent_weave_together.dart' as together;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  server.listen((request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    count++;
    assert(request.headers.value('authorization') == 'Bearer fixture');
    if (count == 1) {
      assert(body['top_k'] == 12 && body['model'] == 'raw');
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"choices":[]}');
    } else {
      assert(body['temperature'] == 0.2);
      if (count == 2) assert(body['response_format']['type'] == 'json_schema');
      if (count == 3) assert(body['tools'][0]['function']['name'] == 'double');
      if (count == 4) {
        final messages = body['messages'] as List;
        assert(
          messages.any((m) => m['role'] == 'tool' && m['content'] == '42'),
        );
        assert(
          messages.any(
            (m) =>
                m['role'] == 'assistant' &&
                m['tool_calls'] != null &&
                m['reasoning_content'] == 'thinking',
          ),
        );
      }
      final delta = count == 2
          ? {'content': '{"answer":42}'}
          : count == 3
          ? {
              'reasoning_content': 'thinking',
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call',
                  'type': 'function',
                  'function': {'name': 'double', 'arguments': '{"answer":21}'},
                },
              ],
            }
          : {'content': '42'};
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      request.response.write(
        'data: ${jsonEncode({
          'model': 'fixture',
          'choices': [
            {'index': 0, 'delta': delta, 'finish_reason': count == 3 ? 'tool_calls' : 'stop'},
          ],
        })}\n\ndata: [DONE]\n\n',
      );
    }
    await request.response.close();
  });
  final client = together.TogetherClient(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}/v1',
  );
  try {
    final raw = await client.createChat({
      'model': 'raw',
      'messages': [],
      'top_k': 12,
    });
    assert(raw['choices'] is List);
    final model = together.TogetherChatModel(
      client: client,
      model: 'fixture',
      options: together.TogetherChatOptions(temperature: 0.2),
    );
    const schema = <String, Object?>{
      'type': 'object',
      'properties': {
        'answer': {'type': 'integer'},
      },
      'required': ['answer'],
    };
    final result = await generateObject<int>(
      model: model,
      schema: schema,
      decode: (json) => (json as Map<String, Object?>)['answer'] as int,
      prompt: 'Answer',
    );
    assert(result.value == 42);
    var executions = 0;
    final agent = AiAgent<String>(
      model: model,
      tools: [
        Tool<int, int, String>(
          name: 'double',
          description: 'Double',
          inputSchema: schema,
          outputSchema: const {'type': 'integer'},
          needsApproval: true,
          decode: (json) => json['answer'] as int,
          encode: (n) => n,
          execute: (n, context) {
            executions++;
            return n * 2;
          },
        ),
      ],
    );
    final paused = await agent.generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'first',
        messages: [ChatMessage.user('Double 21', id: 'u')],
      ),
      ownerId: 'owner',
      context: 'app',
    );
    assert(paused.status == RunStatus.interrupted && executions == 0);
    final resumed = await agent.generate(
      ChatRequest(
        threadId: 'thread',
        runId: 'second',
        parentRunId: paused.runId,
        resume: [paused.interrupts.single.approve()],
      ),
      ownerId: 'owner',
      context: 'app',
    );
    assert(resumed.text == '42' && executions == 1 && count == 4);
    print(
      'PASS native options, structured output, approval and tool history replay',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
  await edgeCases();
}

Future<void> edgeCases() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var count = 0;
  server.listen((request) async {
    await request.drain<void>();
    count++;
    if (count == 1) {
      request.response.statusCode = 429;
      request.response.headers.set('x-request-id', 'request-123');
      request.response.write('{"error":{"message":"private-provider-detail"}}');
    } else {
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      if (count == 2) {
        request.response.write(
          'data: {"choices":[{"index":0,"delta":{"content":"partial"},"finish_reason":"length"}]}\n\ndata: [DONE]\n\n',
        );
      } else {
        for (final arguments in ['{"answer":', '21}']) {
          request.response.write(
            'data: ${jsonEncode({
              'choices': [
                {
                  'index': 0,
                  'delta': {
                    'tool_calls': [
                      {
                        'index': 0,
                        'id': 'call',
                        'type': 'function',
                        'function': {'name': 'double', 'arguments': arguments},
                      },
                    ],
                  },
                  'finish_reason': arguments == '21}' ? 'tool_calls' : null,
                },
              ],
            })}\n\n',
          );
        }
        request.response.write('data: [DONE]\n\n');
      }
    }
    await request.response.close();
  });
  final client = together.TogetherClient(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}/v1',
  );
  final model = together.TogetherChatModel(
    client: client,
    model: 'fixture',
    options: together.TogetherChatOptions(
      compliance: together.TogetherCompliance.hipaa,
      contextLengthExceededBehavior:
          together.TogetherContextLengthBehavior.truncate,
      reasoningEffort: together.TogetherReasoningEffort.low,
    ),
  );
  try {
    Object? failure;
    try {
      await generateText(model: model, prompt: 'fail');
    } catch (error) {
      failure = error;
    }
    assert(failure is AgentRunException);
    final cause =
        (failure as AgentRunException).cause as together.TogetherException;
    assert(cause.statusCode == 429 && cause.requestId == 'request-123');
    assert(
      (cause.details!['error'] as Map)['message'] == 'private-provider-detail',
    );
    assert(!cause.toString().contains('private-provider-detail'));
    var immutable = false;
    try {
      (cause.details!['error'] as Map)['message'] = 'changed';
    } on UnsupportedError {
      immutable = true;
    }
    assert(immutable);
    final partial = await generateText(model: model, prompt: 'bounded');
    assert(partial.text == 'partial' && partial.finishReason == 'length');
    final events = await model
        .stream(
          ModelRequest(messages: [ChatMessage.user('call', id: 'u')]),
          cancellation: CancellationToken(),
        )
        .toList();
    final call = events.whereType<ToolCallReady>().single.call;
    assert(
      call.id == 'call' &&
          call.name == 'double' &&
          call.arguments['answer'] == 21,
    );
    print(
      'PASS safe high-level error cause, partial length and repeated call metadata',
    );
  } finally {
    client.close();
    await server.close(force: true);
  }
}
