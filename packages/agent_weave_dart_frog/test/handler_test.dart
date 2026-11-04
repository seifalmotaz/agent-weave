import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:agent_weave_dart_frog/agent_weave_dart_frog.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

void main() {
  test(
    'HTTP chat authenticates, streams, and isolates history and replay',
    () async {
      final agent = AiAgent<void>(
        model: ScriptedChatModel(
          steps: [
            [const TextDelta('hello'), const ModelFinished()],
          ],
        ),
      );
      final handler = chatHandler<void>(
        agent: agent,
        authenticate: (context) {
          final owner = context.request.headers['authorization'];
          return owner == null ? null : (ownerId: owner, context: null);
        },
      );
      final server = await serve(handler, InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      Future<(int, String)> request(
        String method,
        String path, {
        String? owner,
        Object? body,
      }) async {
        final req = await client.openUrl(
          method,
          Uri.parse('http://127.0.0.1:${server.port}$path'),
        );
        if (owner != null) req.headers.set('authorization', owner);
        if (body != null) req.write(jsonEncode(body));
        final res = await req.close();
        return (res.statusCode, await utf8.decoder.bind(res).join());
      }

      final body = {
        'threadId': 'thread',
        'runId': 'run',
        'messages': [
          {'id': 'u1', 'role': 'user', 'content': 'secret'},
        ],
        'ownerId': 'other',
      };
      expect((await request('POST', '/', body: body)).$1, 401);
      final chat = await request('POST', '/', owner: 'alice', body: body);
      expect(chat.$1, 200);
      expect(chat.$2, contains('hello'));
      expect(
        (await request('GET', '/?threadId=thread', owner: 'alice')).$2,
        contains('secret'),
      );
      expect(
        (await request('GET', '/?threadId=thread', owner: 'other')).$2,
        isNot(contains('secret')),
      );
      expect((await request('GET', '/?runId=run', owner: 'other')).$1, 404);
      expect(
        (await request('GET', '/?runId=run', owner: 'alice')).$2,
        contains('RUN_FINISHED'),
      );
      final replay = await request(
        'GET',
        '/?runId=run&offset=1',
        owner: 'alice',
      );
      expect(replay.$2, isNot(contains('RUN_STARTED')));
      expect(replay.$2, contains('RUN_FINISHED'));
      expect(
        (await request('GET', '/?runId=run&offset=-2', owner: 'alice')).$1,
        400,
      );
      expect((await request('DELETE', '/', owner: 'alice')).$1, 405);
    },
  );

  test('generation binds parameters to authenticated context', () async {
    final handler = generationHandler<String, String, String>(
      authenticate: (_) => (ownerId: 'owner', context: 'trusted'),
      decode: (json, context) => '$context:${json['value']}',
      task: GenerationTask(
        execute: (value, _) async => value,
        encodeResult: (value) => value,
      ),
    );
    final server = await serve(handler, InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await server.close(force: true);
    });
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    request.write(
      jsonEncode({
        'threadId': 't',
        'runId': 'r',
        'ownerId': 'forged-owner',
        'context': 'forged-context',
        'forwardedProps': {'value': 3, 'context': 'forged-context'},
      }),
    );
    final response = await request.close();
    expect(response.statusCode, 200);
    final result = await utf8.decoder.bind(response).join();
    expect(result, contains('trusted:3'));
    expect(result, isNot(contains('forged')));
  });
}
