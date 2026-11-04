import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_demo_server/src/ai/openrouter_image_route.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;
import 'package:agent_weave_serverpod/agent_weave_serverpod.dart';
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';
import 'package:http/http.dart' as http;
import 'package:serverpod/serverpod.dart';
// The pinned framework exposes its network-auth test hook through this extension.
// ignore: implementation_imports
import 'package:serverpod/src/server/server.dart' show ServerInternalMethods;
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  withServerpod(
    'OpenRouter dedicated image generation over Serverpod',
    (builder, _) {
      test('persists buffered, streamed and failed native results', () async {
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requests = <Map<String, dynamic>>[];
        upstream.listen((request) async {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          requests.add(body);
          expect(request.uri.path, '/images');
          if (body['prompt'] == 'buffered' || body['prompt'] == 'fallback') {
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'created': 123,
                'data': [
                  {'b64_json': 'PHN2Zy8+', 'media_type': 'image/svg+xml'},
                  {'b64_json': 'YQ=='},
                ],
                'usage': {
                  'prompt_tokens': 1,
                  'completion_tokens': 2,
                  'total_tokens': 3,
                  'cost': 0.05,
                },
              }),
            );
          } else {
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            if (body['prompt'] == 'failure') {
              request.response.write(
                'data: {"type":"error","error":{"message":"fixture failure"}}\n\ndata: [DONE]\n\n',
              );
            } else {
              request.response.write(
                'data: {"type":"image_generation.partial_image","partial_image_index":0,"b64_json":"YQ=="}\n\n',
              );
              request.response.write(
                'data: {"data":{"type":"image_generation.completed","created":456,"b64_json":"Yg=="}}\n\n',
              );
              request.response.write(
                'data: {"type":"image_generation.completed","created":457,"b64_json":"Yw=="}\n\n',
              );
              request.response.write('data: [DONE]\n\n');
            }
          }
          await request.response.close();
        });
        final client = router.OpenRouterClient.withApiKey(
          apiKey: 'fixture-key',
          baseUrl: 'http://127.0.0.1:${upstream.port}',
        );
        final image = router.OpenRouterImageModel(client: client);
        final pod = builder.build().serverpod;
        pod.server.setAuthenticationHandlerForTesting(
          (session, key) async => key == 'image-auth'
              ? AuthenticationInfo('owner', {}, authId: 'image-fixture')
              : null,
        );
        pod.webServer.addRoute(
          createOpenRouterImageRoute(client: client, model: 'server/model'),
          '/test/owned-images',
        );
        pod.webServer.addRoute(
          AgentGenerationRoute<router.OpenRouterImageRequest, JsonObject>(
            authenticate: (_) => 'owner',
            decode: router.OpenRouterImageRequest.fromJson,
            createTask: (session) =>
                GenerationTask<router.OpenRouterImageRequest, JsonObject>(
                  store: ServerpodRunStore(session),
                  execute: (request, context) async {
                    if (request.stream != true) {
                      return (await image.generate(
                        request,
                        cancellation: context.cancellation,
                      )).raw;
                    }
                    final completions = <JsonObject>[];
                    JsonObject? fallback;
                    await for (final event in image.stream(
                      request,
                      cancellation: context.cancellation,
                    )) {
                      if (event is router.OpenRouterImagePartial) {
                        context.reportProgress(
                          0,
                          message: 'Partial image received',
                        );
                      } else if (event is router.OpenRouterImageCompleted) {
                        completions.add(event.raw);
                      } else if (event is router.OpenRouterImageBuffered) {
                        fallback = event.response.raw;
                      } else if (event is router.OpenRouterImageError) {
                        throw StateError('Image generation failed.');
                      }
                    }
                    if (fallback != null) return fallback;
                    if (completions.isEmpty) {
                      throw StateError('Missing image result.');
                    }
                    return {'events': completions};
                  },
                  encodeResult: (result) => result,
                ),
          ),
          '/test/image-generation',
        );
        try {
          await pod.webServer.start();
          final endpoint = Uri.parse(
            'http://localhost:${pod.webServer.port}/test/image-generation',
          );
          Future<http.Response> run(String mode) => http.post(
            endpoint,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'threadId': 'image-$mode',
              'runId': 'run-$mode',
              'forwardedProps': {
                'model': 'fixture/model',
                'prompt': mode,
                'n': 2,
                'stream': mode != 'buffered',
              },
            }),
          );
          final buffered = await run('buffered');
          final streamed = await run('streamed');
          final failed = await run('failure');
          final fallback = await run('fallback');
          for (final response in [buffered, streamed, failed, fallback]) {
            expect(response.statusCode, 200);
            expect(
              response.headers['content-type'],
              startsWith('text/event-stream'),
            );
          }
          expect(buffered.body, contains('generation:result'));
          expect(buffered.body, contains('image/svg+xml'));
          expect(streamed.body, contains('Partial image received'));
          expect(streamed.body, contains('image_generation.completed'));
          expect(failed.body, contains('RUN_ERROR'));
          expect(failed.body, isNot(contains('generation:result')));
          expect(failed.body, isNot(contains('RUN_FINISHED')));
          expect(requests, hasLength(4));
          expect(requests.map((body) => body['stream']), [
            false,
            true,
            true,
            true,
          ]);
          final fallbackEvents = fallback.body
              .split('\n')
              .where((line) => line.startsWith('data: '))
              .map((line) => jsonDecode(line.substring(6)) as Map)
              .toList();
          final fallbackResult =
              fallbackEvents.singleWhere(
                    (event) => event['name'] == 'generation:result',
                  )['value']
                  as Map;
          expect(fallbackResult['data'], [
            {'b64_json': 'PHN2Zy8+', 'media_type': 'image/svg+xml'},
            {'b64_json': 'YQ=='},
          ]);
          expect(
            requests.where((body) => body['prompt'] == 'fallback'),
            hasLength(1),
          );
          final store = ServerpodRunStore(builder.build());
          final saved = (await store.load(
            ownerId: 'owner',
            threadId: 'image-buffered',
          ))!;
          final result = saved['result'] as Map;
          expect(saved['status'], 'completed');
          expect(result['created'], 123);
          expect(result['data'], hasLength(2));
          expect(result.containsKey('id'), isFalse);
          expect(result.containsKey('model'), isFalse);
          expect(jsonEncode(saved), isNot(contains('fixture-key')));
          expect(
            await store.load(ownerId: 'other', threadId: 'image-buffered'),
            isNull,
          );
          expect(
            await store.events(
              ownerId: 'other',
              threadId: 'image-buffered',
              runId: 'run-buffered',
            ),
            isEmpty,
          );
          final journal = await store.events(
            ownerId: 'owner',
            threadId: 'image-buffered',
            runId: 'run-buffered',
          );
          expect(journal.map((event) => event['type']), [
            'RUN_STARTED',
            'CUSTOM',
            'RUN_FINISHED',
          ]);
          expect((journal[1]['value'] as Map)['data'], result['data']);
          final streamState = (await store.load(
            ownerId: 'owner',
            threadId: 'image-streamed',
          ))!;
          expect(streamState['status'], 'completed');
          expect(
            (streamState['result'] as Map)['events'],
            [
              {
                'type': 'image_generation.completed',
                'created': 456,
                'b64_json': 'Yg==',
              },
              {
                'type': 'image_generation.completed',
                'created': 457,
                'b64_json': 'Yw==',
              },
            ],
          );
          final streamJournal = await store.events(
            ownerId: 'owner',
            threadId: 'image-streamed',
            runId: 'run-streamed',
          );
          expect(streamJournal.map((event) => event['type']), [
            'RUN_STARTED',
            'CUSTOM',
            'CUSTOM',
            'RUN_FINISHED',
          ]);
          expect(streamJournal[1]['name'], 'generation:progress');
          final js = await Process.run(
            'node',
            [
              '--input-type=module',
              '-e',
              r"""
import assert from 'node:assert/strict';
import { GenerationClient, fetchServerSentEvents } from '@tanstack/ai-client';
const generation = new GenerationClient({threadId: 'image-js', connection: fetchServerSentEvents(process.argv[1])});
try {
  await generation.generate({model: 'fixture/model', prompt: 'fallback', stream: true, n: 2});
  assert.equal(generation.getError(), undefined);
  assert.deepEqual(generation.getResult().data, [
    {b64_json: 'PHN2Zy8+', media_type: 'image/svg+xml'}, {b64_json: 'YQ=='}
  ]);
} finally { generation.dispose(); }
""",
              endpoint.toString(),
            ],
            workingDirectory: '../../../tool/interop',
          ).timeout(const Duration(seconds: 20));
          expect(js.exitCode, 0, reason: '${js.stdout}\n${js.stderr}');
          expect(
            requests.where((body) => body['prompt'] == 'fallback'),
            hasLength(2),
          );
          expect(
            (await store.load(
              ownerId: 'owner',
              threadId: 'image-js',
            ))!['status'],
            'completed',
          );
          final failedState = (await store.load(
            ownerId: 'owner',
            threadId: 'image-failure',
          ))!;
          expect(failedState['status'], 'failed');
          expect(failedState['result'], isNull);
          final failedJournal = await store.events(
            ownerId: 'owner',
            threadId: 'image-failure',
            runId: 'run-failure',
          );
          expect(failedJournal.map((event) => event['type']), [
            'RUN_STARTED',
            'RUN_ERROR',
          ]);
          final boundedEndpoint = endpoint.replace(path: '/test/owned-images');
          final boundedBody = jsonEncode({
            'threadId': 'bounded-images',
            'runId': 'bounded-run',
            'forwardedProps': {
              'prompt': 'buffered',
              'model': 'untrusted/model',
              'n': 10,
              'stream': true,
              'provider': {
                'only': ['untrusted'],
              },
              'ownerId': 'untrusted',
            },
          });
          final before = requests.length;
          expect(
            (await http.post(boundedEndpoint, body: boundedBody)).statusCode,
            401,
          );
          expect(requests, hasLength(before));
          final owned = await http.post(
            boundedEndpoint,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer image-auth',
            },
            body: boundedBody,
          );
          expect(owned.statusCode, 200);
          expect(owned.body, contains('generation:result'));
          expect(requests, hasLength(before + 1));
          expect(requests.last, {
            'model': 'server/model',
            'prompt': 'buffered',
            'n': 1,
          });
          expect(
            (await store.load(
              ownerId: 'owner',
              threadId: 'bounded-images',
            ))!['status'],
            'completed',
          );
          expect(
            await store.load(ownerId: 'untrusted', threadId: 'bounded-images'),
            isNull,
          );
        } finally {
          client.close();
          await upstream.close(force: true);
        }
      });
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
