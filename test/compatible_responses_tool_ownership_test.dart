import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;
import 'package:agent_weave_vercel_gateway/agent_weave_vercel_gateway.dart'
    as gateway;
import 'package:agent_weave_cloudflare/agent_weave_cloudflare.dart'
    as cloudflare;
import 'package:agent_weave_openai/agent_weave_openai.dart' as sdk;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final provider in ['openrouter', 'vercel', 'cloudflare']) {
    test('$provider Responses rejects unregistered function tool', () async {
      var sent = false;
      final httpClient = MockClient((_) async {
        sent = true;
        throw StateError('must not send');
      });
      sdk.CreateResponseRequest configure(sdk.CreateResponseRequest request) =>
          sdk.CreateResponseRequest.fromJson({
            ...request.toJson(),
            'tools': [
              {
                'type': 'function',
                'name': 'unregistered',
                'parameters': {'type': 'object'},
                'strict': false,
              },
            ],
          });
      final routerClient = router.OpenRouterClient.withApiKey(
        apiKey: 'fixture',
        httpClient: httpClient,
      );
      final gatewayClient = gateway.GatewayClient.withApiKey(
        apiKey: 'fixture',
        httpClient: httpClient,
      );
      final cloudflareClient = cloudflare.CloudflareClient.withApiToken(
        accountId: 'fixture',
        apiToken: 'fixture',
        httpClient: httpClient,
      );
      final ChatModel model = switch (provider) {
        'openrouter' => router.OpenRouterResponsesModel(
          client: routerClient,
          model: 'fixture',
          configure: configure,
        ),
        'vercel' => gateway.GatewayResponsesModel(
          client: gatewayClient,
          model: 'fixture',
          configure: configure,
        ),
        _ => cloudflare.CloudflareCompatibleResponsesModel(
          client: cloudflare.CloudflareCompatibleClient(
            client: cloudflareClient,
          ),
          model: 'fixture',
          configure: configure,
        ),
      };
      try {
        await expectLater(
          model
              .stream(
                ModelRequest(messages: [ChatMessage.user('Hi', id: 'u')]),
                cancellation: CancellationToken(),
              )
              .toList(),
          throwsArgumentError,
        );
        expect(sent, false);
      } finally {
        routerClient.close();
        gatewayClient.close();
        cloudflareClient.close();
        httpClient.close();
      }
    });
  }
}
