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
const refSchema = <String, Object?>{
  'type': 'object',
  r'$defs': {
    'number': {'type': 'integer', 'minimum': 1},
  },
  'properties': {
    'count': {r'$ref': r'#/$defs/number'},
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

client.ConnectionAdapter connect(
  AiAgent<void> agent, {
  void Function(AgentEvent)? onEvent,
}) => serverpodConnection(
  send: (raw) => agent
      .run(
        ChatRequest.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map)),
        ownerId: 'owner',
        context: null,
      )
      .map((event) {
        onEvent?.call(event);
        return jsonEncode(event.json);
      }),
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

  for (final valid in [true, false]) {
    test('Dart client local ref edited approval valid=$valid', () async {
      final calls = <int>[];
      final events = <AgentEvent>[];
      final agent = AiAgent<void>(
        model: TestModel(withTool: true),
        tools: [
          Tool<int, int, void>(
            name: 'double',
            description: 'Double',
            inputSchema: refSchema,
            outputSchema: outputSchema,
            needsApproval: true,
            decode: (json) => json['count'] as int,
            encode: (value) => value,
            execute: (n, _) {
              calls.add(n);
              return n * 2;
            },
          ),
        ],
      );
      final chat = client.ChatClient(
        connection: connect(agent, onEvent: events.add),
        threadId: 'ref',
        tools: [
          client.ChatClientTool(
            name: 'double',
            needsApproval: true,
            inputSchema: platform.RawJsonSchema(refSchema),
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
      expect(calls, isEmpty);
      interrupt.resolveInterrupt({
        'approved': true,
        'editedArgs': {'count': valid ? 3 : 'invalid'},
      });
      for (
        var i = 0;
        i < 100 &&
            chat.error == null &&
            !chat.messages.any((m) => m.answer == 'Hello from Dart');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (valid) {
        expect(chat.error, isNull);
        expect(calls, [3]);
        expect(chat.messages.last.answer, 'Hello from Dart');
      } else {
        expect(chat.error, 'Invalid input or provider output.');
        expect(events.last.json['code'], 'INVALID_INPUT');
        expect(calls, isEmpty);
      }
    });
  }

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
    expect(schemaHash(refSchema), platform.hashSchemaInput(refSchema));
    final refApproval = platform.normalizeApprovalSchema(null, refSchema);
    expect(approvalResponseSchema(refSchema), refApproval.responseSchema);
    expect(
      schemaHash(approvalResponseSchema(refSchema)),
      refApproval.responseSchemaHash,
    );
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
