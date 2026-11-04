import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:agent_weave_demo_client/agent_weave_demo_client.dart'
    as generated;
import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:serverpod_client/serverpod_client.dart' as transport;
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart' as ai;
import 'package:agent_weave_demo_server/src/ai/agent_factory.dart';
import 'package:agent_weave_serverpod/agent_weave_serverpod.dart';
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:http/http.dart' as http;
import 'package:serverpod/serverpod.dart';
// The pinned framework exposes its network-auth test hook through this extension.
// ignore: implementation_imports
import 'package:serverpod/src/server/server.dart' show ServerInternalMethods;
import 'package:test/test.dart';
import 'test_tools/serverpod_test_tools.dart';
import '../../../../../test/support/run_store_contract.dart';

String input(String thread, String run) => jsonEncode({
  'threadId': thread,
  'runId': run,
  'messages': [
    {
      'id': 'user-$run',
      'role': 'user',
      'parts': [
        {'type': 'text', 'content': 'Hello'},
      ],
    },
  ],
});

void main() {
  withServerpod(
    'AgentWeave PostgreSQL integration',
    (builder, endpoints) {
      runStoreContract(() => ServerpodRunStore(builder.build()));
      test(
        'a recreated agent resumes a PostgreSQL-backed approval without repeating its tool',
        () async {
          var calls = 0;
          AiAgent<Session> agent(ChatModel model) => AiAgent<Session>(
            model: model,
            store: ServerpodRunStore(builder.build()),
            tools: [
              Tool<int, int, Session>(
                name: 'double',
                description: 'Double',
                needsApproval: true,
                inputSchema: const {'type': 'object'},
                outputSchema: const {'type': 'integer'},
                decode: (_) => 21,
                encode: (n) => n,
                execute: (n, context) {
                  calls++;
                  return n * 2;
                },
              ),
            ],
          );
          final first = agent(
            ScriptedChatModel(
              capabilities: const ModelCapabilities(tools: true),
              steps: [
                [
                  ToolCallReady(
                    ToolCall(
                      id: 'approval-call',
                      name: 'double',
                      arguments: {},
                    ),
                  ),
                  const ModelFinished(),
                ],
              ],
            ),
          );
          final paused = await first.generate(
            ChatRequest(
              threadId: 'durable-approval',
              runId: 'pause',
              messages: [ChatMessage.user('Start', id: 'approval-user')],
            ),
            ownerId: 'approval-owner',
            context: builder.build(),
          );
          expect(paused.status, RunStatus.interrupted);
          expect(calls, 0);
          final recreated = agent(
            ScriptedChatModel(
              capabilities: const ModelCapabilities(tools: true),
              steps: [
                [const TextDelta('Result: 42'), const ModelFinished()],
              ],
            ),
          );
          final result = await recreated.generate(
            ChatRequest(
              threadId: paused.threadId,
              runId: 'resume',
              parentRunId: paused.runId,
              resume: [paused.interrupts.single.approve()],
            ),
            ownerId: 'approval-owner',
            context: builder.build(),
          );
          expect(result.text, 'Result: 42');
          expect(calls, 1);
          expect(result.messages, hasLength(4));
          await expectLater(
            recreated.generate(
              ChatRequest(
                threadId: paused.threadId,
                runId: 'resume',
                parentRunId: paused.runId,
                resume: [paused.interrupts.single.approve()],
              ),
              ownerId: 'approval-owner',
              context: builder.build(),
            ),
            throwsA(isA<RunConflict>()),
          );
          expect(calls, 1);
        },
      );

      test(
        'authenticated native endpoint streams and persists history',
        () async {
          final signedIn = builder.copyWith(
            authentication: AuthenticationOverride.authenticationInfo(
              'owner-native',
              {},
            ),
          );
          final events = await endpoints.ai
              .chat(signedIn, input('native', 'run'))
              .toList();
          expect((jsonDecode(events.last) as Map)['type'], 'RUN_FINISHED');
          final history =
              jsonDecode(await endpoints.ai.history(signedIn, 'native')) as Map;
          expect((history['messages'] as List).length, 2);
          final other = builder.copyWith(
            authentication: AuthenticationOverride.authenticationInfo(
              'other-owner',
              {},
            ),
          );
          expect(
            (jsonDecode(await endpoints.ai.history(other, 'native'))
                as Map)['messages'],
            isEmpty,
          );
        },
      );

      test('native endpoint refuses unauthenticated calls', () async {
        await expectLater(
          endpoints.ai.chat(builder, input('forbidden', 'run')).toList(),
          throwsA(isA<ServerpodUnauthenticatedException>()),
        );
      });

      test(
        'real Dart AI client uses the generated Serverpod WebSocket endpoint',
        () async {
          final server = builder.build().serverpod.server;
          server.setAuthenticationHandlerForTesting(
            (session, key) async => key == 'native-fixture-key'
                ? AuthenticationInfo(
                    'network-owner',
                    {},
                    authId: 'network-auth',
                  )
                : null,
          );
          final client = generated.Client('http://localhost:${server.port}/')
            ..authKeyProvider = const FixtureAuth();
          addTearDown(client.close);
          final chat = ai.ChatClient(
            threadId: 'real-native',
            connection: serverpodConnection(send: client.ai.chat),
          );
          addTearDown(chat.dispose);
          await chat.sendText('Hello over WebSocket');
          expect(chat.error, isNull);
          expect(
            chat.messages.last.answer,
            'AgentWeave received: Hello over WebSocket',
          );
        },
      );

      test(
        'PostgreSQL reservations reject contention and survive new store instances',
        () async {
          final first = ServerpodRunStore(builder.build());
          final second = ServerpodRunStore(builder.build());
          final attempts = await Future.wait(
            List.generate(
              8,
              (i) => (i.isEven ? first : second)
                  .begin(ownerId: 'race', threadId: 'thread', runId: 'run-$i')
                  .then(
                    (_) => true,
                    onError: (Object error) {
                      expect(error, isA<RunConflict>());
                      return false;
                    },
                  ),
            ),
          );
          expect(attempts.where((ok) => ok), hasLength(1));
          await expectLater(
            second.begin(ownerId: 'race', threadId: 'thread', runId: 'later'),
            throwsA(isA<RunConflict>()),
          );
        },
      );

      test(
        'PostgreSQL stores ordered events and enforces owner isolation',
        () async {
          final first = ServerpodRunStore(builder.build());
          await first.begin(
            ownerId: 'journal',
            threadId: 'thread',
            runId: 'run',
          );
          for (var sequence = 0; sequence < 3; sequence++) {
            await first.appendEvent(
              ownerId: 'journal',
              threadId: 'thread',
              runId: 'run',
              event: {'sequence': sequence, 'type': 'CUSTOM'},
            );
          }
          await first.save(
            ownerId: 'journal',
            threadId: 'thread',
            runId: 'run',
            state: {'runId': 'run', 'status': 'completed'},
            release: true,
          );
          final second = ServerpodRunStore(builder.build());
          expect(
            (await second.events(
              ownerId: 'journal',
              threadId: 'thread',
              runId: 'run',
              afterSequence: 0,
            )).map((e) => e['sequence']),
            [1, 2],
          );
          expect(
            await second.events(
              ownerId: 'other',
              threadId: 'thread',
              runId: 'run',
            ),
            isEmpty,
          );
          expect(
            await second.load(ownerId: 'other', threadId: 'thread'),
            isNull,
          );
          await expectLater(
            second.begin(ownerId: 'journal', threadId: 'thread', runId: 'run'),
            throwsA(isA<RunConflict>()),
          );
        },
      );

      test(
        'real HTTP SSE keeps its dedicated session alive through streaming',
        () async {
          final pod = builder.build().serverpod;
          Session? streamedSession;
          pod.webServer.addRoute(
            AgentChatRoute<Session>(
              authenticate: (session) => 'http-owner',
              createContext: (session) => session,
              createAgent: (session) {
                streamedSession = session;
                return AiAgent<Session>(
                  model: const DemoModel(),
                  store: ServerpodRunStore(session),
                );
              },
            ),
            '/test/chat',
          );
          pod.webServer.addRoute(
            AgentChatRoute<Session>(
              authenticate: (_) => null,
              createContext: (session) => session,
              createAgent: (_) =>
                  throw StateError('Must not construct an agent'),
            ),
            '/test/unauthorized',
          );
          pod.webServer.addRoute(
            AgentGenerationRoute<int, int>(
              authenticate: (_) => 'generation-owner',
              decode: (json) => json['count'] as int,
              createTask: (session) => GenerationTask<int, int>(
                store: ServerpodRunStore(session),
                execute: (n, context) async => n * 2,
                encodeResult: (n) => {'answer': n},
              ),
            ),
            '/test/generation',
          );
          await pod.webServer.start();
          final base = 'http://localhost:${pod.webServer.port}';
          final response = await http.post(
            Uri.parse('$base/test/chat'),
            headers: {'content-type': 'application/json'},
            body: input('http', 'http-run'),
          );
          expect(response.statusCode, 200);
          expect(
            response.headers['content-type'],
            startsWith('text/event-stream'),
          );
          expect(response.body, contains('RUN_FINISHED'));
          expect(response.body, contains('AgentWeave received: Hello'));
          expect(streamedSession, isNotNull);
          final saved = await ServerpodRunStore(
            builder.build(),
          ).load(ownerId: 'http-owner', threadId: 'http');
          expect(saved!['status'], 'completed');
          final unauthorized = await http.post(
            Uri.parse('$base/test/unauthorized'),
            body: '{}',
          );
          expect(unauthorized.statusCode, 401);
          final malformed = await http.post(
            Uri.parse('$base/test/chat'),
            body: 'not-json',
          );
          expect(malformed.statusCode, 400);
          final history = await http.get(
            Uri.parse('$base/test/chat?threadId=http'),
          );
          expect((jsonDecode(history.body) as Map)['messages'], hasLength(2));
          final replay = await http.get(
            Uri.parse('$base/test/chat?runId=http-run&offset=-1'),
          );
          expect(replay.body, contains('RUN_FINISHED'));
          final unknownRun = await http.get(
            Uri.parse('$base/test/chat?runId=unknown'),
          );
          expect(unknownRun.statusCode, 404);
          final wrongMethod = await http.put(Uri.parse('$base/test/chat'));
          expect(wrongMethod.statusCode, 405);
          final generation = await http.post(
            Uri.parse('$base/test/generation'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'threadId': 'media',
              'runId': 'media-run',
              'count': 21,
            }),
          );
          expect(generation.statusCode, 200);
          expect(generation.body, contains('"answer":42'));
          expect(
            (await ServerpodRunStore(
              builder.build(),
            ).load(ownerId: 'generation-owner', threadId: 'media'))!['status'],
            'completed',
          );
          final interop = await Process.run('node', [
            '../../../tool/interop/serverpod.mjs',
            base,
          ]).timeout(const Duration(seconds: 20));
          expect(
            interop.exitCode,
            0,
            reason: '${interop.stdout}\n${interop.stderr}',
          );
        },
      );
    },
    rollbackDatabase: RollbackDatabase.disabled,
    configOverride: (config) => config.copyWith(
      webServer: ServerConfig(
        port: 0,
        publicHost: 'localhost',
        publicPort: 0,
        publicScheme: 'http',
      ),
    ),
  );
}

final class FixtureAuth implements transport.ClientAuthKeyProvider {
  const FixtureAuth();
  @override
  Future<String> get authHeaderValue async => 'Bearer native-fixture-key';
}
