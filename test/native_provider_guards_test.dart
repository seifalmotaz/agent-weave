import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;
import 'package:agent_weave_cloudflare/agent_weave_cloudflare.dart'
    as cloudflare;
import 'package:agent_weave_together/agent_weave_together.dart' as together;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final provider in ['Anthropic', 'Together', 'Cloudflare']) {
    test(
      '$provider rejects foreign native definitions and history before HTTP',
      () async {
        var sent = 0;
        final transport = MockClient((_) async {
          sent++;
          return http.Response('{}', 200);
        });
        final (model, close) = switch (provider) {
          'Anthropic' => () {
            final client = anthropic.AnthropicClient.withApiKey(
              'fixture',
              httpClient: transport,
            );
            return (
              anthropic.AnthropicChatModel(client: client, model: 'fixture'),
              client.close,
            );
          }(),
          'Together' => () {
            final client = together.TogetherClient(
              apiKey: 'fixture',
              httpClient: transport,
            );
            return (
              together.TogetherChatModel(client: client, model: 'fixture'),
              client.close,
            );
          }(),
          _ => () {
            final client = cloudflare.CloudflareClient.withApiToken(
              accountId: 'fixture',
              apiToken: 'fixture',
              httpClient: transport,
            );
            return (
              cloudflare.CloudflareChatModel(
                client: client,
                model: '@hf/nousresearch/hermes-2-pro-mistral-7b',
              ),
              client.close,
            );
          }(),
        };
        addTearDown(close);
        addTearDown(transport.close);
        for (final history in [false, true]) {
          final request = ModelRequest(
            messages: [
              ChatMessage.user('Hello', id: 'u'),
              if (history)
                ChatMessage(
                  id: 'a',
                  role: MessageRole.assistant,
                  toolCalls: [
                    NativeToolCall(
                      id: 'call',
                      name: 'computer',
                      arguments: {},
                      provider: 'openai.responses',
                    ),
                  ],
                ),
            ],
            tools: [
              if (!history)
                NativeModelTool(
                  name: 'computer',
                  description: 'Computer',
                  inputSchema: {'type': 'object'},
                  provider: 'openai.responses',
                  definition: {'type': 'computer'},
                  bindingId: 'browser-1',
                ),
            ],
          );
          await expectLater(
            model.stream(request, cancellation: CancellationToken()).toList(),
            throwsUnsupportedError,
          );
        }
        expect(sent, 0);
      },
    );
  }
}
