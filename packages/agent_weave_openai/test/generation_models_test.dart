import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

api.OpenAIClient clientFor(
  Future<http.Response> Function(http.Request) handler,
) {
  final transport = MockClient(handler);
  final client = api.OpenAIClient(
    config: const api.OpenAIConfig(
      authProvider: api.ApiKeyProvider('fixture-key'),
      retryPolicy: api.RetryPolicy(maxRetries: 0),
    ),
    httpClient: transport,
    streamClientFactory: () => transport,
  );
  addTearDown(client.close);
  return client;
}

void main() {
  test('image task emits a TanStack-compatible base64 result', () async {
    final client = clientFor((request) async {
      expect(request.url.path, '/v1/images/generations');
      expect((jsonDecode(request.body) as Map)['prompt'], 'A red square');
      return http.Response(
        jsonEncode({
          'created': 1,
          'data': [
            {'b64_json': 'aW1hZ2U='},
          ],
        }),
        200,
      );
    });
    final events = await api
        .imageTask(client)
        .run(
          const api.ImageGenerationRequest(
            model: 'gpt-image-2',
            prompt: 'A red square',
          ),
          threadId: 't',
          runId: 'r',
        )
        .toList();
    expect(events.last.type, 'RUN_FINISHED');
    final result =
        events
                .singleWhere((e) => e.json['name'] == 'generation:result')
                .json['value']
            as Map;
    expect(result['model'], 'gpt-image-2');
    expect(result['images'], [
      {'b64Json': 'aW1hZ2U='},
    ]);
  });
  test('image task supports provider URL results', () async {
    final client = clientFor(
      (request) async => http.Response(
        jsonEncode({
          'created': 1,
          'data': [
            {'url': 'https://example.com/image.png'},
          ],
        }),
        200,
      ),
    );
    final events = await api
        .imageTask(client)
        .run(
          const api.ImageGenerationRequest(
            model: 'fixture',
            prompt: 'A square',
          ),
          threadId: 't',
          runId: 'r',
        )
        .toList();
    expect(((events[1].json['value'] as Map)['images'] as List).single, {
      'url': 'https://example.com/image.png',
    });
  });
  test(
    'speech model and task preserve binary bytes and requested audio format',
    () async {
      final client = clientFor((request) async {
        expect(request.url.path, '/v1/audio/speech');
        return http.Response.bytes(
          [0, 1, 2, 255],
          200,
          headers: {'content-type': 'application/octet-stream'},
        );
      });
      final request = api.SpeechRequest(
        model: 'fixture',
        input: 'Hi',
        voice: api.SpeechVoice.alloy,
        responseFormat: api.SpeechResponseFormat.wav,
      );
      final bytes = await api.OpenAISpeechModel(client).speak(request);
      expect(bytes, [0, 1, 2, 255]);
      final events = await api
          .speechTask(client)
          .run(request, threadId: 't', runId: 'r')
          .toList();
      final result = events[1].json['value'] as Map;
      expect(base64Decode(result['audio'] as String), bytes);
      expect(result['format'], 'wav');
    },
  );
  test(
    'transcription uses multipart uploads and normalizes text for clients',
    () async {
      final client = clientFor((request) async {
        expect(request.url.path, '/v1/audio/transcriptions');
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        expect(request.body, contains('recording.wav'));
        return http.Response(
          '{"text":"اهلا من القاهرة"}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final events = await api
          .transcriptionTask(client)
          .run(
            api.TranscriptionRequest(
              file: Uint8List.fromList([0, 1, 2]),
              filename: 'recording.wav',
              model: 'fixture',
            ),
            threadId: 't',
            runId: 'r',
          )
          .toList();
      expect((events[1].json['value'] as Map)['text'], 'اهلا من القاهرة');
    },
  );
  test('embedding adapter preserves dimensions and decoded vectors', () async {
    final client = clientFor((request) async {
      expect(request.url.path, '/v1/embeddings');
      expect((jsonDecode(request.body) as Map)['dimensions'], 2);
      return http.Response(
        jsonEncode({
          'object': 'list',
          'model': 'fixture',
          'data': [
            {
              'object': 'embedding',
              'index': 0,
              'embedding': [0.1, 0.2],
            },
          ],
          'usage': {'prompt_tokens': 1, 'total_tokens': 1},
        }),
        200,
      );
    });
    final result = await api.OpenAIEmbeddingModel(client).embed(
      api.EmbeddingRequest(
        model: 'fixture',
        input: api.EmbeddingInput.text('Hi'),
        dimensions: 2,
      ),
    );
    expect(result.data.single.embedding, [0.1, 0.2]);
  });
  test('Decisions adapter preserves typed predicates and usage', () async {
    final client = clientFor((request) async {
      expect(request.url.path, '/v1/decisions');
      return http.Response(
        jsonEncode({
          'model': 'fixture',
          'answers': [
            {'type': 'predicate', 'name': 'damaged', 'probability': 0.99},
          ],
          'usage': {
            'input_tokens': 10,
            'output_tokens': 2,
            'total_tokens': 12,
            'input_tokens_details': {
              'cached_tokens': 0,
              'cache_write_tokens': 0,
            },
            'output_tokens_details': {'reasoning_tokens': 0},
          },
        }),
        200,
      );
    });
    final result = await api.OpenAIDecisionModel(client).decide(
      api.DecisionRequest(
        model: 'fixture',
        input: const api.DecisionInput.text('It is broken'),
        questions: const [
          api.DecisionQuestion.predicate(
            name: 'damaged',
            instructions: 'Is it damaged?',
          ),
        ],
      ),
    );
    expect(
      (result.answers.single as api.PredicateDecisionAnswer).probability,
      0.99,
    );
  });
  test(
    'video adapter returns a typed job without starting an unbounded poll',
    () async {
      var requests = 0;
      final client = clientFor((request) async {
        requests++;
        expect(request.url.path, '/v1/videos');
        return http.Response(
          jsonEncode({
            'id': 'video-1',
            'model': 'sora-2',
            'status': 'queued',
            'progress': 0,
            'created_at': 0,
            'size': '720x1280',
            'seconds': '4',
          }),
          200,
        );
      });
      final result = await api.OpenAIVideoModel(client).create(
        const api.CreateVideoRequest(
          prompt: 'A moving square',
          model: 'sora-2',
        ),
      );
      expect(result.id, 'video-1');
      expect(requests, 1);
    },
  );
  test(
    'all media adapters reject a pre-cancelled token before HTTP submission',
    () async {
      final client = clientFor((_) async => fail('Must not submit'));
      final cancellation = CancellationToken()..cancel();
      await expectLater(
        api.OpenAIImageModel(client).generate(
          const api.ImageGenerationRequest(model: 'fixture', prompt: 'Hi'),
          cancellation: cancellation,
        ),
        throwsA(isA<RunCancelled>()),
      );
      expect(
        () => api.OpenAISpeechModel(client).speak(
          const api.SpeechRequest(
            model: 'fixture',
            input: 'Hi',
            voice: api.SpeechVoice.alloy,
          ),
          cancellation: cancellation,
        ),
        throwsA(isA<RunCancelled>()),
      );
      expect(
        () => api.OpenAIVideoModel(client).create(
          const api.CreateVideoRequest(prompt: 'Hi'),
          cancellation: cancellation,
        ),
        throwsA(isA<RunCancelled>()),
      );
      await expectLater(
        api.OpenAIRealtimeModel(
          client: client,
          model: 'fixture',
        ).connect(cancellation: cancellation),
        throwsA(isA<RunCancelled>()),
      );
    },
  );
  test(
    'realtime model opens an authenticated local WebSocket and sends user events',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = Completer<Map<String, Object?>>();
      final closed = Completer<void>();
      final listener = server.listen((request) async {
        expect(request.headers.value('authorization'), 'Bearer fixture-key');
        expect(request.uri.queryParameters['model'], 'fixture');
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((raw) {
          if (!received.isCompleted) {
            received.complete(
              Map<String, Object?>.from(jsonDecode(raw as String) as Map),
            );
          }
        }, onDone: closed.complete);
      });
      addTearDown(listener.cancel);
      final client = api.OpenAIClient(
        config: api.OpenAIConfig(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          authProvider: const api.ApiKeyProvider('fixture-key'),
        ),
      );
      addTearDown(client.close);
      final connection = await api.OpenAIRealtimeModel(
        client: client,
        model: 'fixture',
      ).connect();
      connection.sendUserMessage('Hello');
      expect(
        (await received.future.timeout(const Duration(seconds: 3)))['type'],
        'conversation.item.create',
      );
      await connection.close();
      await closed.future.timeout(const Duration(seconds: 3));
    },
  );
}
