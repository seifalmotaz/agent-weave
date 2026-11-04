import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'cancellation.dart';
import 'model.dart';
import 'protocol.dart';
import 'storage.dart';
import 'tool.dart';

/// A reusable agent definition. Mutable conversation state belongs to [store].
final class AiAgent<C> {
  final ChatModel model;
  final List<AgentTool<C>> tools;
  final String? instructions;
  final JsonObject? outputSchema;
  final int maxSteps;
  final int maxOutputTokens;
  final RunStore store;

  /// Receives internal errors for server-side tracing. Never sent to clients.
  final void Function(Object error, StackTrace stack)? onError;
  final String Function() _newId;

  AiAgent({
    required this.model,
    Iterable<AgentTool<C>> tools = const [],
    this.instructions,
    JsonObject? outputSchema,
    this.maxSteps = 8,
    this.maxOutputTokens = 1024,
    RunStore? store,
    this.onError,
    String Function()? newId,
  }) : tools = List.unmodifiable(tools),
       store = store ?? MemoryRunStore(),
       outputSchema = outputSchema == null ? null : immutableJson(outputSchema),
       _newId = newId ?? const Uuid().v4 {
    if (maxSteps < 1 || maxOutputTokens < 1) {
      throw ArgumentError('Step and output token limits must be positive.');
    }
    if (this.tools.map((t) => t.definition.name).toSet().length !=
        this.tools.length) {
      throw ArgumentError('Tool names must be unique.');
    }
    if (this.tools.isNotEmpty && !model.capabilities.tools) {
      throw ArgumentError('The model does not support tools.');
    }
    if (outputSchema != null && !model.capabilities.structuredOutput) {
      throw ArgumentError('The model does not support structured output.');
    }
  }

  /// [ownerId] and [context] must come from trusted server authentication.
  /// Cancelling the subscription cancels the underlying provider invocation.
  Stream<AgentEvent> run(
    ChatRequest request, {
    required String ownerId,
    required C context,
    CancellationToken? cancellation,
  }) {
    final token = cancellation ?? CancellationToken();
    StreamSubscription<AgentEvent>? subscription;
    late final StreamController<AgentEvent> controller;
    controller = StreamController<AgentEvent>(
      onListen: () {
        subscription = _execute(request, ownerId, context, token).listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        token.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<AgentEvent> _execute(
    ChatRequest request,
    String ownerId,
    C context,
    CancellationToken token,
  ) async* {
    if (ownerId.isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
    token.throwIfCancelled();
    final previous = await store.begin(
      ownerId: ownerId,
      threadId: request.threadId,
      runId: request.runId,
      parentRunId: request.parentRunId,
    );
    final messages = <ChatMessage>[
      for (final raw in previous['messages'] as List? ?? [])
        ChatMessage.fromJson(Map<String, Object?>.from(raw as Map)),
    ];
    final journal = <JsonObject>[];
    final pending = <JsonObject>[];
    final usage = <JsonObject>[];
    final generation = (previous['generation'] as int? ?? 0) + 1;
    var status = RunStatus.running;
    var released = false;
    var accepted = false;
    String? partialMessageId;
    StringBuffer? partialText;
    void preservePartial() {
      final id = partialMessageId;
      final text = partialText;
      if (id != null &&
          text != null &&
          text.isNotEmpty &&
          !messages.any((m) => m.id == id)) {
        messages.add(
          ChatMessage(
            id: id,
            role: MessageRole.assistant,
            content: [TextPart(text.toString())],
          ),
        );
      }
    }

    List<ToolCall> unresolvedCalls() {
      final completed = messages
          .where((m) => m.role == MessageRole.tool)
          .map((m) => m.toolCallId)
          .toSet();
      return [
        for (final message in messages)
          for (final call in message.toolCalls)
            if (!completed.contains(call.id)) call,
      ];
    }

    JsonObject state() => {
      'kind': 'chat',
      'runId': request.runId,
      'threadId': request.threadId,
      'generation': generation,
      'status': status.name,
      'messages': [for (final m in messages) m.toJson()],
      'events': journal,
      'pending': pending,
    };
    Future<AgentEvent> event(
      String type, [
      JsonObject fields = const {},
    ]) async {
      final json = <String, Object?>{
        'type': type,
        'threadId': request.threadId,
        'runId': request.runId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'sequence': journal.length,
        ...fields,
        if ((type == 'RUN_FINISHED' || type == 'RUN_ERROR') && usage.isNotEmpty)
          'usage': List<JsonObject>.of(usage),
      };
      journal.add(json);
      await store.appendEvent(
        ownerId: ownerId,
        threadId: request.threadId,
        runId: request.runId,
        event: json,
      );
      if (type == 'RUN_FINISHED' || type == 'RUN_ERROR') {
        await store.save(
          ownerId: ownerId,
          threadId: request.threadId,
          runId: request.runId,
          state: state(),
          release: true,
        );
        released = true;
      }
      return AgentEvent(json);
    }

    try {
      if (previous['kind'] != null && previous['kind'] != 'chat') {
        throw const FormatException('Thread belongs to a different operation.');
      }
      final known = messages.map((m) => m.id).toSet();
      for (final message in request.messages) {
        if (!known.contains(message.id)) {
          if (message.role != MessageRole.user) {
            throw const FormatException(
              'Only user messages may extend server history.',
            );
          }
          messages.add(message);
          known.add(message.id);
        }
      }
      for (final message in messages) {
        if (!model.capabilities.imageInput &&
            message.content.any((p) => p is ImagePart)) {
          throw const FormatException('The model does not accept images.');
        }
        if (!model.capabilities.fileInput &&
            message.content.any((p) => p is FilePart)) {
          throw const FormatException('The model does not accept files.');
        }
        if (!model.capabilities.audioInput &&
            message.content.any((p) => p is AudioPart)) {
          throw const FormatException('The model does not accept audio.');
        }
        if (!model.capabilities.videoInput &&
            message.content.any((p) => p is VideoPart)) {
          throw const FormatException('The model does not accept video.');
        }
      }
      final waiting = [
        for (final raw in previous['pending'] as List? ?? [])
          Map<String, Object?>.from(raw as Map),
      ];
      if (request.resume.length != waiting.length ||
          !waiting.every(
            (p) => request.resume.any((r) => r.interruptId == p['id']),
          )) {
        throw const FormatException(
          'Resume must answer every pending interrupt exactly once.',
        );
      }
      // Validate the entire resolution batch before executing any side effect.
      for (final item in waiting) {
        final call = ToolCall.fromJson(
          Map<String, Object?>.from(item['call'] as Map),
        );
        final tool = _tool(call.name);
        if (schemaHash(tool.definition.inputSchema) !=
                item['inputSchemaHash'] ||
            schemaHash(tool.outputSchema) != item['outputSchemaHash']) {
          throw const FormatException(
            'Tool schema changed since the run paused.',
          );
        }
        final resolution = request.resume.singleWhere(
          (r) => r.interruptId == item['id'],
        );
        if (resolution.cancelled) continue;
        final value = resolution.value;
        if (tool.clientExecuted) {
          if (tool.outputSchema case final schema?) {
            validateSchema(schema, value);
          }
        } else {
          final answer = value is bool
              ? <String, Object?>{'approved': value}
              : Map<String, Object?>.from(value as Map);
          validateSchema(
            approvalResponseSchema(tool.definition.inputSchema),
            answer,
          );
        }
      }
      accepted = true;
      await store.save(
        ownerId: ownerId,
        threadId: request.threadId,
        runId: request.runId,
        state: state(),
        release: false,
      );
      yield await event('RUN_STARTED', {
        if (request.parentRunId != null) 'parentRunId': request.parentRunId,
      });
      for (final item in waiting) {
        final call = ToolCall.fromJson(
          Map<String, Object?>.from(item['call'] as Map),
        );
        final tool = _tool(call.name);
        final resolution = request.resume.singleWhere(
          (r) => r.interruptId == item['id'],
        );
        final answer = resolution.cancelled ? false : resolution.value;
        Object? result;
        if (tool.clientExecuted) {
          result = resolution.cancelled
              ? {'error': 'Client tool was cancelled.'}
              : answer;
        } else {
          final resolution = answer is bool
              ? <String, Object?>{'approved': answer}
              : Map<String, Object?>.from(answer as Map);
          if (resolution['approved'] == true) {
            final edited = resolution['editedArgs'];
            result = await _invoke(
              tool,
              edited == null
                  ? call
                  : ToolCall(
                      id: call.id,
                      name: call.name,
                      arguments: Map<String, Object?>.from(edited as Map),
                    ),
              request,
              ownerId,
              context,
              token,
            );
          } else {
            result = {'error': 'Tool execution was declined.'};
          }
        }
        messages.add(_result(call, result));
        yield await event('TOOL_CALL_RESULT', _resultFields(call, result));
      }
      for (var step = 0; step < maxSteps; step++) {
        token.throwIfCancelled();
        final messageId = _newId();
        final text = StringBuffer();
        partialMessageId = messageId;
        partialText = text;
        final calls = <ToolCall>[];
        final providerData = <String, List<JsonObject>>{};
        var textStarted = false;
        var reasoningStarted = false;
        var finished = false;
        var finishReason = 'stop';
        await for (final item in model.stream(
          ModelRequest(
            messages: messages,
            tools: tools.map((t) => t.definition),
            instructions: instructions,
            outputSchema: outputSchema,
            maxOutputTokens: maxOutputTokens,
          ),
          cancellation: token,
        )) {
          token.throwIfCancelled();
          if (finished) {
            throw StateError('Provider emitted events after completion.');
          }
          switch (item) {
            case TextDelta(text: final delta):
              if (!textStarted) {
                textStarted = true;
                yield await event('TEXT_MESSAGE_START', {
                  'messageId': messageId,
                  'role': 'assistant',
                });
                if (outputSchema != null) {
                  yield await event('CUSTOM', {
                    'name': 'structured-output.start',
                    'value': {'messageId': messageId},
                  });
                }
              }
              text.write(delta);
              yield await event('TEXT_MESSAGE_CONTENT', {
                'messageId': messageId,
                'delta': delta,
              });
            case ReasoningDelta(:final text):
              if (!reasoningStarted) {
                reasoningStarted = true;
                yield await event('REASONING_START', {'messageId': messageId});
                yield await event('REASONING_MESSAGE_START', {
                  'messageId': messageId,
                  'role': 'assistant',
                });
              }
              yield await event('REASONING_MESSAGE_CONTENT', {
                'messageId': messageId,
                'delta': text,
              });
            case ToolCallReady(:final call):
              if (calls.any((c) => c.id == call.id) ||
                  messages.any(
                    (m) => m.toolCalls.any((c) => c.id == call.id),
                  )) {
                throw const FormatException(
                  'Provider reused a tool call identifier.',
                );
              }
              final tool = _tool(call.name);
              validateSchema(tool.definition.inputSchema, call.arguments);
              calls.add(call);
              yield await event('TOOL_CALL_START', {
                'toolCallId': call.id,
                'toolCallName': call.name,
                'parentMessageId': messageId,
              });
              yield await event('TOOL_CALL_ARGS', {
                'toolCallId': call.id,
                'delta': jsonEncode(call.arguments),
              });
              yield await event('TOOL_CALL_END', {
                'toolCallId': call.id,
                'toolName': call.name,
                'args': jsonEncode(call.arguments),
                'input': call.arguments,
              });
            case TokenUsage(:final inputTokens, :final outputTokens):
              usage.add(item.toJson());
              yield await event('CUSTOM', {
                'name': 'agent_weave:usage',
                'value': {
                  'inputTokens': inputTokens,
                  'outputTokens': outputTokens,
                },
              });
            case ModelFinished(:final reason):
              finished = true;
              finishReason = reason;
            case ProviderOutput(:final provider, :final items):
              providerData[provider] = items;
          }
        }
        if (!finished) {
          throw StateError('Provider stream ended without a terminal event.');
        }
        if (calls.isNotEmpty && finishReason == 'length') {
          throw StateError(
            'Cannot execute tools from a truncated model invocation.',
          );
        }
        messages.add(
          ChatMessage(
            id: messageId,
            role: MessageRole.assistant,
            content: text.isEmpty ? const [] : [TextPart(text.toString())],
            toolCalls: calls,
            providerData: providerData,
          ),
        );
        partialMessageId = null;
        partialText = null;
        // Checkpoint before executing tools; event deltas use an append-only log.
        await store.save(
          ownerId: ownerId,
          threadId: request.threadId,
          runId: request.runId,
          state: state(),
          release: false,
        );
        if (textStarted) {
          yield await event('TEXT_MESSAGE_END', {'messageId': messageId});
        }
        if (reasoningStarted) {
          yield await event('REASONING_MESSAGE_END', {'messageId': messageId});
          yield await event('REASONING_END', {'messageId': messageId});
        }
        if (calls.isEmpty) {
          if (outputSchema case final schema?) {
            final object = jsonDecode(text.toString());
            validateSchema(schema, object);
            yield await event('CUSTOM', {
              'name': 'structured-output.complete',
              'value': {
                'messageId': messageId,
                'object': object,
                'raw': text.toString(),
              },
            });
          }
          status = RunStatus.completed;
          yield await event('RUN_FINISHED', {'finishReason': finishReason});
          return;
        }
        final interrupts = <JsonObject>[];
        for (final call in calls) {
          final tool = _tool(call.name);
          if (tool.needsApproval || tool.clientExecuted) {
            final id = _newId();
            pending.add({
              'id': id,
              'call': call.toJson(),
              'inputSchemaHash': schemaHash(tool.definition.inputSchema),
              'outputSchemaHash': schemaHash(tool.outputSchema),
            });
            final binding = <String, Object?>{
              'v': 1,
              'interruptId': id,
              'interruptedRunId': request.runId,
              'generation': generation,
              'toolName': call.name,
              'toolCallId': call.id,
              'kind': tool.clientExecuted
                  ? 'client-tool-execution'
                  : 'tool-approval',
              if (tool.clientExecuted) ...{
                'outputSchemaHash': schemaHash(tool.outputSchema),
                'responseSchemaHash': schemaHash(tool.outputSchema),
              } else ...{
                'originalArgs': call.arguments,
                'inputSchemaHash': schemaHash(tool.definition.inputSchema),
                'approvalSchemaHash': schemaHash({
                  'approve': null,
                  'reject': null,
                }),
                'responseSchemaHash': schemaHash(
                  approvalResponseSchema(tool.definition.inputSchema),
                ),
              },
            };
            interrupts.add({
              'id': id,
              'toolCallId': call.id,
              'reason': tool.clientExecuted
                  ? 'tanstack:client_tool_execution'
                  : 'tool_call',
              'metadata': {
                'kind': tool.clientExecuted ? 'client_tool' : 'approval',
                'toolName': call.name,
                'input': call.arguments,
                'tanstack:interruptBinding': binding,
              },
              if (!tool.clientExecuted)
                'responseSchema': approvalResponseSchema(
                  tool.definition.inputSchema,
                ),
            });
          } else {
            final result = await _invoke(
              tool,
              call,
              request,
              ownerId,
              context,
              token,
            );
            messages.add(_result(call, result));
            yield await event('TOOL_CALL_RESULT', _resultFields(call, result));
          }
        }
        if (interrupts.isNotEmpty) {
          status = RunStatus.interrupted;
          yield await event('RUN_FINISHED', {
            'outcome': {'type': 'interrupt', 'interrupts': interrupts},
          });
          return;
        }
      }
      throw StateError('The agent reached its step limit.');
    } catch (error, stack) {
      status = token.isCancelled ? RunStatus.cancelled : RunStatus.failed;
      onError?.call(error, stack);
      preservePartial();
      if (accepted) {
        for (final call in unresolvedCalls()) {
          final result = {
            'error':
                'Tool execution failed or was interrupted. Verify external effects before retrying.',
          };
          messages.add(_result(call, result));
          if (!token.isCancelled) {
            yield await event('TOOL_CALL_RESULT', {
              ..._resultFields(call, result),
              'metadata': {
                'tanstack': {'state': 'output-error'},
              },
            });
          }
        }
      }
      if (!accepted) {
        // Invalid continuations must not erase the pending approval snapshot.
        await store.save(
          ownerId: ownerId,
          threadId: request.threadId,
          runId: request.runId,
          state: previous,
          release: true,
        );
        released = true;
      }
      if (!token.isCancelled) {
        final fields = <String, Object?>{
          'code': error is FormatException ? 'INVALID_INPUT' : 'RUN_FAILED',
          'message': error is FormatException
              ? 'Invalid input or provider output.'
              : 'The AI run could not complete.',
        };
        yield accepted
            ? await event('RUN_ERROR', fields)
            : AgentEvent({
                'type': 'RUN_ERROR',
                'threadId': request.threadId,
                'runId': request.runId,
                ...fields,
              });
      }
    } finally {
      if (status == RunStatus.running) status = RunStatus.cancelled;
      preservePartial();
      if (accepted && status == RunStatus.cancelled) {
        for (final call in unresolvedCalls()) {
          messages.add(
            _result(call, {
              'error':
                  'The run was cancelled. Verify external effects before retrying.',
            }),
          );
        }
      }
      if (!released) {
        released = true;
        await store.save(
          ownerId: ownerId,
          threadId: request.threadId,
          runId: request.runId,
          state: state(),
          release: true,
        );
      }
    }
  }

  AgentTool<C> _tool(String name) => tools.firstWhere(
    (tool) => tool.definition.name == name,
    orElse: () => throw const FormatException('Unknown tool.'),
  );

  Future<Object?> _invoke(
    AgentTool<C> tool,
    ToolCall call,
    ChatRequest request,
    String ownerId,
    C context,
    CancellationToken token,
  ) async {
    token.throwIfCancelled();
    return tool.invoke(
      call.arguments,
      ToolContext(
        value: context,
        ownerId: ownerId,
        threadId: request.threadId,
        runId: request.runId,
        toolCallId: call.id,
        cancellation: token,
      ),
    );
  }
}

ChatMessage _result(ToolCall call, Object? result) => ChatMessage(
  id: 'result-${call.id}',
  role: MessageRole.tool,
  toolCallId: call.id,
  content: [TextPart(jsonEncode(result))],
);

JsonObject _resultFields(ToolCall call, Object? result) => {
  'toolCallId': call.id,
  'messageId': 'result-${call.id}',
  'content': jsonEncode(result),
  'role': 'tool',
};
