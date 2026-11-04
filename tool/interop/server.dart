import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

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
  final nativeAgent = AiAgent<void>(
    model: const NativeInteropModel(),
    tools: [NativeInteropTool()],
  );
  var computerEffects = 0;
  var ordinaryEffects = 0;
  final mixedAgent = AiAgent<void>(
    model: const MixedInteropModel(),
    tools: [
      anthropic.AnthropicComputerTool<void>(
        environmentId: 'private-mixed-environment',
        execute: (call, context) {
          computerEffects++;
          return anthropic.AnthropicComputerResult.error('fixture failure');
        },
      ),
      Tool<int, int, void>(
        name: 'double',
        description: 'Double',
        inputSchema: inputSchema,
        outputSchema: const {'type': 'integer'},
        decode: (json) => json['count'] as int,
        encode: (value) => value,
        execute: (n, context) {
          ordinaryEffects++;
          return n * 2;
        },
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
      if (request.method == 'GET' && request.uri.path == '/mixed-state') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'computer': computerEffects,
            'ordinary': ordinaryEffects,
          }),
        );
        continue;
      }
      if (request.method == 'GET' &&
          {
            '/history',
            '/structured-history',
            '/native-history',
            '/mixed-history',
          }.contains(request.uri.path)) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            chatHydration(
              await (request.uri.path == '/native-history'
                      ? nativeAgent
                      : request.uri.path == '/mixed-history'
                      ? mixedAgent
                      : request.uri.path == '/structured-history'
                      ? structuredAgent
                      : agent)
                  .store
                  .load(
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
        source =
            (request.uri.path == '/mixed'
                    ? mixedAgent
                    : request.uri.path == '/native'
                    ? nativeAgent
                    : request.uri.path == '/structured'
                    ? structuredAgent
                    : agent)
                .run(
                  ChatRequest.fromJson(json),
                  ownerId: 'test',
                  context: null,
                );
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
    if (last.text == 'pause' || last.text == 'structured-pause') {
      yield const TextDelta('Working');
      yield ProviderOutput(
        provider: 'fixture.pause',
        items: [
          {'opaque': 'PRIVATE-PAUSE'},
        ],
      );
      yield const ModelFinished.continuation('provider_pause');
      return;
    }
    if (last.providerData.containsKey('fixture.pause')) {
      yield TextDelta(
        request.outputSchema == null ? 'Hello from Dart' : '{"answer":42}',
      );
      yield const ModelFinished();
      return;
    }
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

final class NativeInteropTool implements AgentTool<void> {
  @override
  final definition = NativeModelTool(
    name: 'nativeGate',
    description: 'Native fixture',
    inputSchema: inputSchema,
    provider: 'fixture.native',
    definition: {'type': 'fixture-computer'},
    bindingId: 'private-native-environment',
  );
  @override
  JsonObject? get outputSchema => null;
  @override
  bool get needsApproval => false;
  @override
  bool get clientExecuted => false;
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<void> context) async {
    if (!context.approved) throw StateError('Approval required');
    return 'captured';
  }
}

final class NativeInteropModel implements ChatModel {
  const NativeInteropModel();
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(tools: true);
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    if (request.messages.last.role == MessageRole.tool) {
      yield const TextDelta('Computer completed');
      yield const ModelFinished();
    } else {
      yield NativeToolCallReady(
        NativeToolCall(
          id: 'native-call',
          name: 'nativeGate',
          arguments: {'count': 2},
          provider: 'fixture.native',
          requiresApproval: true,
        ),
      );
      yield ProviderOutput(
        provider: 'fixture.native',
        items: [
          {'private': 'private-native-replay'},
        ],
      );
      yield const ModelFinished('tool_calls');
    }
  }
}

final class MixedInteropModel implements ChatModel {
  const MixedInteropModel();
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(tools: true);
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    if (request.messages.last.role == MessageRole.tool) {
      final results = request.messages
          .where((m) => m.role == MessageRole.tool)
          .toList();
      if (results.map((m) => m.toolCallId).join(',') !=
              'computer-1,regular,computer-2' ||
          !results[0].text.contains('fixture failure') ||
          !results[1].text.contains('Not executed') ||
          !results[2].text.contains('Not executed')) {
        throw StateError(
          'Mixed result IDs, order or halt incorrect: ${results.map((m) => m.toJson()).toList()}',
        );
      }
      yield const TextDelta('Mixed completed');
      yield const ModelFinished();
      return;
    }
    for (final (id, name) in [
      ('computer-1', 'screenshot'),
      ('regular', 'double'),
      ('computer-2', 'screenshot'),
    ]) {
      if (name == 'double') {
        yield ToolCallReady(
          ToolCall(id: id, name: name, arguments: {'count': 2}),
        );
      } else {
        yield NativeToolCallReady(
          NativeToolCall(
            id: id,
            name: 'computer',
            provider: 'anthropic.messages',
            arguments: {
              'type': 'tool_use',
              'id': id,
              'name': name,
              'toolset_name': 'computer',
              'input': {},
            },
          ),
        );
      }
    }
    yield ProviderOutput(
      provider: 'anthropic.messages',
      items: [
        {'private': 'private-mixed-replay'},
      ],
    );
    yield const ModelFinished('tool_calls');
  }
}
