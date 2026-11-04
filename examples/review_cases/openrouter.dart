// Run from the workspace root with: dart --enable-asserts run examples/review_cases/openrouter.dart
// Offline loopback only; no provider credentials are required.
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final handled = server.first.then((request) async {
    final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
    assert(request.uri.path == '/api/v1/chat/completions');
    assert(request.headers.value('x-title') == 'Review');
    assert(body['model'] == 'example/model');
    assert(
      ((body['messages'] as List).single['content'] as List).single['text'] ==
          'Summarize this',
    );
    assert((body['provider'] as Map)['allow_fallbacks'] == false);
    request.response.headers.contentType = ContentType('text', 'event-stream');
    request.response.write(
      'data: ${jsonEncode({
        'id': 'fixture',
        'object': 'chat.completion.chunk',
        'created': 0,
        'model': 'example/model',
        'choices': [
          {
            'index': 0,
            'delta': {'content': 'Summary'},
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
        'model': 'example/model',
        'choices': [
          {'index': 0, 'delta': <String, Object?>{}, 'finish_reason': 'stop'},
        ],
      })}\n\ndata: [DONE]\n\n',
    );
    await request.response.close();
  });
  final client = router.OpenRouterClient.withApiKey(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${server.port}/api/v1',
    appName: 'Review',
  );
  try {
    final model = router.OpenRouterChatModel(
      client: client,
      model: 'example/model',
      options: router.OpenRouterChatOptions(
        provider: router.OpenRouterProviderPreferences(allowFallbacks: false),
      ),
    );
    final result = await generateText(model: model, prompt: 'Summarize this');
    assert(result.text == 'Summary');
    await handled;
    print('OpenRouter consumer loopback OK: ${result.text}');
  } finally {
    client.close();
    await server.close(force: true);
  }
  final errorServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final errorHandled = errorServer.first.then((request) async {
    await request.drain<void>();
    request.response.headers.contentType = ContentType('text', 'event-stream');
    request.response.write(
      'data: {"error":{"message":"upstream failed","code":502}}\n\n',
    );
    await request.response.close();
  });
  final errorClient = router.OpenRouterClient.withApiKey(
    apiKey: 'fixture',
    baseUrl: 'http://127.0.0.1:${errorServer.port}/api/v1',
  );
  try {
    final model = router.OpenRouterChatModel(
      client: errorClient,
      model: 'example/model',
    );
    Object? failure;
    try {
      await generateText(model: model, prompt: 'Hello');
    } catch (error) {
      failure = error;
    }

    assert(failure is AgentRunException && failure.code == 'MODEL_FAILED');
    assert(
      (failure as AgentRunException).cause.toString().contains(
        'OpenRouter request failed',
      ),
    );
    await errorHandled;
    print('OpenRouter inline error surfaced: $failure');
  } finally {
    errorClient.close();
    await errorServer.close(force: true);
  }
}
