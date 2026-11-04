import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Chat and Responses forward Parallel options and nullable Responses finish',
    () async {
      final bodies = <String, Map<String, dynamic>>{};
      final client = router.OpenRouterClient.withApiKey(
        apiKey: 'fixture',
        httpClient: MockClient((request) async {
          bodies[request.url.path] =
              jsonDecode(request.body) as Map<String, dynamic>;
          if (request.url.path.endsWith('/chat/completions')) {
            final chunk = {
              'id': 'c',
              'object': 'chat.completion.chunk',
              'created': 1,
              'model': 'fixture',
              'choices': [
                {
                  'index': 0,
                  'delta': {'content': 'chat'},
                  'finish_reason': 'stop',
                },
              ],
            };
            return http.Response(
              'data: ${jsonEncode(chunk)}\n\ndata: [DONE]\n\n',
              200,
            );
          }
          final response = <String, Object?>{
            'id': 'r',
            'model': 'fixture',
            'output': <Object?>[],
            'error': null,
            'incomplete_details': null,
            'instructions': null,
            'max_output_tokens': null,
            'max_tool_calls': null,
            'reasoning': null,
            'text': null,
            'top_logprobs': null,
            'truncation': null,
          };
          return http.Response(
            'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': 'responses'})}\n\n'
            'data: ${jsonEncode({'type': 'response.completed', 'response': response})}\n\ndata: [DONE]\n\n',
            200,
          );
        }),
      );
      addTearDown(client.close);
      final provider = router.OpenRouterProviderPreferences(
        options: {
          'parallel': {'future_setting': 42},
        },
      );
      final chat = await generateText(
        model: router.OpenRouterChatModel(
          client: client,
          model: 'fixture',
          options: router.OpenRouterChatOptions(provider: provider),
        ),
        prompt: 'hello',
      );
      final responses = await generateText(
        model: router.OpenRouterResponsesModel(
          client: client,
          model: 'fixture',
          options: router.OpenRouterResponsesOptions(provider: provider),
        ),
        prompt: 'hello',
      );
      expect(chat.text, 'chat');
      expect(responses.text, 'responses');
      for (final path in ['/api/v1/chat/completions', '/api/v1/responses']) {
        expect(bodies[path]!['provider']['options'], {
          'parallel': {'future_setting': 42},
        });
      }
    },
  );
  test('Image generation forwards Parallel native options', () async {
    late Map<String, dynamic> body;
    final client = router.OpenRouterClient.withApiKey(
      apiKey: 'fixture',
      httpClient: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"created":1,"data":[{"b64_json":"eA=="}]}', 200);
      }),
    );
    addTearDown(client.close);
    final result = await router.OpenRouterImageModel(client: client).generate(
      router.OpenRouterImageRequest(
        model: 'fixture',
        prompt: 'hello',
        provider: router.OpenRouterImageProviderPreferences(
          options: {
            'parallel': {'future_setting': 42},
          },
        ),
      ),
    );
    expect(result.data.single.bytes, [120]);
    expect(body['provider']['options'], {
      'parallel': {'future_setting': 42},
    });
  });
  test('Image discovery retains fractional range bounds', () async {
    final client = router.OpenRouterClient.withApiKey(
      apiKey: 'fixture',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'id': 'author/model',
            'endpoints': [
              {
                'provider_name': 'Parallel',
                'provider_slug': 'parallel',
                'provider_tag': 'parallel',
                'supports_streaming': false,
                'allowed_passthrough_parameters': <String>[],
                'pricing': <Object?>[],
                'supported_parameters': {
                  'guidance': {'type': 'range', 'min': 0.25, 'max': 9.75},
                },
              },
            ],
          }),
          200,
        ),
      ),
    );
    addTearDown(client.close);
    final response = await router.OpenRouterImageModel(
      client: client,
    ).listModelEndpoints('author', 'model');
    final range =
        response.endpoints.single.supportedParameters['guidance']
            as router.OpenRouterImageRangeCapability;
    expect(range.min, 0.25);
    expect(range.max, 9.75);
  });
}
