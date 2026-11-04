import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as api;
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

const _remote = <String, Object?>{
  'type': 'mcp_tool_use',
  'id': 'PRIVATE-REMOTE-ID',
  'server_name': 'support',
  'name': 'escalate',
  'input': {'ticket': 42, 'opaque': 'PRIVATE-INPUT'},
  'opaque': 'PRIVATE-CALL',
};
const _listing = <String, Object?>{
  'type': 'mcp_tool_listing',
  'mcp_server_name': 'support',
  'tools': [
    {
      'name': 'escalate',
      'description': 'PRIVATE-LISTING',
      'input_schema': {'type': 'object'},
    },
  ],
  'opaque': 'PRIVATE-DISCOVERY',
};
const _remoteResult = <String, Object?>{
  'type': 'mcp_tool_result',
  'tool_use_id': 'PRIVATE-REMOTE-ID',
  'is_error': false,
  'content': [
    {'type': 'text', 'text': 'PRIVATE-REMOTE-RESULT'},
  ],
  'opaque': 'PRIVATE-RESULT',
};

void main() {
  withServerpod('Anthropic MCP PostgreSQL continuation', (builder, _) {
    for (final beta in api.AnthropicMcpBeta.values) {
      test('recreates a mixed local/MCP turn with ${beta.header}', () async {
        final provider = await _Provider.start(
          (call) => (
            blocks: call == 1
                ? [
                    if (beta == api.AnthropicMcpBeta.client20260915) _listing,
                    _remote,
                    {
                      'type': 'tool_use',
                      'id': 'local-id',
                      'name': 'escalate',
                      'input': <String, Object?>{},
                    },
                  ]
                : [
                    _remoteResult,
                    {'type': 'text', 'text': 'Done'},
                  ],
            reason: call == 1 ? 'tool_use' : 'end_turn',
          ),
        );
        addTearDown(provider.close);
        final client = api.AnthropicNativeClient.withApiKey(
          apiKey: 'fixture',
          baseUrl: provider.url,
          betas: ['prompt-caching-fixture'],
          headers: {'x-fixture': 'retained'},
        );
        addTearDown(client.close);
        var effects = 0;
        var token = 'PRIVATE-FIRST-TOKEN';
        AiAgent<void> agent({String variation = 'same'}) => AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          model: client.chatModel(
            model: variation == 'model' ? 'different' : 'fixture',
            authorityBindingId: variation == 'authority' ? 'other' : 'owner',
            options: {'temperature': variation == 'options' ? 0.4 : 0.2},
            mcpServers: [
              api.AnthropicMcpServer(
                name: 'support',
                url: Uri.parse(
                  variation == 'server'
                      ? 'https://changed.example.invalid/mcp'
                      : 'https://PRIVATE-SERVER.example.invalid/mcp',
                ),
                beta: variation == 'beta'
                    ? (beta == api.AnthropicMcpBeta.client20251120
                          ? api.AnthropicMcpBeta.client20260915
                          : api.AnthropicMcpBeta.client20251120)
                    : beta,
                credentialBindingId: variation == 'binding' ? 'other' : 'owner',
                authorizationToken: () => token,
              ),
            ],
          ),
          tools: [
            Tool<JsonObject, String, void>(
              name: 'escalate',
              description: 'Escalate a local ticket',
              inputSchema: const {'type': 'object'},
              outputSchema: const {'type': 'string'},
              needsApproval: true,
              decode: (input) => input,
              encode: (value) => value,
              execute: (_, context) {
                expect(context.approved, true);
                effects++;
                return 'Local result';
              },
            ),
          ],
        );
        final first = await agent().generate(
          ChatRequest(
            threadId: 'mixed',
            runId: 'first',
            messages: [ChatMessage.user('Escalate', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(first.status, RunStatus.interrupted);
        expect(first.interrupts, hasLength(1));
        expect(first.interrupts.single.call.name, 'escalate');
        expect(
          first.interrupts.single.call,
          isNot(isA<ProviderApprovalCall>()),
        );
        expect(effects, 0);
        final answer = first.interrupts.single.approve();
        final saved = await agent().store.load(
          ownerId: 'owner',
          threadId: 'mixed',
        );
        expect(jsonEncode(saved), contains('PRIVATE-REMOTE-ID'));
        expect(jsonEncode(saved), isNot(contains(token)));
        expect(
          await agent().store.load(ownerId: 'other', threadId: 'mixed'),
          isNull,
        );
        final journal = await agent().store.events(
          ownerId: 'owner',
          threadId: 'mixed',
          runId: 'first',
        );
        expect(
          jsonEncode({'history': chatHydration(saved), 'events': journal}),
          isNot(contains('PRIVATE-')),
        );
        for (final variation in [
          'server',
          'binding',
          'authority',
          'options',
          'model',
          'beta',
        ]) {
          await expectLater(
            agent(variation: variation).generate(
              ChatRequest(
                threadId: 'mixed',
                runId: 'changed-$variation',
                parentRunId: 'first',
                resume: [answer],
              ),
              ownerId: 'owner',
              context: null,
            ),
            throwsA(
              isA<AgentRunException>().having(
                (e) => e.code,
                'code',
                'INVALID_INPUT',
              ),
            ),
          );
          expect(effects, 0);
          expect(provider.requests, hasLength(1));
          expect(
            await agent().store.load(ownerId: 'owner', threadId: 'mixed'),
            saved,
          );
        }
        token = 'PRIVATE-REFRESHED-TOKEN';
        final completed = await agent().generate(
          ChatRequest(
            threadId: 'mixed',
            runId: 'resume',
            parentRunId: 'first',
            resume: [answer],
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(completed.status, RunStatus.completed);
        expect(completed.text, 'Done');
        expect(effects, 1);
        expect(provider.requests, hasLength(2));
        expect(
          (provider.requests.last['mcp_servers'] as List)
              .single['authorization_token'],
          token,
        );
        expect(
          provider.betas.every(
            (flags) =>
                flags!.contains(beta.header) &&
                flags.contains('prompt-caching-fixture'),
          ),
          true,
        );
        expect(provider.extraHeaders, ['retained', 'retained']);
        final replay = (provider.requests.last['messages'] as List)
            .where((message) => message['role'] == 'assistant')
            .expand((message) => message['content'] as List)
            .toList();
        expect(
          replay.singleWhere((block) => block['type'] == 'mcp_tool_use'),
          _remote,
        );
        if (beta == api.AnthropicMcpBeta.client20260915) {
          expect(
            replay.singleWhere((block) => block['type'] == 'mcp_tool_listing'),
            _listing,
          );
        }
        final results =
            ((provider.requests.last['messages'] as List).last['content']
                as List);
        expect(results.first['type'], 'tool_result');
        expect(results.first['tool_use_id'], 'local-id');
        final finalState = await agent().store.load(
          ownerId: 'owner',
          threadId: 'mixed',
        );
        expect(jsonEncode(finalState), isNot(contains(token)));
        expect(
          jsonEncode(chatHydration(finalState)),
          isNot(contains('PRIVATE-')),
        );
      });
    }
    test(
      'provider pause survives reload and keeps listing replay private',
      () async {
        final provider = await _Provider.start(
          (call) => (
            blocks: call == 1
                ? [_listing, _remote]
                : [
                    _remoteResult,
                    {'type': 'text', 'text': 'Continued'},
                  ],
            reason: call == 1 ? 'pause_turn' : 'end_turn',
          ),
        );
        addTearDown(provider.close);
        final client = api.AnthropicNativeClient.withApiKey(
          apiKey: 'fixture',
          baseUrl: provider.url,
        );
        addTearDown(client.close);
        AiAgent<void> agent({bool changed = false}) => AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          maxSteps: 1,
          model: client.chatModel(
            model: 'fixture',
            authorityBindingId: changed ? 'different' : 'owner',
            mcpServers: [
              api.AnthropicMcpServer(
                name: 'support',
                url: Uri.parse('https://example.invalid/mcp'),
                beta: api.AnthropicMcpBeta.client20260915,
              ),
            ],
          ),
        );
        await expectLater(
          agent().generate(
            ChatRequest(
              threadId: 'paused',
              runId: 'first',
              messages: [ChatMessage.user('Continue', id: 'u')],
            ),
            ownerId: 'owner',
            context: null,
          ),
          throwsA(
            isA<AgentRunException>().having(
              (e) => e.code,
              'code',
              'STEP_LIMIT',
            ),
          ),
        );
        final checkpoint = await agent().store.load(
          ownerId: 'owner',
          threadId: 'paused',
        );
        expect(checkpoint!['providerContinuationPending'], true);
        expect(checkpoint['providerApprovalIndeterminate'], isNot(true));
        await expectLater(
          agent(changed: true).generate(
            ChatRequest(
              threadId: 'paused',
              runId: 'changed',
              parentRunId: 'first',
            ),
            ownerId: 'owner',
            context: null,
          ),
          throwsA(
            isA<AgentRunException>().having(
              (e) => e.code,
              'code',
              'INVALID_INPUT',
            ),
          ),
        );
        expect(provider.requests, hasLength(1));
        final completed = await agent().generate(
          ChatRequest(
            threadId: 'paused',
            runId: 'resume',
            parentRunId: 'first',
          ),
          ownerId: 'owner',
          context: null,
        );
        expect(completed.text, 'Continued');
        expect(provider.requests, hasLength(2));
        expect((provider.requests.last['messages'] as List).last['content'], [
          _listing,
          _remote,
        ]);
        expect(
          jsonEncode(
            chatHydration(
              await agent().store.load(ownerId: 'owner', threadId: 'paused'),
            ),
          ),
          isNot(contains('PRIVATE-')),
        );
      },
    );
    test(
      'uncertain MCP send stays closed after PostgreSQL recreation',
      () async {
        final provider = await _Provider.start(
          (_) => (blocks: <JsonObject>[], reason: 'end_turn'),
          fail: true,
        );
        addTearDown(provider.close);
        final client = api.AnthropicNativeClient.withApiKey(
          apiKey: 'fixture',
          baseUrl: provider.url,
        );
        addTearDown(client.close);
        AiAgent<void> agent() => AiAgent<void>(
          store: ServerpodRunStore(builder.build()),
          model: client.chatModel(
            model: 'fixture',
            authorityBindingId: 'owner',
            mcpServers: [
              api.AnthropicMcpServer(
                name: 'support',
                url: Uri.parse('https://example.invalid/mcp'),
                beta: api.AnthropicMcpBeta.client20251120,
              ),
            ],
          ),
        );
        await expectLater(
          agent().generate(
            ChatRequest(
              threadId: 'uncertain',
              runId: 'first',
              messages: [ChatMessage.user('Execute', id: 'u')],
            ),
            ownerId: 'owner',
            context: null,
          ),
          throwsA(isA<AgentRunException>()),
        );
        final saved = await agent().store.load(
          ownerId: 'owner',
          threadId: 'uncertain',
        );
        expect(saved!['providerApprovalIndeterminate'], true);
        await expectLater(
          agent().generate(
            ChatRequest(
              threadId: 'uncertain',
              runId: 'retry',
              parentRunId: 'first',
            ),
            ownerId: 'owner',
            context: null,
          ),
          throwsA(
            isA<AgentRunException>().having(
              (e) => e.code,
              'code',
              'INVALID_INPUT',
            ),
          ),
        );
        expect(provider.requests, hasLength(1));
      },
    );
  });
}

typedef _Reply = ({List<JsonObject> blocks, String reason});

final class _Provider {
  final HttpServer _server;
  final _Reply Function(int) _reply;
  final bool fail;
  final requests = <JsonObject>[];
  final betas = <String?>[];
  final extraHeaders = <String?>[];
  _Provider._(this._server, this._reply, this.fail) {
    _server.listen(_handle);
  }
  static Future<_Provider> start(
    _Reply Function(int) reply, {
    bool fail = false,
  }) async => _Provider._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    reply,
    fail,
  );
  String get url => 'http://127.0.0.1:${_server.port}';
  Future<void> close() => _server.close(force: true);
  Future<void> _handle(HttpRequest request) async {
    requests.add(
      jsonDecode(await utf8.decoder.bind(request).join()) as JsonObject,
    );
    betas.add(request.headers.value('anthropic-beta'));
    extraHeaders.add(request.headers.value('x-fixture'));
    if (fail) {
      request.response.statusCode = 503;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'type': 'error',
          'error': {'type': 'overloaded_error', 'message': 'Fixture'},
        }),
      );
    } else {
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      final reply = _reply(requests.length);
      final events = <JsonObject>[
        {
          'type': 'message_start',
          'message': {
            'id': 'm',
            'model': 'fixture',
            'content': [],
            'usage': {'input_tokens': 1, 'output_tokens': 0},
          },
        },
        for (var i = 0; i < reply.blocks.length; i++) ...[
          {
            'type': 'content_block_start',
            'index': i,
            'content_block': reply.blocks[i],
          },
          {'type': 'content_block_stop', 'index': i},
        ],
        {
          'type': 'message_delta',
          'delta': {'stop_reason': reply.reason},
          'usage': {'output_tokens': 1},
        },
        {'type': 'message_stop'},
      ];
      for (final event in events) {
        request.response.write('data: ${jsonEncode(event)}\n\n');
      }
    }
    await request.response.close();
  }
}
