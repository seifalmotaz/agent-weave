import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';

const inputSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'count': {'type': 'integer'},
  },
  'required': ['count'],
  'additionalProperties': false,
};

Future<void> main() async {
  final agent = AiAgent<void>(
    model: const InteropModel(),
    tools: [
      const ClientTool<void>(
        definition: ModelTool(
          name: 'clientDouble',
          description: 'Double on the client',
          inputSchema: inputSchema,
        ),
        outputSchema: {'type': 'integer'},
      ),
      for (final name in ['double', 'gate'])
        Tool<int, int, void>(
          name: name,
          description: 'Double',
          inputSchema: inputSchema,
          outputSchema: const {'type': 'integer'},
          needsApproval: name == 'gate',
          decode: (json) => json['count'] as int,
          encode: (value) => value,
          execute: (n, context) => n * 2,
        ),
    ],
  );
  final structuredAgent = AiAgent<void>(
    model: const InteropModel(),
    outputSchema: const {
      'type': 'object',
      'properties': {
        'answer': {'type': 'integer'},
      },
      'required': ['answer'],
      'additionalProperties': false,
    },
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  stdout.writeln(jsonEncode({'port': server.port}));
  await for (final request in server) {
    if (request.uri.path == '/shutdown') {
      request.response.statusCode = 204;
      await request.response.close();
      await server.close(force: true);
      break;
    }
    try {
      if (request.method == 'GET' && request.uri.path == '/history') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            chatHydration(
              await agent.store.load(
                ownerId: 'test',
                threadId: request.uri.queryParameters['threadId']!,
              ),
            ),
          ),
        );
        continue;
      }
      final json = Map<String, Object?>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
      );
      final Stream<AgentEvent> source;
      if (request.uri.path == '/generation') {
        source =
            GenerationTask<JsonObject, JsonObject>(
              execute: (input, context) async {
                context.reportProgress(0.5);
                return {'answer': 42};
              },
              encodeResult: (result) => result,
            ).run(
              json,
              threadId: json['threadId'] as String,
              runId: json['runId'] as String,
            );
      } else {
        source = (request.uri.path == '/structured' ? structuredAgent : agent)
            .run(ChatRequest.fromJson(json), ownerId: 'test', context: null);
      }
      await for (final event in source) {
        request.response.write(event.toSse());
        await request.response.flush();
      }
    } catch (_) {
      request.response.write(
        AgentEvent({'type': 'RUN_ERROR', 'message': 'Interop failure'}).toSse(),
      );
    } finally {
      await request.response.close();
    }
  }
}

final class InteropModel implements ChatModel {
  const InteropModel();
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(
    tools: true,
    structuredOutput: true,
    fileInput: true,
    imageInput: true,
    audioInput: true,
    videoInput: true,
  );
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    final last = request.messages.last;
    if (last.content.any((part) => part is! TextPart)) {
      yield TextDelta(
        jsonEncode([
          for (final part in last.content)
            switch (part) {
              DocumentPart document => document.sourceJson,
              FilePart(:final fileId) => {'type': 'file', 'value': fileId},
              ImagePart(:final url) ||
              VideoPart(:final url) => {'type': 'url', 'value': url},
              AudioPart(:final data) => {'type': 'data', 'value': data},
              TextPart() => {'type': 'text'},
            },
        ]),
      );
    } else if (last.text == 'structured') {
      yield const TextDelta('{"answer":42}');
    } else if (last.role == MessageRole.user &&
        ['tool', 'approval', 'client'].contains(last.text)) {
      yield ToolCallReady(
        ToolCall(
          id: 'call',
          name: switch (last.text) {
            'approval' => 'gate',
            'client' => 'clientDouble',
            _ => 'double',
          },
          arguments: {'count': 2},
        ),
      );
    } else {
      if (last.text == 'reasoning') {
        yield const ReasoningDelta('Considering the request.');
      }
      yield TextDelta(
        last.role == MessageRole.tool
            ? 'Result: ${last.text}'
            : 'Hello from Dart',
      );
    }
    yield const ModelFinished();
  }
}
