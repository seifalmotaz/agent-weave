import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;
import 'package:test/test.dart';

void main() {
  test(
    'managed profiles freeze configuration, merge include and reject callbacks',
    () async {
      final hosted = [
        openai.OpenAIHostedTool.fromJson({'type': 'web_search'}),
      ];
      final options = <String, Object?>{
        'temperature': 0.2,
        'include': <String>['web_search_call.action.sources'],
      };
      JsonObject? sent;
      final model = openai.ResponsesProtocolModel.native(
        model: 'm',
        authorityBindingId: 'account-a',
        hostedTools: hosted,
        options: options,
        toolChoice: 'auto',
        transport: (body, _) async* {
          sent = body;
          yield {
            'type': 'response.completed',
            'response': {'status': 'completed', 'output': <Object?>[]},
          };
        },
      );
      final contract = model.continuationContract;
      hosted.clear();
      (options['include'] as List).clear();
      options['temperature'] = 0.9;
      expect(model.continuationContract, contract);
      await model
          .stream(ModelRequest(messages: []), cancellation: CancellationToken())
          .toList();
      expect(sent!['temperature'], 0.2);
      expect(sent!['tool_choice'], 'auto');
      expect(
        sent!['include'],
        containsAll([
          'web_search_call.action.sources',
          'reasoning.encrypted_content',
        ]),
      );
      expect((sent!['tools'] as List), hasLength(1));
      expect(
        () => openai.ResponsesProtocolModel.native(
          model: 'm',
          hostedTools: [
            openai.OpenAIHostedTool.fromJson({'type': 'web_search'}),
          ],
          transport: (_, _) => const Stream.empty(),
        ),
        throwsArgumentError,
      );
      expect(
        () => openai.ResponsesProtocolModel.native(
          model: 'm',
          authorityBindingId: 'account-a',
          hostedTools: [
            openai.OpenAIHostedTool.fromJson({'type': 'web_search'}),
          ],
          configure: (body) => body,
          transport: (_, _) => const Stream.empty(),
        ),
        throwsArgumentError,
      );
      for (final key in [
        'model',
        'tools',
        'tool_choice',
        'store',
        'background',
        'conversation',
        'previous_response_id',
        'authorization',
      ]) {
        expect(
          () => openai.ResponsesProtocolModel.native(
            model: 'm',
            options: {key: 'x'},
            transport: (_, _) => const Stream.empty(),
          ),
          throwsArgumentError,
          reason: key,
        );
      }
    },
  );
  test(
    'typed transport roundtrip protection survives caller list mutation',
    () async {
      final hosted = [
        openai.OpenAIHostedTool.fromJson({
          'type': 'web_search',
          'future_field': {'x': 1},
        }),
      ];
      var sent = false;
      final model = openai.ResponsesProtocolModel(
        model: 'm',
        authorityBindingId: 'account-a',
        hostedTools: hosted,
        transport: (_, _) {
          sent = true;
          return const Stream.empty();
        },
      );
      hosted.clear();
      await expectLater(
        model
            .stream(
              ModelRequest(messages: []),
              cancellation: CancellationToken(),
            )
            .toList(),
        throwsUnsupportedError,
      );
      expect(sent, false);
    },
  );
  test('authority, tool choice and frozen options affect exact profile', () {
    openai.ResponsesProtocolModel model(
      String authority,
      Object? choice,
      JsonObject options,
    ) => openai.ResponsesProtocolModel.native(
      model: 'm',
      authorityBindingId: authority,
      hostedTools: [
        openai.OpenAIHostedTool.fromJson({'type': 'web_search'}),
      ],
      toolChoice: choice,
      options: options,
      transport: (_, _) => const Stream.empty(),
    );
    final original = model('a', 'auto', {
      'temperature': 0.2,
    }).continuationContract;
    expect(
      jsonEquals(
        original,
        model('b', 'auto', {'temperature': 0.2}).continuationContract,
      ),
      false,
    );
    expect(
      jsonEquals(
        original,
        model('a', 'none', {'temperature': 0.2}).continuationContract,
      ),
      false,
    );
    expect(
      jsonEquals(
        original,
        model('a', 'auto', {'temperature': 0.3}).continuationContract,
      ),
      false,
    );
  });
  test(
    'text options merge with runtime schema and tool choice is JSON snapshotted',
    () async {
      final text = <String, Object?>{
        'verbosity': 'low',
        'future': {'v': 1},
      };
      final choice = <String, Object?>{
        'type': 'allowed_tools',
        'mode': 'auto',
        'tools': [
          {'type': 'web_search'},
        ],
      };
      JsonObject? sent;
      final model = openai.ResponsesProtocolModel.native(
        model: 'm',
        authorityBindingId: 'a',
        hostedTools: [
          openai.OpenAIHostedTool.fromJson({'type': 'web_search'}),
        ],
        options: {'text': text},
        toolChoice: choice,
        transport: (body, _) async* {
          sent = body;
          yield {
            'type': 'response.completed',
            'response': {'status': 'completed', 'output': <Object?>[]},
          };
        },
      );
      text['verbosity'] = 'high';
      (choice['tools'] as List).clear();
      await model
          .stream(
            ModelRequest(messages: [], outputSchema: const {'type': 'object'}),
            cancellation: CancellationToken(),
          )
          .toList();
      expect((sent!['text'] as Map)['verbosity'], 'low');
      expect(((sent!['text'] as Map)['format'] as Map)['type'], 'json_schema');
      expect(((sent!['tool_choice'] as Map)['tools'] as List), hasLength(1));
      expect(
        () => openai.ResponsesProtocolModel.native(
          model: 'm',
          options: {
            'text': {
              'format': {'type': 'text'},
            },
          },
          transport: (_, _) => const Stream.empty(),
        ),
        throwsArgumentError,
      );
      for (final bad in [true, <Object?>[], DateTime(2020)]) {
        expect(
          () => openai.ResponsesProtocolModel.native(
            model: 'm',
            toolChoice: bad,
            transport: (_, _) => const Stream.empty(),
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => openai.ResponsesProtocolModel.native(
          model: 'm',
          toolChoice: {'type': DateTime(2020)},
          transport: (_, _) => const Stream.empty(),
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'changing provider authority blocks approved local effect before dispatch',
    () async {
      var effects = 0, requests = 0;
      final store = MemoryRunStore();
      final local = Tool<JsonObject, int, void>(
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
      final item = <String, Object?>{
        'type': 'function_call',
        'id': 'item',
        'call_id': 'local-call',
        'name': 'local',
        'arguments': '{}',
        'status': 'completed',
      };
      AiAgent<void> agent(String authority, {bool strict = false}) =>
          AiAgent<void>(
            store: store,
            tools: [local],
            model: openai.ResponsesProtocolModel.native(
              model: 'm',
              authorityBindingId: authority,
              functionToolOptions: {
                'local': {'strict': strict},
              },
              mcpTools: [
                openai.OpenAIMcpTool.fromJson({
                  'type': 'mcp',
                  'server_label': 'docs',
                  'server_url': 'https://example.com/mcp',
                  'require_approval': 'always',
                }),
              ],
              transport: (body, _) async* {
                requests++;
                yield {
                  'type': 'response.completed',
                  'response': {
                    'status': 'completed',
                    'output': [item],
                  },
                };
              },
            ),
          );
      final paused = await agent('account-a').generate(
        ChatRequest(
          threadId: 't',
          runId: 'first',
          messages: [ChatMessage.user('hi', id: 'u')],
        ),
        ownerId: 'owner',
        context: null,
      );
      await expectLater(
        agent('account-b').generate(
          ChatRequest(
            threadId: 't',
            runId: 'second',
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
      await expectLater(
        agent('account-a', strict: true).generate(
          ChatRequest(
            threadId: 't',
            runId: 'changed-options',
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
    },
  );
  test('managed function options are frozen, serialized, and bound', () async {
    final mutable = <String, JsonObject>{
      'lookup': {
        'strict': true,
        'defer_loading': true,
        'allowed_callers': <String>['direct'],
        'async': false,
      },
    };
    JsonObject? sent;
    final model = openai.ResponsesProtocolModel.native(
      model: 'm',
      authorityBindingId: 'a',
      hostedTools: [
        openai.OpenAIHostedTool.fromJson({'type': 'web_search'}),
      ],
      functionToolOptions: mutable,
      transport: (body, _) async* {
        sent = body;
        yield {
          'type': 'response.completed',
          'response': {'status': 'completed', 'output': <Object?>[]},
        };
      },
    );
    final profile = model.continuationContract;
    (mutable['lookup']!['allowed_callers'] as List).clear();
    mutable['lookup']!['strict'] = false;
    await model
        .stream(
          ModelRequest(
            messages: [],
            tools: [
              const ModelTool(
                name: 'lookup',
                description: '',
                inputSchema: {'type': 'object'},
              ),
            ],
          ),
          cancellation: CancellationToken(),
        )
        .toList();
    final tool = (sent!['tools'] as List).last as Map;
    expect(tool['strict'], true);
    expect(tool['defer_loading'], true);
    expect(tool['async'], false);
    expect(tool['allowed_callers'], ['direct']);
    expect(model.continuationContract, profile);
    final different = openai.ResponsesProtocolModel.native(
      model: 'm',
      authorityBindingId: 'a',
      hostedTools: [
        openai.OpenAIHostedTool.fromJson({'type': 'web_search'}),
      ],
      functionToolOptions: {
        'lookup': {'strict': false},
      },
      transport: (_, _) => const Stream.empty(),
    );
    expect(jsonEquals(profile, different.continuationContract), false);
  });
  test(
    'invalid and unregistered function options fail before transport',
    () async {
      for (final options in <JsonObject>[
        {'name': 'evil'},
        {'parameters': {}},
        {'strict': 'true'},
        {'defer_loading': 2},
        {
          'allowed_callers': ['programmatic'],
        },
      ]) {
        expect(
          () => openai.ResponsesProtocolModel.native(
            model: 'm',
            functionToolOptions: {'lookup': options},
            transport: (_, _) => const Stream.empty(),
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => openai.ResponsesProtocolModel.native(
          model: 'm',
          functionToolOptions: {
            'lookup': {'async': true},
          },
          transport: (_, _) => const Stream.empty(),
        ),
        throwsUnsupportedError,
      );
      var sent = false;
      final model = openai.ResponsesProtocolModel.native(
        model: 'm',
        functionToolOptions: {
          'missing': {'strict': true},
        },
        transport: (_, _) {
          sent = true;
          return const Stream.empty();
        },
      );
      await expectLater(
        model
            .stream(
              ModelRequest(messages: []),
              cancellation: CancellationToken(),
            )
            .toList(),
        throwsArgumentError,
      );
      expect(sent, false);
    },
  );
}
