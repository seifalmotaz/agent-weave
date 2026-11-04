import 'dart:convert';

import 'package:agent_weave_cloudflare/agent_weave_cloudflare.dart';
import 'package:agent_weave_together/agent_weave_together.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Future<void> main() async {
  final seen = <http.Request>[];
  final transport = MockClient((request) async {
    seen.add(request);
    return http.Response(
      '{"success":true}',
      200,
      headers: {'cf-aig-request-id': 'request-1', 'cf-aig-cache-status': 'HIT'},
    );
  });
  final defaults = CloudflareGatewayOptions(
    gatewayId: 'default-id',
    cacheTtl: 10,
  );
  final client = CloudflareClient.withApiToken(
    accountId: 'account',
    apiToken: 'fixture',
    httpClient: transport,
    gateway: defaults,
  );
  final gateway = CloudflareGatewayClient(client: client);
  try {
    final result = await gateway.runJson('@cf/model', {
      'prompt': 'hello',
    }, gateway: CloudflareGatewayOptions(cacheTtl: 60));
    assert(seen.last.headers['cf-aig-gateway-id'] == 'default-id');
    assert(seen.last.headers['cf-aig-cache-ttl'] == '60');
    assert(result.requestId == 'request-1');
    assert(result.cacheStatus == 'HIT');
    await gateway.runJson(
      '@cf/model',
      {},
      gateway: CloudflareGatewayOptions(gatewayId: 'other-id'),
    );
    assert(seen.last.headers['cf-aig-gateway-id'] == 'other-id');
    assert(seen.last.headers['cf-aig-cache-ttl'] == '10');
    await gateway.runJson('@cf/model', {});
    assert(seen.last.headers['cf-aig-gateway-id'] == 'default-id');
    assert(seen.last.headers['cf-aig-cache-ttl'] == '10');
    assert(defaults.headers['cf-aig-cache-ttl'] == '10');
  } finally {
    client.close();
    transport.close();
  }

  final togetherTransport = MockClient((request) async {
    assert(request.url.queryParameters['trace'] == 'a b');
    assert(request.headers['x-consumer'] == 'fixture');
    assert(request.headers['authorization'] == 'Bearer fixture');
    assert((jsonDecode(request.body) as Map)['temperature'] == 0.3);
    return http.Response('{"choices":[]}', 200);
  });
  final together = TogetherClient(
    apiKey: 'fixture',
    httpClient: togetherTransport,
    headers: {'x-consumer': 'fixture'},
    query: {'trace': 'a b'},
  );
  try {
    await together.createChat({
      'model': 'model',
      'messages': [],
      'temperature': 0.3,
    });
  } finally {
    together.close();
    togetherTransport.close();
  }
  print('Provider options consumer checks passed');
}
