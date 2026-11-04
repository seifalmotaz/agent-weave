import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const events =
    'event: message_start\ndata: {"type":"message_start","message":{"id":"m","type":"message","role":"assistant","model":"fixture","content":[],"usage":{"input_tokens":1,"output_tokens":0}}}\n\nevent: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":0}}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n';
void main() {
  test(
    'native MCP injection rejects before repeated provider effects',
    () async {
      var effects = 0;
      final transport = MockClient((_) async {
        effects++;
        return http.Response(
          events,
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });
      final client = AnthropicNativeClient.withApiKey(
        apiKey: 'key',
        httpClient: transport,
      );
      addTearDown(() {
        client.close();
        transport.close();
      });
      final store = MemoryRunStore();
      String? parentRunId;
      var attempt = 0;
      for (final value in <Object>[
        [
          {
            'type': 'url',
            'url': 'https://example.invalid/mcp',
            'name': 'x',
            'authorization_token': 'SECRET',
            'tool_configuration': {'enabled': true},
          },
        ],
        'invalid',
        42,
        <String, Object?>{},
      ]) {
        for (var retry = 0; retry < 2; retry++) {
          final runId = 'attempt-${attempt++}';
          final agent = AiAgent<void>(
            model: client.chatModel(
              model: 'fixture',
              configure: (body) => {...body, 'mcp_servers': value},
            ),
            store: store,
          );
          try {
            await agent.generate(
              ChatRequest(
                threadId: 't',
                runId: runId,
                parentRunId: parentRunId,
                messages: [ChatMessage.user('hi', id: 'user-$runId')],
              ),
              ownerId: 'owner',
              context: null,
            );
            fail('Expected rejection');
          } on AgentRunException catch (error) {
            expect(error.cause, isA<UnsupportedError>());
            expect(error.cause.toString(), contains('not integrated'));
            expect(error.cause.toString(), isNot(contains('SECRET')));
            parentRunId = runId;
          }
        }
      }
      expect(effects, 0);
      expect(
        jsonEncode(
          chatHydration(await store.load(ownerId: 'owner', threadId: 't')),
        ),
        isNot(contains('SECRET')),
      );
    },
  );
  test('null and empty server lists pass through unchanged', () async {
    final bodies = <Map<String, dynamic>>[];
    final transport = MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        events,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final client = AnthropicNativeClient.withApiKey(
      apiKey: 'key',
      httpClient: transport,
    );
    addTearDown(() {
      client.close();
      transport.close();
    });
    for (final value in [null, <Object?>[]]) {
      await client
          .chatModel(
            model: 'fixture',
            configure: (body) => {
              ...body,
              'mcp_servers': value,
              'temperature': 0.2,
            },
          )
          .stream(
            ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList();
    }
    expect(bodies.length, 2);
    expect(bodies[0]['mcp_servers'], isNull);
    expect(bodies[1]['mcp_servers'], isEmpty);
    expect(bodies.every((body) => body['temperature'] == 0.2), true);
  });
  test('modern MCP toolset remains blocked before transport', () async {
    var effects = 0;
    final transport = MockClient((_) async {
      effects++;
      return http.Response(events, 200);
    });
    final client = AnthropicNativeClient.withApiKey(
      apiKey: 'key',
      httpClient: transport,
    );
    addTearDown(() {
      client.close();
      transport.close();
    });
    await expectLater(
      client
          .chatModel(
            model: 'fixture',
            configure: (body) => {
              ...body,
              'tools': [
                {'type': 'mcp_toolset', 'mcp_server_name': 'x'},
              ],
            },
          )
          .stream(
            ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList(),
      throwsArgumentError,
    );
    expect(effects, 0);
  });
  test(
    'raw native API retains explicit MCP configuration and response data',
    () async {
      JsonObject? sent;
      const block = <String, Object?>{
        'type': 'mcp_tool_use',
        'id': 'native-call',
        'name': 'lookup',
        'server_name': 'support',
        'input': <String, Object?>{},
      };
      final transport = MockClient((request) async {
        sent = jsonDecode(request.body) as JsonObject;
        return http.Response(
          jsonEncode({
            'content': [block],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = AnthropicNativeClient.withApiKey(
        apiKey: 'fixture',
        httpClient: transport,
      );
      addTearDown(client.close);
      addTearDown(transport.close);
      final response = await client.createMessage({
        'model': 'fixture',
        'max_tokens': 16,
        'mcp_servers': [
          {
            'type': 'url',
            'name': 'support',
            'url': 'https://support.example.invalid/mcp',
          },
        ],
        'messages': [
          {'role': 'user', 'content': 'Lookup'},
        ],
      });
      expect(sent!['mcp_servers'], isNotEmpty);
      expect(response.data['content'], [block]);
    },
  );
  test('typed facade cannot retain unsupported MCP server field', () async {
    var effects = 0;
    final transport = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      expect(body.containsKey('mcp_servers'), false);
      effects++;
      return http.Response(
        events,
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    });
    final client = api.AnthropicClient.withApiKey('key', httpClient: transport);
    addTearDown(() {
      client.close();
      transport.close();
    });
    final model = AnthropicChatModel(
      client: client,
      model: 'fixture',
      configure: (request) => api.MessageCreateRequest.fromJson({
        ...request.toJson(),
        'mcp_servers': [
          {'type': 'url', 'name': 'x', 'url': 'https://example.invalid'},
        ],
      }),
    );
    await model
        .stream(
          ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
          cancellation: CancellationToken(),
        )
        .toList();
    expect(effects, 1, reason: 'ordinary non-MCP request remains available');
  });
}
