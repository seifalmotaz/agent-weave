import 'dart:async';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as sdk;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'chat_test.dart' as f;

anthropic.AnthropicMcpServer server(anthropic.AnthropicMcpBeta beta) =>
    anthropic.AnthropicMcpServer(
      name: 'docs',
      url: Uri.parse('https://example.com/mcp'),
      beta: beta,
      credentialBindingId: 'owner-account',
      authorizationToken: () => 'fake-secret',
    );
List<JsonObject> frames(
  List<JsonObject> blocks, {
  String reason = 'end_turn',
}) => [
  f.start(),
  for (var i = 0; i < blocks.length; i++) ...[f.block(i, blocks[i]), f.stop(i)],
  f.finish(reason),
  f.done,
];
void main() {
  for (final beta in anthropic.AnthropicMcpBeta.values) {
    test('provider-owned MCP results normalize and replay for $beta', () async {
      final bodies = <JsonObject>[];
      final model = anthropic.AnthropicProtocolModel(
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [server(beta)],
        transport: (body, _) async* {
          bodies.add(body);
          final blocks = <JsonObject>[
            if (beta == anthropic.AnthropicMcpBeta.client20260915)
              {
                'type': 'mcp_tool_listing',
                'mcp_server_name': 'docs',
                'tools': [
                  {
                    'name': 'find',
                    'input_schema': {'type': 'object'},
                  },
                ],
                'future': 'private-listing',
              },
            {
              'type': 'mcp_tool_use',
              'id': 'mcp-1',
              'name': 'find',
              'server_name': 'docs',
              'input': {'q': 'x'},
              'future': 'opaque',
            },
            {
              'type': 'mcp_tool_result',
              'tool_use_id': 'mcp-1',
              'is_error': false,
              'content': [
                {'type': 'text', 'text': 'private-result'},
              ],
            },
          ];
          yield* Stream.fromIterable(frames(bodies.length == 1 ? blocks : []));
        },
      );
      final events = await model
          .stream(
            ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(events.whereType<ProviderExecutionStarting>(), hasLength(1));
      expect(events.whereType<ToolCallReady>(), isEmpty);
      final data = events.whereType<ProviderOutput>().singleWhere(
        (e) => e.provider == 'anthropic.messages',
      );
      expect(data.items.any((item) => item['future'] == 'opaque'), true);
      final request = bodies.single;
      expect(
        ((request['mcp_servers'] as List).single as Map)['authorization_token'],
        'fake-secret',
      );
      if (beta == anthropic.AnthropicMcpBeta.legacy20250404) {
        expect(request['tools'], isNull);
      } else {
        expect(
          ((request['tools'] as List).single as Map)['type'],
          'mcp_toolset',
        );
      }
      final history = ChatMessage(
        id: 'a',
        role: MessageRole.assistant,
        providerData: {
          for (final event in events.whereType<ProviderOutput>())
            event.provider: event.items,
        },
      );
      await model
          .stream(
            ModelRequest(
              messages: [
                ChatMessage.user('hi', id: 'u'),
                history,
                ChatMessage.user('next', id: 'u2'),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      final replay = ((bodies.last['messages'] as List)[1] as Map)['content'];
      expect(replay, data.items);
    });
  }
  for (final invalid in <List<JsonObject>>[
    [
      {
        'type': 'mcp_tool_result',
        'tool_use_id': 'unknown',
        'is_error': false,
        'content': 'x',
      },
    ],
    [
      {
        'type': 'mcp_tool_use',
        'id': 'x',
        'name': 'find',
        'server_name': 'wrong',
        'input': {},
      },
    ],
    [
      {
        'type': 'mcp_tool_use',
        'id': 'x',
        'name': 'find',
        'server_name': 'docs',
        'input': {},
      },
    ],
    [
      {
        'type': 'mcp_tool_use',
        'id': 'x',
        'name': 'find',
        'server_name': 'docs',
        'input': {},
      },
      {
        'type': 'mcp_tool_result',
        'tool_use_id': 'x',
        'is_error': false,
        'content': [
          {'type': 'image', 'source': <String, Object?>{}},
        ],
      },
    ],
  ]) {
    test(
      'malformed MCP output rejects without local calls: $invalid',
      () async {
        final model = anthropic.AnthropicProtocolModel(
          model: 'fixture',
          authorityBindingId: 'account',
          mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
          transport: (_, _) => Stream.fromIterable(frames(invalid)),
        );
        final events = <ModelEvent>[];
        await expectLater(() async {
          await for (final e in model.stream(
            ModelRequest(messages: []),
            cancellation: CancellationToken(),
          )) {
            events.add(e);
          }
        }, throwsA(anything));
        expect(events.whereType<ToolCallReady>(), isEmpty);
      },
    );
  }
  test('MCP input JSON deltas assemble by block index', () async {
    final model = anthropic.AnthropicProtocolModel(
      model: 'fixture',
      authorityBindingId: 'account',
      mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
      transport: (_, _) => Stream.fromIterable([
        f.start(),
        f.block(0, {
          'type': 'mcp_tool_use',
          'id': 'x',
          'name': 'find',
          'server_name': 'docs',
          'input': {},
        }),
        f.delta(0, {'type': 'input_json_delta', 'partial_json': '{"q":'}),
        f.delta(0, {'type': 'input_json_delta', 'partial_json': '"x"}'}),
        f.stop(0),
        f.block(1, {
          'type': 'mcp_tool_result',
          'tool_use_id': 'x',
          'is_error': false,
          'content': 'ok',
        }),
        f.stop(1),
        f.finish('end_turn'),
        f.done,
      ]),
    );
    final events = await model
        .stream(ModelRequest(messages: []), cancellation: CancellationToken())
        .toList();
    final replay = events
        .whereType<ProviderOutput>()
        .singleWhere((e) => e.provider == 'anthropic.messages')
        .items;
    expect(replay.first['input'], {'q': 'x'});
  });
  test(
    'managed declarative container, document and system options survive snapshots',
    () async {
      final bodies = <JsonObject>[];
      final container = <String, Object?>{
        'skills': [
          {'type': 'anthropic', 'skill_id': 'pdf', 'version': 'latest'},
        ],
      };
      final decorations = <String, List<JsonObject?>>{
        'u': [
          {
            'context': 'first',
            'citations': {'enabled': true},
            'cache_control': {'type': 'ephemeral'},
          },
          {
            'cache_control': {'type': 'ephemeral'},
          },
        ],
      };
      final model = anthropic.AnthropicProtocolModel(
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
        container: container,
        messageDecorations: decorations,
        systemCacheControl: const {'type': 'ephemeral'},
        transport: (body, _) async* {
          bodies.add(body);
          final start = f.start();
          (start['message'] as Map)['container'] = {'id': 'inherited'};
          yield start;
          yield f.finish('end_turn');
          yield f.done;
        },
      );
      container['skills'] = [];
      decorations['u']!.clear();
      final user = ChatMessage(
        id: 'u',
        role: MessageRole.user,
        content: [
          DocumentPart.url('https://example.com/a.pdf'),
          TextPart('hello'),
        ],
      );
      final events = await model
          .stream(
            ModelRequest(messages: [user], instructions: 'system'),
            cancellation: CancellationToken(),
          )
          .toList();
      final first = bodies.single;
      expect(((first['container'] as Map)['skills'] as List), hasLength(1));
      expect(((first['system'] as List).single as Map)['cache_control'], {
        'type': 'ephemeral',
      });
      final parts =
          ((first['messages'] as List).single as Map)['content'] as List;
      expect(parts.first['context'], 'first');
      expect(parts.first['citations'], {'enabled': true});
      expect(parts.last['cache_control'], {'type': 'ephemeral'});
      final history = ChatMessage(
        id: 'a',
        role: MessageRole.assistant,
        providerData: {
          for (final event in events.whereType<ProviderOutput>())
            event.provider: event.items,
        },
      );
      await model
          .stream(
            ModelRequest(
              messages: [
                user,
                history,
                ChatMessage.user('next', id: 'u2'),
              ],
              instructions: 'system',
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      final resumed = bodies.last['container'] as Map;
      expect(resumed['id'], 'inherited');
      expect(resumed['skills'], hasLength(1));
    },
  );
  test('MCP token echoes in metadata keys and model are redacted', () async {
    final model = anthropic.AnthropicProtocolModel(
      model: 'fixture',
      authorityBindingId: 'account',
      mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
      transport: (_, _) async* {
        final start = f.start();
        (start['message'] as Map)['model'] = 'model-fake-secret';
        (start['message'] as Map)['fake-secret'] = 'fake-secret';
        final finish = f.finish('end_turn');
        (finish['delta'] as Map)['echo'] = 'fake-secret';
        yield start;
        yield finish;
        yield f.done;
      },
    );
    final events = await model
        .stream(ModelRequest(messages: []), cancellation: CancellationToken())
        .toList();
    final metadata = events
        .whereType<ProviderOutput>()
        .singleWhere((e) => e.provider == 'anthropic.messages.metadata')
        .items;
    expect(metadata.toString(), isNot(contains('fake-secret')));
    expect(
      events.whereType<TokenUsage>().single.model,
      isNot(contains('fake-secret')),
    );
  });
  test(
    'mixed MCP and local approval binds profile before effect and permits credential rotation',
    () async {
      var requests = 0, effects = 0, token = 0;
      final bodies = <JsonObject>[];
      final store = MemoryRunStore();
      final tool = Tool<int, int, void>(
        name: 'local',
        description: '',
        inputSchema: const {'type': 'object'},
        outputSchema: const {'type': 'integer'},
        needsApproval: true,
        decode: (_) => 1,
        encode: (v) => v,
        execute: (v, _) {
          effects++;
          return v;
        },
      );
      AiAgent<void> agent(String endpoint) => AiAgent<void>(
        store: store,
        tools: [tool],
        model: anthropic.AnthropicProtocolModel(
          model: 'fixture',
          authorityBindingId: 'account',
          mcpServers: [
            anthropic.AnthropicMcpServer(
              name: 'docs',
              url: Uri.parse(endpoint),
              beta: anthropic.AnthropicMcpBeta.client20251120,
              credentialBindingId: 'owner',
              authorizationToken: () => 'token-${++token}',
            ),
          ],
          transport: (body, _) async* {
            bodies.add(body);
            requests++;
            if (requests == 1) {
              yield* Stream.fromIterable(
                frames([
                  {
                    'type': 'mcp_tool_use',
                    'id': 'remote',
                    'name': 'find',
                    'server_name': 'docs',
                    'input': {'q': 'private'},
                  },
                  {
                    'type': 'tool_use',
                    'id': 'local-1',
                    'name': 'local',
                    'input': <String, Object?>{},
                  },
                ], reason: 'tool_use'),
              );
            } else {
              yield* Stream.fromIterable(
                frames([
                  {
                    'type': 'mcp_tool_result',
                    'tool_use_id': 'remote',
                    'is_error': false,
                    'content': 'ok',
                  },
                ]),
              );
            }
          },
        ),
      );
      final paused = await agent('https://example.com/mcp').generate(
        ChatRequest(
          threadId: 'thread',
          runId: 'first',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'owner',
        context: null,
      );
      expect(paused.status, RunStatus.interrupted);
      await expectLater(
        agent('https://changed.example/mcp').generate(
          ChatRequest(
            threadId: 'thread',
            runId: 'changed',
            parentRunId: 'first',
            resume: [paused.interrupts.single.approve()],
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
      expect(requests, 1);
      expect(token, 1);
      final done = await agent('https://example.com/mcp').generate(
        ChatRequest(
          threadId: 'thread',
          runId: 'next',
          parentRunId: 'first',
          resume: [paused.interrupts.single.approve()],
        ),
        ownerId: 'owner',
        context: null,
      );
      expect(done.status, RunStatus.completed);
      expect(effects, 1);
      expect(requests, 2);
      expect(token, 2);
      expect(
        ((bodies.last['mcp_servers'] as List).single
            as Map)['authorization_token'],
        'token-2',
      );
      final turns = bodies.last['messages'] as List;
      expect((turns[1] as Map)['role'], 'assistant');
      expect(
        ((turns[1] as Map)['content'] as List).first['type'],
        'mcp_tool_use',
      );
      expect(
        ((turns.last as Map)['content'] as List).single['type'],
        'tool_result',
      );
    },
  );
  test(
    'SDK MCP 503 sends once, redacts failure, and blocks uncertain retry',
    () async {
      var requests = 0;
      final httpClient = MockClient((_) async {
        requests++;
        return http.Response('{"error":{"message":"fake-secret"}}', 503);
      });
      final client = sdk.AnthropicClient.withApiKey(
        'api-key',
        httpClient: httpClient,
      );
      addTearDown(() {
        client.close();
        httpClient.close();
      });
      final store = MemoryRunStore();
      final model = anthropic.AnthropicChatModel(
        client: client,
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
      );
      final agent = AiAgent<void>(model: model, store: store);
      try {
        await agent.generate(
          ChatRequest(
            threadId: 't',
            runId: 'first',
            messages: [ChatMessage.user('hi', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        );
        fail('Expected failure');
      } on AgentRunException catch (error) {
        expect(error.cause, isA<anthropic.JsonHttpException>());
        final cause = error.cause as anthropic.JsonHttpException;
        expect(cause.statusCode, 503);
        expect(
          cause.requestId,
          isNull,
          reason: 'SDK stream errors omit response metadata',
        );
        expect(cause.details, isNull);
        expect(cause.toString(), isNot(contains('fake-secret')));
      }
      expect(requests, 1);
      expect(
        (await store.load(
          ownerId: 'owner',
          threadId: 't',
        ))!['providerApprovalIndeterminate'],
        true,
      );
      await expectLater(
        agent.generate(
          ChatRequest(threadId: 't', runId: 'retry'),
          ownerId: 'owner',
          context: null,
        ),
        throwsA(isA<AgentRunException>()),
      );
      expect(requests, 1);
    },
  );
  for (final reason in [
    'max_tokens',
    'model_context_window_exceeded',
    'refusal',
    'tool_use',
  ]) {
    test(
      'unfinished MCP cannot terminate or skip client calls: $reason',
      () async {
        final model = anthropic.AnthropicProtocolModel(
          model: 'fixture',
          authorityBindingId: 'account',
          mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
          transport: (_, _) => Stream.fromIterable(
            frames([
              {
                'type': 'mcp_tool_use',
                'id': 'x',
                'name': 'find',
                'server_name': 'docs',
                'input': <String, Object?>{},
              },
            ], reason: reason),
          ),
        );
        final events = <ModelEvent>[];
        await expectLater(() async {
          await for (final e in model.stream(
            ModelRequest(messages: []),
            cancellation: CancellationToken(),
          )) {
            events.add(e);
          }
        }, throwsFormatException);
        expect(events.whereType<ModelFinished>(), isEmpty);
        expect(events.whereType<ToolCallReady>(), isEmpty);
      },
    );
  }
  for (final input in <Object?>[
    null,
    'text',
    3,
    [1, true],
  ]) {
    test('provider-owned MCP input preserves any JSON value: $input', () async {
      final model = anthropic.AnthropicProtocolModel(
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
        transport: (_, _) => Stream.fromIterable(
          frames([
            {
              'type': 'mcp_tool_use',
              'id': 'x',
              'name': 'find',
              'server_name': 'docs',
              'input': input,
            },
            {
              'type': 'mcp_tool_result',
              'tool_use_id': 'x',
              'is_error': false,
              'content': 'ok',
            },
          ]),
        ),
      );
      final events = await model
          .stream(ModelRequest(messages: []), cancellation: CancellationToken())
          .toList();
      expect(
        events
            .whereType<ProviderOutput>()
            .singleWhere((e) => e.provider == 'anthropic.messages')
            .items
            .first['input'],
        input,
      );
    });
  }
  test(
    'missing MCP input is rejected, fragmented scalar JSON preserved',
    () async {
      anthropic.AnthropicProtocolModel model(List<JsonObject> output) =>
          anthropic.AnthropicProtocolModel(
            model: 'fixture',
            authorityBindingId: 'account',
            mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
            transport: (_, _) => Stream.fromIterable(output),
          );
      await expectLater(
        model(
              frames([
                {
                  'type': 'mcp_tool_use',
                  'id': 'x',
                  'name': 'find',
                  'server_name': 'docs',
                },
              ]),
            )
            .stream(
              ModelRequest(messages: []),
              cancellation: CancellationToken(),
            )
            .toList(),
        throwsA(anything),
      );
      final events =
          await model([
                f.start(),
                f.block(0, {
                  'type': 'mcp_tool_use',
                  'id': 'x',
                  'name': 'find',
                  'server_name': 'docs',
                }),
                f.delta(0, {'type': 'input_json_delta', 'partial_json': '[1,'}),
                f.delta(0, {'type': 'input_json_delta', 'partial_json': '2]'}),
                f.stop(0),
                f.block(1, {
                  'type': 'mcp_tool_result',
                  'tool_use_id': 'x',
                  'is_error': false,
                  'content': 'ok',
                }),
                f.stop(1),
                f.finish('end_turn'),
                f.done,
              ])
              .stream(
                ModelRequest(messages: []),
                cancellation: CancellationToken(),
              )
              .toList();
      expect(
        events
            .whereType<ProviderOutput>()
            .singleWhere((e) => e.provider == 'anthropic.messages')
            .items
            .first['input'],
        [1, 2],
      );
    },
  );
  test(
    'pause_turn survives step limit and resumes private MCP result',
    () async {
      var requests = 0;
      final store = MemoryRunStore();
      final model = anthropic.AnthropicProtocolModel(
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
        transport: (body, _) async* {
          requests++;
          if (requests == 1) {
            yield* Stream.fromIterable(
              frames([
                {
                  'type': 'mcp_tool_use',
                  'id': 'x',
                  'name': 'find',
                  'server_name': 'docs',
                  'input': <String, Object?>{},
                },
              ], reason: 'pause_turn'),
            );
          } else {
            expect(
              ((body['messages'] as List).last as Map)['role'],
              'assistant',
            );
            yield* Stream.fromIterable(
              frames([
                {
                  'type': 'mcp_tool_result',
                  'tool_use_id': 'x',
                  'is_error': false,
                  'content': 'done',
                },
              ]),
            );
          }
        },
      );
      await expectLater(
        AiAgent<void>(model: model, store: store, maxSteps: 1).generate(
          ChatRequest(
            threadId: 't',
            runId: 'first',
            messages: [ChatMessage.user('go', id: 'u')],
          ),
          ownerId: 'owner',
          context: null,
        ),
        throwsA(
          isA<AgentRunException>().having((e) => e.code, 'code', 'STEP_LIMIT'),
        ),
      );
      final resumed = await AiAgent<void>(model: model, store: store).generate(
        ChatRequest(threadId: 't', runId: 'resume'),
        ownerId: 'owner',
        context: null,
      );
      expect(resumed.status, RunStatus.completed);
      expect(requests, 2);
    },
  );
  test(
    'cancellation releases stalled MCP credential lookup before dispatch',
    () async {
      final credentials = Completer<String>();
      final entered = Completer<void>();
      var sends = 0;
      final store = MemoryRunStore();
      final model = anthropic.AnthropicProtocolModel(
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [
          anthropic.AnthropicMcpServer(
            name: 'docs',
            url: Uri.parse('https://example.com/mcp'),
            beta: anthropic.AnthropicMcpBeta.client20251120,
            credentialBindingId: 'owner',
            authorizationToken: () {
              entered.complete();
              return credentials.future;
            },
          ),
        ],
        transport: (_, _) {
          sends++;
          return const Stream.empty();
        },
      );
      final token = CancellationToken();
      final result = AiAgent<void>(model: model, store: store).generate(
        ChatRequest(
          threadId: 't',
          runId: 'first',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'owner',
        context: null,
        cancellation: token,
      );
      await entered.future;
      token.cancel();
      await expectLater(
        result.timeout(const Duration(seconds: 2)),
        throwsA(isA<RunCancelled>()),
      );
      expect(credentials.isCompleted, false);
      expect(sends, 0);
      final state = (await store.load(ownerId: 'owner', threadId: 't'))!;
      expect(state['providerApprovalIndeterminate'], isNull);
      final previous = await store.begin(
        ownerId: 'owner',
        threadId: 't',
        runId: 'probe',
      );
      await store.save(
        ownerId: 'owner',
        threadId: 't',
        runId: 'probe',
        state: previous,
        release: true,
      );
      credentials.completeError(StateError('late credential failure'));
      await Future<void>.delayed(Duration.zero);
    },
  );
  test(
    'conflicting later MCP listing fails before the next local call',
    () async {
      var requests = 0, effects = 0;
      final tool = Tool<JsonObject, int, void>(
        name: 'local',
        description: '',
        inputSchema: const {'type': 'object'},
        outputSchema: const {'type': 'integer'},
        needsApproval: true,
        decode: (v) => v,
        encode: (v) => v,
        execute: (_, _) {
          effects++;
          return 1;
        },
      );
      final model = anthropic.AnthropicProtocolModel(
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [server(anthropic.AnthropicMcpBeta.client20260915)],
        transport: (_, _) async* {
          requests++;
          yield* Stream.fromIterable(
            frames([
              {
                'type': 'mcp_tool_listing',
                'mcp_server_name': 'docs',
                'tools': [
                  {
                    'name': requests == 1 ? 'find' : 'changed',
                    'input_schema': {'type': 'object'},
                  },
                ],
              },
              {
                'type': 'tool_use',
                'id': requests == 1 ? 'local-1' : 'local-2',
                'name': 'local',
                'input': <String, Object?>{},
              },
            ], reason: 'tool_use'),
          );
        },
      );
      final agent = AiAgent<void>(model: model, tools: [tool]);
      final paused = await agent.generate(
        ChatRequest(
          threadId: 't',
          runId: 'first',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'owner',
        context: null,
      );
      expect(paused.status, RunStatus.interrupted);
      await expectLater(
        agent.generate(
          ChatRequest(
            threadId: 't',
            runId: 'next',
            parentRunId: 'first',
            resume: [paused.interrupts.single.approve()],
          ),
          ownerId: 'owner',
          context: null,
        ),
        throwsA(isA<AgentRunException>()),
      );
      expect(
        effects,
        1,
        reason: 'only the first explicitly approved local call runs',
      );
      expect(requests, 2);
    },
  );
  for (final matches in [true, false]) {
    test(
      'explicit MCP pin rejects inconsistent listing: matches=$matches',
      () async {
        final pinned = <JsonObject>[
          {
            'name': 'find',
            'input_schema': {'type': 'object'},
          },
        ];
        final configured = anthropic.AnthropicMcpServer(
          name: 'docs',
          url: Uri.parse('https://example.com/mcp'),
          beta: anthropic.AnthropicMcpBeta.client20260915,
          toolset: anthropic.AnthropicMcpToolset(tools: pinned),
        );
        final listing = <JsonObject>[
          {
            'name': matches ? 'find' : 'changed',
            'input_schema': {'type': 'object'},
          },
        ];
        final model = anthropic.AnthropicProtocolModel(
          model: 'fixture',
          authorityBindingId: 'account',
          mcpServers: [configured],
          transport: (_, _) => Stream.fromIterable(
            frames([
              {
                'type': 'mcp_tool_listing',
                'mcp_server_name': 'docs',
                'tools': listing,
              },
            ]),
          ),
        );
        final run = model
            .stream(
              ModelRequest(messages: []),
              cancellation: CancellationToken(),
            )
            .toList();
        if (matches) {
          expect((await run).whereType<ModelFinished>(), hasLength(1));
        } else {
          await expectLater(run, throwsFormatException);
        }
      },
    );
  }
  test('identical MCP listing across turns preserves history', () async {
    var requests = 0;
    final listing = <JsonObject>[
      {
        'name': 'find',
        'input_schema': {'type': 'object'},
      },
    ];
    final model = anthropic.AnthropicProtocolModel(
      model: 'fixture',
      authorityBindingId: 'account',
      mcpServers: [server(anthropic.AnthropicMcpBeta.client20260915)],
      transport: (_, _) async* {
        requests++;
        yield* Stream.fromIterable(
          frames([
            {
              'type': 'mcp_tool_listing',
              'mcp_server_name': 'docs',
              'tools': listing,
            },
          ]),
        );
      },
    );
    final first = await model
        .stream(
          ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
          cancellation: CancellationToken(),
        )
        .toList();
    final assistant = ChatMessage(
      id: 'a',
      role: MessageRole.assistant,
      providerData: {
        for (final e in first.whereType<ProviderOutput>()) e.provider: e.items,
      },
    );
    final second = await model
        .stream(
          ModelRequest(
            messages: [
              ChatMessage.user('hi', id: 'u'),
              assistant,
              ChatMessage.user('next', id: 'u2'),
            ],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    expect(second.whereType<ModelFinished>(), hasLength(1));
    expect(requests, 2);
  });
  for (final requestId in ['request-123', 'request-fake-secret']) {
    test(
      'native MCP HTTP diagnostics preserve redacted request ID: $requestId',
      () async {
        final transport = MockClient(
          (_) async => http.Response(
            '{"error":{"message":"fake-secret"}}',
            503,
            headers: {'request-id': requestId, 'x-private': 'fake-secret'},
          ),
        );
        final client = anthropic.AnthropicNativeClient.withApiKey(
          apiKey: 'api-key',
          httpClient: transport,
        );
        addTearDown(() {
          client.close();
          transport.close();
        });
        final agent = AiAgent<void>(
          model: client.chatModel(
            model: 'fixture',
            authorityBindingId: 'account',
            mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
          ),
        );
        try {
          await agent.generate(
            ChatRequest(
              threadId: 't',
              runId: 'first',
              messages: [ChatMessage.user('hi', id: 'u')],
            ),
            ownerId: 'owner',
            context: null,
          );
          fail('Expected failure');
        } on AgentRunException catch (error) {
          final cause = error.cause as anthropic.JsonHttpException;
          expect(cause.statusCode, 503);
          expect(
            cause.requestId,
            requestId.replaceAll('fake-secret', '[REDACTED]'),
          );
          expect(cause.details, isNull);
          expect(cause.responseHeaders, isEmpty);
          expect(cause.toString(), isNot(contains('fake-secret')));
        }
      },
    );
  }
  test(
    'malformed MCP input keeps safe FormatException classification',
    () async {
      final model = anthropic.AnthropicProtocolModel(
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [server(anthropic.AnthropicMcpBeta.client20251120)],
        transport: (_, _) => Stream.fromIterable([
          f.start(),
          f.block(0, {
            'type': 'mcp_tool_use',
            'id': 'x',
            'name': 'find',
            'server_name': 'docs',
          }),
          f.delta(0, {
            'type': 'input_json_delta',
            'partial_json': '{fake-secret',
          }),
          f.stop(0),
          f.finish('end_turn'),
          f.done,
        ]),
      );
      await expectLater(
        model
            .stream(
              ModelRequest(messages: []),
              cancellation: CancellationToken(),
            )
            .toList(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'safe',
            isNot(contains('fake-secret')),
          ),
        ),
      );
    },
  );
  for (final scenario in [
    'legacy disabled',
    'legacy allowlist',
    'modern default disabled',
    'modern override disabled',
    'pinned missing',
    'modern override enabled',
  ]) {
    test('reported MCP tool obeys configured policy: $scenario', () async {
      final legacy = scenario.startsWith('legacy');
      final beta = scenario == 'pinned missing'
          ? anthropic.AnthropicMcpBeta.client20260915
          : legacy
          ? anthropic.AnthropicMcpBeta.legacy20250404
          : anthropic.AnthropicMcpBeta.client20251120;
      final serverConfig = anthropic.AnthropicMcpServer(
        name: 'docs',
        url: Uri.parse('https://example.com/mcp'),
        beta: beta,
        legacyToolConfiguration: !legacy
            ? null
            : scenario == 'legacy disabled'
            ? {'enabled': false}
            : {
                'enabled': true,
                'allowed_tools': ['other'],
              },
        toolset: legacy
            ? null
            : anthropic.AnthropicMcpToolset(
                defaultConfig: anthropic.AnthropicMcpToolConfig(
                  enabled:
                      scenario == 'modern override disabled' ||
                      scenario == 'pinned missing',
                ),
                configs: scenario == 'modern override enabled'
                    ? {'find': anthropic.AnthropicMcpToolConfig(enabled: true)}
                    : scenario == 'modern override disabled'
                    ? {'find': anthropic.AnthropicMcpToolConfig(enabled: false)}
                    : {},
                tools: scenario == 'pinned missing'
                    ? [
                        {
                          'name': 'other',
                          'input_schema': {'type': 'object'},
                        },
                      ]
                    : null,
              ),
      );
      final model = anthropic.AnthropicProtocolModel(
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [serverConfig],
        transport: (_, _) => Stream.fromIterable(
          frames([
            {
              'type': 'mcp_tool_use',
              'id': 'remote',
              'name': 'find',
              'server_name': 'docs',
              'input': <String, Object?>{},
            },
            {
              'type': 'mcp_tool_result',
              'tool_use_id': 'remote',
              'is_error': false,
              'content': 'ok',
            },
            {
              'type': 'tool_use',
              'id': 'local',
              'name': 'local',
              'input': <String, Object?>{},
            },
          ], reason: 'tool_use'),
        ),
      );
      final events = <ModelEvent>[];
      Future<void> result() async {
        await for (final event in model.stream(
          ModelRequest(
            messages: [],
            tools: [
              const ModelTool(
                name: 'local',
                description: '',
                inputSchema: {'type': 'object'},
              ),
            ],
          ),
          cancellation: CancellationToken(),
        )) {
          events.add(event);
        }
      }

      if (scenario == 'modern override enabled') {
        await result();
        expect(events.whereType<ToolCallReady>(), hasLength(1));
      } else {
        await expectLater(result(), throwsFormatException);
        expect(events.whereType<ToolCallReady>(), isEmpty);
      }
    });
  }
  test(
    'completed MCP history survives narrower tool policy in a new turn',
    () async {
      final enabled = anthropic.AnthropicMcpServer(
        name: 'docs',
        url: Uri.parse('https://example.com/mcp'),
        beta: anthropic.AnthropicMcpBeta.client20251120,
      );
      final disabled = anthropic.AnthropicMcpServer(
        name: 'docs',
        url: Uri.parse('https://example.com/mcp'),
        beta: anthropic.AnthropicMcpBeta.client20251120,
        toolset: anthropic.AnthropicMcpToolset(
          defaultConfig: anthropic.AnthropicMcpToolConfig(enabled: false),
        ),
      );
      final oldModel = anthropic.AnthropicProtocolModel(
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [enabled],
        transport: (_, _) => Stream.fromIterable(
          frames([
            {
              'type': 'mcp_tool_use',
              'id': 'old',
              'name': 'find',
              'server_name': 'docs',
              'input': <String, Object?>{},
            },
            {
              'type': 'mcp_tool_result',
              'tool_use_id': 'old',
              'is_error': false,
              'content': 'ok',
            },
          ]),
        ),
      );
      final initial = await oldModel
          .stream(
            ModelRequest(messages: [ChatMessage.user('hi', id: 'u')]),
            cancellation: CancellationToken(),
          )
          .toList();
      final assistant = ChatMessage(
        id: 'a',
        role: MessageRole.assistant,
        providerData: {
          for (final item in initial.whereType<ProviderOutput>())
            item.provider: item.items,
        },
      );
      var requests = 0;
      final newModel = anthropic.AnthropicProtocolModel(
        model: 'fixture',
        authorityBindingId: 'account',
        mcpServers: [disabled],
        transport: (_, _) async* {
          requests++;
          yield* Stream.fromIterable(frames([]));
        },
      );
      final output = await newModel
          .stream(
            ModelRequest(
              messages: [
                ChatMessage.user('hi', id: 'u'),
                assistant,
                ChatMessage.user('next', id: 'u2'),
              ],
            ),
            cancellation: CancellationToken(),
          )
          .toList();
      expect(output.whereType<ModelFinished>(), hasLength(1));
      expect(requests, 1);
    },
  );
}
