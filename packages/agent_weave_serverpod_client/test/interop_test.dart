import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_serverpod_client/agent_weave_serverpod_client.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart' as client;
import 'package:tanstack_ai_dart/platform.dart' as platform;
import 'package:test/test.dart';

const inputSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'count': {'type': 'integer'},
  },
  'required': ['count'],
  'additionalProperties': false,
};
const outputSchema = <String, Object?>{'type': 'integer'};

final class TestModel implements ChatModel {
  final bool withTool;
  TestModel({this.withTool = false});
  @override
  ModelCapabilities get capabilities => const ModelCapabilities(tools: true);
  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    if (withTool && request.messages.last.role == MessageRole.user) {
      yield ToolCallReady(
        ToolCall(id: 'call', name: 'double', arguments: {'count': 2}),
      );
    } else {
      yield const TextDelta('Hello from Dart');
    }
    yield const ModelFinished();
  }
}

client.ConnectionAdapter connect(AiAgent<void> agent) => serverpodConnection(
  send: (raw) => agent
      .run(
        ChatRequest.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map)),
        ownerId: 'owner',
        context: null,
      )
      .map((event) => jsonEncode(event.json)),
);

void main() {
  test(
    'real Dart ChatClient reconstructs a response and a second turn',
    () async {
      final agent = AiAgent<void>(model: TestModel());
      final chat = client.ChatClient(
        connection: connect(agent),
        threadId: 'thread',
      );
      addTearDown(chat.dispose);
      await chat.sendText('Hello');
      expect(chat.error, isNull);
      expect(chat.messages.last.answer, 'Hello from Dart');
      await chat.sendText('Again');
      expect(chat.error, isNull);
      expect(chat.messages.where((m) => m.role == 'assistant').length, 2);
    },
  );

  test(
    'real Dart ChatClient binds and resumes a server tool approval',
    () async {
      var calls = 0;
      final agent = AiAgent<void>(
        model: TestModel(withTool: true),
        tools: [
          Tool<int, int, void>(
            name: 'double',
            description: 'Double',
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            needsApproval: true,
            decode: (json) => json['count'] as int,
            encode: (value) => value,
            execute: (n, _) {
              calls++;
              return n * 2;
            },
          ),
        ],
      );
      final chat = client.ChatClient(
        connection: connect(agent),
        threadId: 'approval',
        tools: [
          client.ChatClientTool(
            name: 'double',
            needsApproval: true,
            inputSchema: platform.RawJsonSchema(inputSchema),
            outputSchema: platform.RawJsonSchema(outputSchema),
          ),
        ],
      );
      addTearDown(chat.dispose);
      await chat.sendText('Start');
      expect(chat.error, isNull);
      final interrupt = chat.getInterrupts().single;
      expect(interrupt.kind, 'tool-approval');
      expect(interrupt.canResolve, isTrue);
      expect(calls, 0);
      interrupt.resolveApproval(true);
      for (var i = 0; i < 100 && calls == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      for (var i = 0; i < 100 && chat.isStreaming; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(chat.error, isNull);
      expect(calls, 1);
      expect(chat.messages.last.answer, 'Hello from Dart');
    },
  );

  test(
    'real Dart client executes a bound client tool and resumes automatically',
    () async {
      var calls = 0;
      final agent = AiAgent<void>(
        model: TestModel(withTool: true),
        tools: [
          const ClientTool<void>(
            definition: ModelTool(
              name: 'double',
              description: 'Double on device',
              inputSchema: inputSchema,
            ),
            outputSchema: outputSchema,
          ),
        ],
      );
      final chat = client.ChatClient(
        connection: connect(agent),
        threadId: 'client-tool',
        tools: [
          client.ChatClientTool(
            name: 'double',
            inputSchema: platform.RawJsonSchema(inputSchema),
            outputSchema: platform.RawJsonSchema(outputSchema),
            execute: (dynamic input, _) {
              calls++;
              return ((input as Map)['count'] as int) * 2;
            },
          ),
        ],
      );
      addTearDown(chat.dispose);
      await chat.sendText('Start');
      for (var i = 0; i < 100 && (calls == 0 || chat.isStreaming); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(chat.error, isNull);
      expect(calls, 1);
      expect(chat.messages.last.answer, 'Hello from Dart');
    },
  );

  test('approval and schema hashes match the existing client library', () {
    expect(schemaHash(inputSchema), platform.hashSchemaInput(inputSchema));
    expect(schemaHash(null), platform.hashSchemaInput(null));
    final approval = platform.normalizeApprovalSchema(null, inputSchema);
    expect(approvalResponseSchema(inputSchema), approval.responseSchema);
    expect(
      schemaHash(approvalResponseSchema(inputSchema)),
      approval.responseSchemaHash,
    );
    expect(
      schemaHash({'approve': null, 'reject': null}),
      approval.approvalSchemaHash,
    );
  });
}
