import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_dart_frog/agent_weave_dart_frog.dart';
import 'package:agent_weave_ollama/agent_weave_ollama.dart' as ollama;
import 'package:dart_frog/dart_frog.dart';

const schema = <String, Object?>{
  'type': 'object',
  'properties': {
    'count': {'type': 'integer'},
  },
  'required': ['count'],
  'additionalProperties': false,
};

Future<void> main() async {
  final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  var effects = 0;
  final failures = <String>[];
  upstream.listen((request) async {
    try {
      final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      requests++;
      if (request.uri.path != '/api/chat' ||
          body['model'] != 'fixture' ||
          body['stream'] != true) {
        throw StateError('Invalid upstream request');
      }
      final messages = body['messages'] as List;
      final user = messages.firstWhere((m) => m['role'] == 'user')['content'];
      Map<String, Object?> message;
      if (user == 'text') {
        message = {'role': 'assistant', 'content': 'Hello from Ollama'};
      } else if (user == 'schema') {
        if (body['format'] is! Map) throw StateError('Missing schema');
        message = {'role': 'assistant', 'content': '{"answer":42}'};
      } else if (user == 'approval' && messages.last['role'] != 'tool') {
        if (effects != 0 || body['tools'][0]['function']['name'] != 'gate') {
          throw StateError('Tool was not gated');
        }
        message = {
          'role': 'assistant',
          'content': '',
          'thinking': 'private-thinking',
          'secret_field': 'private-field',
          'tool_calls': [
            {
              'id': 'private-native-id',
              'function': {
                'index': 0,
                'name': 'gate',
                'arguments': {'count': 2},
              },
            },
          ],
        };
      } else if (user == 'approval') {
        final assistant = messages.firstWhere((m) => m['tool_calls'] != null);
        final tool = messages.last;
        if (effects != 1 ||
            assistant['thinking'] != 'private-thinking' ||
            assistant['secret_field'] != 'private-field' ||
            assistant['tool_calls'][0]['id'] != 'private-native-id' ||
            assistant['tool_calls'][0]['function']['index'] != 0 ||
            tool['tool_call_id'] != 'private-native-id' ||
            tool['tool_name'] != 'gate' ||
            tool['content'] != '4') {
          throw StateError('Invalid continuation');
        }
        message = {'role': 'assistant', 'content': 'Result: 4'};
      } else {
        throw StateError('Unexpected prompt');
      }
      request.response.write(
        '${jsonEncode({'model': 'fixture', 'message': message, 'done': true, 'done_reason': 'stop', 'total_duration': 123, 'private_metadata': 'private-meta', 'prompt_eval_count': 3, 'eval_count': 2})}\n',
      );
    } catch (error) {
      failures.add(error.toString());
      request.response.statusCode = 500;
      request.response.write('{"error":"fixture failed"}');
    } finally {
      await request.response.close();
    }
  });
  final client = ollama.OllamaNativeClient(
    baseUrl: 'http://127.0.0.1:${upstream.port}',
  );
  final model = client.chatModel(model: 'fixture');
  final agent = AiAgent<String>(
    model: model,
    tools: [
      Tool<int, int, String>(
        name: 'gate',
        description: 'Double',
        inputSchema: schema,
        outputSchema: const {'type': 'integer'},
        needsApproval: true,
        decode: (j) => j['count'] as int,
        encode: (n) => n,
        execute: (n, context) {
          if (context.value != 'trusted') throw StateError('context');
          effects++;
          return n * 2;
        },
      ),
    ],
  );
  final structured = AiAgent<String>(
    model: model,
    outputSchema: const {
      'type': 'object',
      'properties': {
        'answer': {'type': 'integer'},
      },
      'required': ['answer'],
      'additionalProperties': false,
    },
  );
  ({String ownerId, String context})? auth(RequestContext c) =>
      switch (c.request.headers['authorization']) {
        'Bearer alice' => (ownerId: 'alice', context: 'trusted'),
        'Bearer bob' => (ownerId: 'bob', context: 'trusted'),
        _ => null,
      };
  final chat = chatHandler<String>(agent: agent, authenticate: auth);
  final structuredChat = chatHandler<String>(
    agent: structured,
    authenticate: auth,
  );
  final generation =
      generationHandler<String, ({String prompt, String trusted}), JsonObject>(
        authenticate: auth,
        decode: (j, context) =>
            (prompt: j['prompt'] as String, trusted: context),
        task: GenerationTask(
          execute: (p, context) async {
            if (p.trusted != 'trusted') throw StateError('context');
            if (p.prompt == 'fail') {
              throw StateError('private-generation-error');
            }
            return {'answer': 42};
          },
          encodeResult: (v) => v,
        ),
      );
  final server = await serve(
    (context) {
      return switch (context.request.uri.path) {
        '/chat' => chat(context),
        '/structured' => structuredChat(context),
        '/generation' => generation(context),
        '/state' => Future.value(
          Response.json(
            body: {
              'requests': requests,
              'effects': effects,
              'failures': failures,
            },
          ),
        ),
        _ => Future.value(Response(statusCode: 404)),
      };
    },
    InternetAddress.loopbackIPv4,
    0,
  );
  stdout.writeln(jsonEncode({'port': server.port}));
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close(force: true);
    client.close();
    await upstream.close(force: true);
    exit(0);
  });
}
