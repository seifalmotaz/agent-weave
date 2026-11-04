import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_cloudflare/agent_weave_cloudflare.dart' as cf;

Future<void> main() async {
  final accountId = Platform.environment['CLOUDFLARE_ACCOUNT_ID'];
  final apiToken = Platform.environment['CLOUDFLARE_API_TOKEN'];
  final modelId = Platform.environment['CLOUDFLARE_CHAT_MODEL'];
  final gatewayId = Platform.environment['CLOUDFLARE_GATEWAY_ID'];
  if (accountId == null || apiToken == null || modelId == null) {
    throw StateError(
      'Set CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN and CLOUDFLARE_CHAT_MODEL.',
    );
  }
  if (modelId.startsWith('@cf/') && gatewayId == null) {
    throw StateError(
      'Set CLOUDFLARE_GATEWAY_ID for Workers AI gateway requests.',
    );
  }
  final workers = cf.CloudflareClient.withApiToken(
    accountId: accountId,
    apiToken: apiToken,
    gateway: gatewayId == null
        ? null
        : cf.CloudflareGatewayOptions(gatewayId: gatewayId),
  );
  try {
    final model = cf.CloudflareCompatibleChatModel(
      client: cf.CloudflareCompatibleClient(client: workers),
      model: modelId,
    );
    final result = await generateText(model: model, prompt: 'Say hello.');
    print(result.text);
  } finally {
    workers.close();
  }
}
