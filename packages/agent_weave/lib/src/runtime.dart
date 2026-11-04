import 'dart:async';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:json_schema/json_schema.dart';
import 'cancellation.dart';
import 'citations.dart';
import 'references.dart';
import 'diagnostics.dart';
import 'model.dart';
import 'protocol.dart';
import 'storage.dart';
import 'result.dart';
import 'tool.dart';
import 'history.dart';

/// A reusable agent definition. Mutable conversation state belongs to [store].
final class AiAgent<C> {
  final ChatModel model;
  final List<AgentTool<C>> tools;
  final String? instructions;

  /// Trusted server-side seed history for new threads, never request-body data.
  final List<ChatMessage> initialMessages;
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
    Iterable<ChatMessage> initialMessages = const [],
    JsonObject? outputSchema,
    this.maxSteps = 8,
    this.maxOutputTokens = 1024,
    RunStore? store,
    this.onError,
    String Function()? newId,
  }) : tools = List.unmodifiable(tools),
       initialMessages = List.unmodifiable(initialMessages),
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
    if (this.initialMessages.map((m) => m.id).toSet().length !=
        this.initialMessages.length) {
      throw ArgumentError('Initial message identifiers must be unique.');
    }
    for (final tool in this.tools) {
      validateToolDefinition(tool.definition, tool.outputSchema);
      if (tool.clientExecuted && tool.definition is NativeModelTool) {
        throw UnsupportedError(
          'Client-executed native tools are not supported.',
        );
      }
    }
    if (outputSchema != null) JsonSchema.create(outputSchema);
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
  }) => _run(
    request,
    ownerId: ownerId,
    context: context,
    cancellation: cancellation,
  );

  /// Return a typed result without parsing UI protocol events.
  /// Failures throw [AgentRunException]; interruptions return a paused result.
  Future<AgentResult> generate(
    ChatRequest request, {
    required String ownerId,
    required C context,
    CancellationToken? cancellation,
  }) async {
    AgentResult? result;
    _RunFailure? failure;
    await _run(
      request,
      ownerId: ownerId,
      context: context,
      cancellation: cancellation,
      onResult: (value, error) {
        result = value;
        failure = error;
      },
    ).drain<void>();
    final value = result!;
    if (value.status == RunStatus.cancelled) throw const RunCancelled();
    if (failure case final error?) {
      Error.throwWithStackTrace(
        AgentRunException(
          code: error.code,
          message: error.message,
          result: value,
          cause: error.cause,
          causeStackTrace: error.stack,
        ),
        error.stack,
      );
    }
    return value;
  }

  Stream<AgentEvent> _run(
    ChatRequest request, {
    required String ownerId,
    required C context,
    CancellationToken? cancellation,
    void Function(AgentResult, _RunFailure?)? onResult,
  }) => (cancellation ?? CancellationToken()).bindStream(
    (token) => _execute(request, ownerId, context, token, onResult),
  );

  Stream<AgentEvent> _execute(
    ChatRequest request,
    String ownerId,
    C context,
    CancellationToken token,
    void Function(AgentResult, _RunFailure?)? onResult,
  ) async* {
    if (ownerId.isEmpty) throw ArgumentError.value(ownerId, 'ownerId');
    token.throwIfCancelled();
    final previous = await store.begin(
      ownerId: ownerId,
      threadId: request.threadId,
      runId: request.runId,
      parentRunId: request.parentRunId,
    );
    late final List<ChatMessage> messages;
    late final int generation;
    String? nativeContinuationClosed;
    try {
      messages = <ChatMessage>[
        if (!previous.containsKey('messages'))
          ...initialMessages
        else
          for (final raw in previous['messages'] as List)
            ChatMessage.fromJson(Map<String, Object?>.from(raw as Map)),
      ];
      generation = (previous['generation'] as int? ?? 0) + 1;
      nativeContinuationClosed =
          previous['nativeContinuationClosed'] as String?;
    } catch (error, stack) {
      // A newer or corrupt snapshot must not strand the acquired reservation.
      await store.save(
        ownerId: ownerId,
        threadId: request.threadId,
        runId: request.runId,
        state: previous,
        release: true,
      );
      reportError(onError, error, stack);
      throw const FormatException(
        'Stored conversation cannot be decoded by this SDK.',
      );
    }
    final previousIds = messages.map((m) => m.id).toSet();
    _RunFailure? failure;
    var phase = 'input';
    String? lastFinishReason;
    Object? structuredOutput;
    final journal = <JsonObject>[];
    final pending = <JsonObject>[];
    final usage = <TokenUsage>[];
    var status = RunStatus.running;
    var released = false;
    var accepted = false;
    var providerContinuationPending =
        previous['providerContinuationPending'] == true;
    String? partialMessageId;
    StringBuffer? partialText;
    List<TextCitation>? partialCitations;
    List<OutputReference>? partialReferences;
    void preservePartial() {
      final id = partialMessageId;
      final text = partialText;
      if (id != null &&
          text != null &&
          (text.isNotEmpty || (partialReferences?.isNotEmpty ?? false)) &&
          !messages.any((m) => m.id == id)) {
        messages.add(
          ChatMessage(
            id: id,
            role: MessageRole.assistant,
            content: [TextPart(text.toString())],
            citations: partialCitations ?? const [],
            references: partialReferences ?? const [],
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
      if (providerContinuationPending) 'providerContinuationPending': true,
      'nativeContinuationClosed': ?nativeContinuationClosed,
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
          'usage': [for (final item in usage) item.toJson()],
      };
      journal.add(json);
      try {
        if (type == 'RUN_FINISHED' || type == 'RUN_ERROR') {
          await store.complete(
            ownerId: ownerId,
            threadId: request.threadId,
            runId: request.runId,
            event: json,
            state: state(),
          );
          released = true;
        } else {
          await store.appendEvent(
            ownerId: ownerId,
            threadId: request.threadId,
            runId: request.runId,
            event: json,
          );
        }
      } catch (_) {
        journal.removeLast();
        rethrow;
      }
      return AgentEvent(json);
    }

    try {
      if (nativeContinuationClosed != null) {
        throw const FormatException(
          'Native continuation closed; start a new thread.',
        );
      }
      if (((previous['pending'] as List? ?? []).isNotEmpty ||
              providerContinuationPending) &&
          request.messages.any(
            (message) => !messages.any((saved) => saved.id == message.id),
          )) {
        throw const FormatException(
          'Resolve pending tools or provider continuation before adding a new user message.',
        );
      }
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
            message.content.any((p) => p is FilePart || p is DocumentPart)) {
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
        final recorded = item['toolContract'];
        if (!item.containsKey('toolContract')) {
          throw const _ToolContractException(
            'This approval predates exact tool contract checks. Start a new conversation.',
          );
        }
        if (recorded is! Map<String, Object?> || recorded['v'] != 1) {
          throw const _ToolContractException(
            'This approval uses an unsupported tool contract. Start a new conversation.',
          );
        }
        final tool = tools
            .where((tool) => tool.definition.name == call.name)
            .firstOrNull;
        if (tool == null || !jsonEquals(recorded, _toolContract(tool))) {
          throw const _ToolContractException(
            'Tool configuration changed. Start a new conversation.',
          );
        }
        _validateToolKind(call, tool.definition);
        final resolution = request.resume.singleWhere(
          (r) => r.interruptId == item['id'],
        );
        if (resolution.cancelled) continue;
        final value = resolution.value;
        try {
          jsonEncode(value);
        } catch (_) {
          throw const FormatException(
            'Interrupt answers must be JSON-serializable.',
          );
        }
        if (value is! bool &&
            !tool.clientExecuted &&
            value is! Map<String, Object?>) {
          throw const FormatException('Expected an approval decision.');
        }
        if (tool.clientExecuted) {
          if (tool.outputSchema case final schema?) {
            validateSchema(schema, value);
          }
        } else {
          final answer = value is bool
              ? <String, Object?>{'approved': value}
              : Map<String, Object?>.from(value as Map);
          validateSchema(
            _approvalSchema(call, tool.definition.inputSchema),
            answer,
          );
          if (call is NativeToolCall && answer.containsKey('editedArgs')) {
            throw const FormatException(
              'Native tool arguments cannot be edited.',
            );
          }
        }
      }
      final nativeDeclined = waiting.any((item) {
        final call = ToolCall.fromJson(
          Map<String, Object?>.from(item['call'] as Map),
        );
        if (call is! NativeToolCall) return false;
        final answer = request.resume.singleWhere(
          (r) => r.interruptId == item['id'],
        );
        return answer.cancelled ||
            answer.value == false ||
            (answer.value is Map && (answer.value as Map)['approved'] == false);
      });
      accepted = true;
      if (nativeDeclined) {
        nativeContinuationClosed =
            'Native tool approval declined or cancelled; start a new thread.';
        status = RunStatus.cancelled;
        yield await event('RUN_STARTED', {
          if (request.parentRunId != null) 'parentRunId': request.parentRunId,
        });
        yield await event('RUN_FINISHED', {
          'finishReason': 'cancelled',
          'outcome': {'type': 'cancelled', 'reason': nativeContinuationClosed},
        });
        return;
      }
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
      final failedNativeBatches = <String>{};
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
            phase = 'tool';
            result = await _invokeInBatch(
              failedNativeBatches,
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
              approved: true,
            );
          } else {
            result = {'error': 'Tool execution was declined.'};
          }
        }
        messages.add(_result(call, result));
        yield await event('TOOL_CALL_RESULT', _resultFields(call, result));
      }
      for (var step = 0; step < maxSteps; step++) {
        failedNativeBatches.clear();
        phase = 'provider';
        token.throwIfCancelled();
        final messageId = _newId();
        final text = StringBuffer();
        final media = <({int offset, ContentPart part})>[];
        final citations = <TextCitation>[];
        final references = <OutputReference>[];
        partialReferences = references;
        partialCitations = citations;
        var hasMedia = false;
        partialMessageId = messageId;
        partialText = text;
        final calls = <ToolCall>[];
        final providerData = <String, List<JsonObject>>{};
        var textStarted = false;
        var reasoningStarted = false;
        var finished = false;
        var continueTurn = false;
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
            case ReferenceReady(:final reference):
              reference.validateFor(text.toString());
              references.add(reference);
              yield await event('CUSTOM', {
                'name': 'agent_weave:reference',
                'value': {
                  'messageId': messageId,
                  'referenceIndex': references.length - 1,
                  'reference': reference.toJson(),
                },
              });
            case CitationReady(:final citation):
              citation.validateFor(text.toString());
              citations.add(citation);
              yield await event('CUSTOM', {
                'name': 'agent_weave:citation',
                'value': {
                  'messageId': messageId,
                  'citationIndex': citations.length - 1,
                  'citation': citation.toJson(),
                },
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
            case ContentPartReady(:final part, :final textOffset):
              final offset = textOffset ?? text.length;
              if (offset > text.length ||
                  (media.isNotEmpty && offset < media.last.offset)) {
                throw const FormatException(
                  'Output media has an invalid text offset.',
                );
              }
              media.add((offset: offset, part: part));
              hasMedia = true;
            case ToolCallReady() || NativeToolCallReady():
              final call = switch (item) {
                ToolCallReady(:final call) => call,
                NativeToolCallReady(:final call) => call,
                _ => throw StateError('Unexpected tool call event.'),
              };
              if (calls.any((c) => c.id == call.id) ||
                  messages.any(
                    (m) => m.toolCalls.any((c) => c.id == call.id),
                  )) {
                throw const FormatException(
                  'Provider reused a tool call identifier.',
                );
              }
              final tool = _tool(call.name);
              if ((item is ToolCallReady && call is! FunctionToolCall) ||
                  (item is NativeToolCallReady && call is! NativeToolCall)) {
                throw const FormatException('Tool call event kind mismatch.');
              }
              _validateToolKind(call, tool.definition);
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
              usage.add(item);
              yield await event('CUSTOM', {
                'name': 'agent_weave:usage',
                'value': {
                  'inputTokens': inputTokens,
                  'outputTokens': outputTokens,
                },
              });
            case ModelFinished(:final reason, continueTurn: final continuation):
              finished = true;
              continueTurn = continuation;
              finishReason = reason;
              lastFinishReason = reason;
            case ProviderOutput(:final provider, :final items):
              providerData[provider] = items;
          }
        }
        if (!finished) {
          throw StateError('Provider stream ended without a terminal event.');
        }
        if (continueTurn && calls.isNotEmpty) {
          throw StateError('A provider continuation cannot await local tools.');
        }
        if (calls.isNotEmpty && finishReason == 'length') {
          throw StateError(
            'Cannot execute tools from a truncated model invocation.',
          );
        }
        providerContinuationPending = continueTurn;
        final content = <ContentPart>[];
        final fullText = text.toString();
        var cursor = 0;
        for (final output in media) {
          if (output.offset > cursor) {
            content.add(TextPart(fullText.substring(cursor, output.offset)));
          }
          content.add(output.part);
          cursor = output.offset;
        }
        if (cursor < fullText.length) {
          content.add(TextPart(fullText.substring(cursor)));
        }
        messages.add(
          ChatMessage(
            id: messageId,
            role: MessageRole.assistant,
            content: content,
            citations: citations,
            references: references,
            toolCalls: calls,
            providerData: providerData,
          ),
        );
        partialMessageId = null;
        partialText = null;
        partialCitations = null;
        partialReferences = null;
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
        if (continueTurn) {
          if (hasMedia ||
              citations.isNotEmpty ||
              references.isNotEmpty ||
              (outputSchema != null && textStarted)) {
            // A paused invocation is progress text, not a failed JSON answer.
            yield await event('MESSAGES_SNAPSHOT', {
              'messages': chatHydration(state())['messages'],
            });
          }
          continue;
        }
        if (calls.isEmpty) {
          if (outputSchema case final schema?) {
            phase = 'output';
            final object = jsonDecode(text.toString());
            validateSchema(schema, object);
            structuredOutput = object;
            messages[messages.length - 1] = ChatMessage(
              id: messageId,
              role: MessageRole.assistant,
              content: content,
              citations: citations,
              references: references,
              providerData: providerData,
              structuredOutput: StructuredMessageOutput(text.toString()),
            );
            yield await event('CUSTOM', {
              'name': 'structured-output.complete',
              'value': {
                'messageId': messageId,
                'object': object,
                'raw': text.toString(),
              },
            });
          }
          if (hasMedia || citations.isNotEmpty || references.isNotEmpty) {
            yield await event('MESSAGES_SNAPSHOT', {
              'messages': chatHydration(state())['messages'],
            });
          }
          status = RunStatus.completed;
          yield await event('RUN_FINISHED', {'finishReason': finishReason});
          return;
        }
        if (hasMedia ||
            citations.isNotEmpty ||
            references.isNotEmpty ||
            (outputSchema != null && textStarted)) {
          yield await event('MESSAGES_SNAPSHOT', {
            'messages': chatHydration(state())['messages'],
          });
        }
        final interrupts = <JsonObject>[];
        final sequentialApprovals = {
          for (final call in calls)
            if (_tool(call.name) is SequentialNativeTool<C> &&
                (_tool(call.name).needsApproval ||
                    (call is NativeToolCall && call.requiresApproval)))
              call.name,
        };
        for (final call in calls) {
          final tool = _tool(call.name);
          if (tool.needsApproval ||
              tool.clientExecuted ||
              sequentialApprovals.isNotEmpty ||
              (call is NativeToolCall && call.requiresApproval)) {
            final id = _newId();
            pending.add({
              'id': id,
              'call': call.toJson(),
              'toolContract': _toolContract(tool),
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
                  _approvalSchema(call, tool.definition.inputSchema),
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
                'responseSchema': _approvalSchema(
                  call,
                  tool.definition.inputSchema,
                ),
            });
          } else {
            phase = 'tool';
            final result = await _invokeInBatch(
              failedNativeBatches,
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
      phase = 'step_limit';
      throw StateError('The agent reached its step limit.');
    } catch (error, stack) {
      failure = (
        cause: error,
        stack: stack,
        code: switch (phase) {
          'input' => 'INVALID_INPUT',
          'output' => 'INVALID_OUTPUT',
          'provider' =>
            error is FormatException ? 'INVALID_OUTPUT' : 'MODEL_FAILED',
          'tool' => 'TOOL_FAILED',
          'step_limit' => 'STEP_LIMIT',
          _ => 'RUN_FAILED',
        },
        message: previous['nativeContinuationClosed'] != null
            ? 'Native continuation closed. Start a new thread.'
            : error is _ToolContractException
            ? error.message
            : error is FormatException
            ? 'Invalid input or provider output.'
            : 'The AI run could not complete.',
      );
      status = token.isCancelled ? RunStatus.cancelled : RunStatus.failed;
      reportError(onError, error, stack);
      preservePartial();
      if (accepted) {
        for (final call in unresolvedCalls()) {
          if (call is NativeToolCall) {
            nativeContinuationClosed =
                'Native tool execution failed; start a new thread.';
            continue;
          }
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
          'code': failure.code,
          'message': failure.message,
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
          if (call is NativeToolCall) {
            nativeContinuationClosed =
                'Native tool execution cancelled; start a new thread.';
            continue;
          }
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
      onResult?.call(
        AgentResult(
          threadId: request.threadId,
          runId: request.runId,
          status: status,
          messages: messages,
          responseMessages: messages.where(
            (m) => !previousIds.contains(m.id) && m.role != MessageRole.user,
          ),
          usages: usage,
          finishReason: lastFinishReason,
          output: structuredOutput,
          interrupts: [
            for (final item in pending)
              ToolInterrupt(
                id: item['id'] as String,
                call: ToolCall.fromJson(
                  Map<String, Object?>.from(item['call'] as Map),
                ),
                clientExecuted: _tool(
                  (item['call'] as Map)['name'] as String,
                ).clientExecuted,
              ),
          ],
        ),
        failure,
      );
    }
  }

  AgentTool<C> _tool(String name) => tools.firstWhere(
    (tool) => tool.definition.name == name,
    orElse: () => throw const FormatException('Unknown tool.'),
  );

  Future<Object?> _invokeInBatch(
    Set<String> failed,
    AgentTool<C> tool,
    ToolCall call,
    ChatRequest request,
    String ownerId,
    C context,
    CancellationToken token, {
    bool approved = false,
  }) async {
    token.throwIfCancelled();
    if (failed.isNotEmpty) {
      if (call is NativeToolCall && tool is SequentialNativeTool<C>) {
        return tool.skippedResult();
      }
      if (call is FunctionToolCall) {
        return {
          'error':
              'Not executed: an earlier native action in this turn failed.',
        };
      }
      throw StateError(
        'Cannot synthesize a skipped result for this native tool.',
      );
    }
    if (call is NativeToolCall && tool is SequentialNativeTool<C>) {
      final result = await _invoke(
        tool,
        call,
        request,
        ownerId,
        context,
        token,
        approved: approved,
      );
      if (tool.isFailure(result)) failed.add(call.name);
      return result;
    }
    return _invoke(
      tool,
      call,
      request,
      ownerId,
      context,
      token,
      approved: approved,
    );
  }

  Future<Object?> _invoke(
    AgentTool<C> tool,
    ToolCall call,
    ChatRequest request,
    String ownerId,
    C context,
    CancellationToken token, {
    bool approved = false,
  }) async {
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
        approved: approved,
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

void _validateToolKind(ToolCall call, ModelTool definition) {
  if (call is FunctionToolCall && definition is FunctionModelTool) {
    return;
  }
  if (call is NativeToolCall &&
      definition is NativeModelTool &&
      call.provider == definition.provider) {
    return;
  }
  throw const FormatException(
    'Tool call kind or provider does not match its definition.',
  );
}

// Private resume state must retain Dart integers; wire hashes use JS semantics.
JsonObject _toolContract<C>(AgentTool<C> tool) {
  final definition = tool.definition;
  return immutableJson({
    'v': 1,
    'kind': switch (definition) {
      FunctionModelTool() => 'function',
      NativeModelTool() => 'native',
    },
    'name': definition.name,
    'description': definition.description,
    'inputSchema': definition.inputSchema,
    'outputSchema': tool.outputSchema,
    'clientExecuted': tool.clientExecuted,
    'needsApproval': tool.needsApproval,
    'sequential': tool is SequentialNativeTool<C>,
    if (definition is NativeModelTool) ...{
      'provider': definition.provider,
      'bindingId': definition.bindingId,
      'definition': definition.definition,
    },
  });
}

final class _ToolContractException extends FormatException {
  const _ToolContractException(super.message);
}

JsonObject _approvalSchema(ToolCall call, JsonObject inputSchema) =>
    call is NativeToolCall
    ? {
        'type': 'object',
        'properties': {
          'approved': {'type': 'boolean'},
        },
        'required': ['approved'],
        'additionalProperties': false,
      }
    : approvalResponseSchema(inputSchema);

typedef _RunFailure = ({
  Object cause,
  StackTrace stack,
  String code,
  String message,
});
