import 'dart:convert';
import 'dart:io';
import 'package:agent_weave_vercel_gateway/agent_weave_vercel_gateway.dart';

void main() {
  final options = GatewayOptions(
    models: ['provider/fallback'],
    order: ['provider'],
    only: ['provider'],
    caching: GatewayCaching.auto,
    byokProviderTimeouts: {'openai': 15000},
    disallowPromptTraining: true,
    zeroDataRetention: true,
    has: ['tool-use', '!quantization:fp8'],
    quotaEntityId: 'tenant-1',
    serviceTier: GatewayServiceTier.priority,
    sort: GatewayProviderSort.ttft,
    tags: ['fixture'],
    user: 'user-1',
  );
  final file = File('.dart_tool/gateway-options.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(options.toJson()));
}
