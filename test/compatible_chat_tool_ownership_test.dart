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
  const owned = ModelTool(
    name: 'lookup',
    description: 'lookup',
    inputSchema: {
      'type': 'object',
      'properties': {
        'counter': {'type': 'integer', 'maximum': 9007199254740993},
      },
    },
  );
  for (final provider in ['openrouter', 'vercel', 'cloudflare']) {
    for (final mutation in ['add', 'nested_int', 'nested_double']) {
      test('$provider rejects $mutation of runtime-owned Chat tools', () async {
        var sent = false;
        final httpClient = MockClient((_) async {
          sent = true;
          throw StateError('request should not reach HTTP');
        });
        sdk.ChatCompletionCreateRequest configure(
          sdk.ChatCompletionCreateRequest request,
        ) {
          final json = request.toJson();
          final tools = (json['tools'] as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
          if (mutation == 'add') {
            tools.add({
              'type': 'function',
              'function': {
                'name': 'unregistered',
                'parameters': {'type': 'object'},
              },
            });
          } else {
            final function = Map<String, dynamic>.from(
              tools.first['function'] as Map,
            );
            final parameters = Map<String, dynamic>.from(
              function['parameters'] as Map,
            );
            final properties = Map<String, dynamic>.from(
              parameters['properties'] as Map,
            );
            properties['counter'] = {
              'type': 'integer',
              'maximum': mutation == 'nested_double'
                  ? 9007199254740992.0
                  : 9007199254740992,
            };
            parameters['properties'] = properties;
            function['parameters'] = parameters;
            tools.first['function'] = function;
          }
          return sdk.ChatCompletionCreateRequest.fromJson({
            ...json,
            'tools': tools,
          });
        }

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
          'openrouter' => router.OpenRouterChatModel(
            client: routerClient,
            model: 'fixture',
            configure: configure,
          ),
          'vercel' => gateway.GatewayChatModel(
            client: gatewayClient,
            model: 'fixture',
            configure: configure,
          ),
          _ => cloudflare.CloudflareCompatibleChatModel(
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
                  ModelRequest(
                    messages: [ChatMessage.user('Hi', id: 'u')],
                    tools: const [owned],
                  ),
                  cancellation: CancellationToken(),
                )
                .toList(),
            throwsArgumentError,
          );
          expect(sent, isFalse);
        } finally {
          routerClient.close();
          gatewayClient.close();
          cloudflareClient.close();
          httpClient.close();
        }
      });
    }
  }
}
