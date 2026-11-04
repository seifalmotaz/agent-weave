// Loopback consumer exercise: dart --enable-asserts run examples/review_cases/dart_frog.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:agent_weave_dart_frog/agent_weave_dart_frog.dart';
import 'package:dart_frog/dart_frog.dart';

Future<void> main() async {
  var executions = 0;
  final agent = AiAgent<String>(
    model: ScriptedChatModel(
      capabilities: const ModelCapabilities(tools: true),
      steps: [
        [
          ToolCallReady(
            ToolCall(id: 'call', name: 'double', arguments: {'value': 21}),
          ),
          const ModelFinished(),
        ],
        [const TextDelta('42'), const ModelFinished()],
      ],
    ),
    tools: [
      Tool<int, int, String>(
        name: 'double',
        description: 'Double',
        inputSchema: const {
          'type': 'object',
          'properties': {
            'value': {'type': 'integer'},
          },
          'required': ['value'],
        },
        outputSchema: const {'type': 'integer'},
        needsApproval: true,
        decode: (v) => v['value'] as int,
        encode: (v) => v,
        execute: (v, context) {
          assert(context.value == 'trusted');
          executions++;
          return v * 2;
        },
      ),
    ],
  );
  ({String ownerId, String context})? auth(RequestContext c) =>
      switch (c.request.headers['authorization']) {
        'Bearer alice' => (ownerId: 'alice', context: 'trusted'),
        'Bearer bob' => (ownerId: 'bob', context: 'trusted'),
        _ => null,
      };
  final chat = chatHandler<String>(agent: agent, authenticate: auth);
  final generation =
      generationHandler<String, ({int number, String trusted}), int>(
        authenticate: auth,
        decode: (json, trustedContext) {
          return (number: json['number'] as int, trusted: trustedContext);
        },
        task: GenerationTask(
          execute: (n, context) async {
            assert(n.trusted == 'trusted');
            return n.number * 2;
          },
          encodeResult: (n) => n,
        ),
      );
  final cancelModel = CancelModel();
  final cancelChat = chatHandler<String>(
    agent: AiAgent(model: cancelModel),
    authenticate: auth,
  );
  final server = await serve(
    (c) => c.request.uri.path == '/generation'
        ? generation(c)
        : c.request.uri.path == '/cancel'
        ? cancelChat(c)
        : chat(c),
    InternetAddress.loopbackIPv4,
    0,
  );
  final client = HttpClient();
  Future<(int, String)> request(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final req = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (token != null) req.headers.set('authorization', 'Bearer $token');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close();
    return (response.statusCode, await utf8.decoder.bind(response).join());
  }

  try {
    assert((await request('GET', '/?threadId=t')).$1 == 401);
    assert((await request('DELETE', '/', token: 'alice')).$1 == 405);
    assert(
      (await request(
            'POST',
            '/',
            token: 'alice',
            body: {'threadId': 't'},
          )).$1 ==
          400,
    );
    final first = await request(
      'POST',
      '/',
      token: 'alice',
      body: {
        'threadId': 't',
        'runId': 'r1',
        'ownerId': 'bob',
        'messages': [
          {'id': 'u', 'role': 'user', 'content': 'double'},
        ],
      },
    );
    assert(first.$1 == 200 && executions == 0);
    final events = first.$2
        .split('\n')
        .where((s) => s.startsWith('data: '))
        .map((s) => jsonDecode(s.substring(6)) as Map)
        .toList();
    final interrupted = events.firstWhere((e) => e['type'] == 'RUN_FINISHED');
    final interruptId =
        ((interrupted['outcome'] as Map)['interrupts'] as List).single['id'];
    final other = await request('GET', '/?threadId=t', token: 'bob');
    assert(other.$1 == 200 && !other.$2.contains('double'));
    final resumed = await request(
      'POST',
      '/',
      token: 'alice',
      body: {
        'threadId': 't',
        'runId': 'r2',
        'parentRunId': 'r1',
        'messages': <Object>[],
        'resume': [
          {'interruptId': interruptId, 'status': 'resolved', 'payload': true},
        ],
      },
    );
    assert(resumed.$1 == 200 && resumed.$2.contains('42') && executions == 1);
    final history = await request('GET', '/?threadId=t', token: 'alice');
    assert(history.$1 == 200 && history.$2.contains('42'));
    final replay = await request(
      'GET',
      '/?threadId=t&runId=r2&offset=0',
      token: 'alice',
    );
    final replayEvents = replay.$2
        .split('\n')
        .where((s) => s.startsWith('data: '))
        .map((s) => jsonDecode(s.substring(6)) as Map)
        .toList();
    assert(
      replay.$1 == 200 &&
          replayEvents.isNotEmpty &&
          replayEvents.every((e) => (e['sequence'] as int) > 0),
    );
    assert(
      (await request(
            'GET',
            '/?threadId=t&runId=r2&offset=bad',
            token: 'alice',
          )).$1 ==
          400,
    );
    final foreignReplay = await request(
      'GET',
      '/?threadId=t&runId=r2',
      token: 'bob',
    );
    assert(!foreignReplay.$2.contains('42'));
    final gen = await request(
      'POST',
      '/generation',
      token: 'alice',
      body: {
        'threadId': 'g',
        'runId': 'g1',
        'forwardedProps': {'number': 21},
      },
    );
    assert(gen.$1 == 200 && gen.$2.contains('42'));
    assert(
      (await request(
            'POST',
            '/generation',
            token: 'alice',
            body: {
              'threadId': 'g',
              'runId': 'g2',
              'forwardedProps': <String, Object>{},
            },
          )).$1 ==
          400,
    );
    final cancelRequest = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/cancel'),
    );
    cancelRequest.headers.set('authorization', 'Bearer alice');
    cancelRequest.write(
      jsonEncode({
        'threadId': 'cancel',
        'runId': 'cancel',
        'messages': [
          {'id': 'u', 'role': 'user', 'content': 'hi'},
        ],
      }),
    );
    final cancelResponse = await cancelRequest.close();
    final subscription = cancelResponse.listen((_) {});
    await cancelModel.started.future.timeout(const Duration(seconds: 3));
    await subscription.cancel();
    await cancelModel.stopped.future.timeout(const Duration(seconds: 5));
    print('PASS disconnect cancellation');
    print(
      'PASS auth, methods, payload, owner isolation, stored approval resume, history and generation over HTTP',
    );
  } finally {
    client.close(force: true);
    await server.close(force: true);
  }
}

final class CancelModel implements ChatModel {
  final started = Completer<void>();
  final stopped = Completer<void>();
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    try {
      started.complete();
      while (true) {
        cancellation.throwIfCancelled();
        yield const TextDelta('x');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      stopped.complete();
    }
  }
}
