import 'model.dart';
import 'storage.dart';
import 'protocol.dart';

/// A server-side snapshot belonging to one run, independent of later turns.
/// Includes private provider continuation state; use chatHydration for UI data.
final class AgentResult {
  final String threadId;
  final String runId;
  final RunStatus status;
  final String? finishReason;
  final List<ChatMessage> messages;
  final List<ChatMessage> responseMessages;
  final List<TokenUsage> usages;
  final List<ToolInterrupt> interrupts;
  final Object? output;

  AgentResult({
    required this.threadId,
    required this.runId,
    required this.status,
    required Iterable<ChatMessage> messages,
    required Iterable<ChatMessage> responseMessages,
    required Iterable<TokenUsage> usages,
    Iterable<ToolInterrupt> interrupts = const [],
    this.finishReason,
    Object? output,
  }) : messages = List.unmodifiable(messages),
       responseMessages = List.unmodifiable(responseMessages),
       usages = List.unmodifiable(usages),
       interrupts = List.unmodifiable(interrupts),
       output = immutableJson({'value': output})['value'];

  /// The final assistant message in this run, excluding intermediate tool steps.
  String get text =>
      responseMessages
          .where((m) => m.role == MessageRole.assistant)
          .lastOrNull
          ?.text ??
      '';

  /// Images produced by assistant messages in this run, including tool steps.
  List<ImagePart> get images => List.unmodifiable([
    for (final message in responseMessages)
      if (message.role == MessageRole.assistant)
        ...message.content.whereType<ImagePart>(),
  ]);

  /// Null means the provider reported no usage. Missing token details stay null.
  TokenUsage? get usage {
    if (usages.isEmpty) return null;
    final models = usages.map((u) => u.model).toSet();
    return TokenUsage(
      inputTokens: usages.fold<int>(0, (sum, u) => sum + u.inputTokens),
      outputTokens: usages.fold<int>(0, (sum, u) => sum + u.outputTokens),
      model: models.length == 1 ? models.single : null,
      cachedInputTokens: usages.every((u) => u.cachedInputTokens != null)
          ? usages.fold<int>(0, (sum, u) => sum + u.cachedInputTokens!)
          : null,
      reasoningTokens: usages.every((u) => u.reasoningTokens != null)
          ? usages.fold<int>(0, (sum, u) => sum + u.reasoningTokens!)
          : null,
    );
  }
}

/// An interrupted tool is a successful pause, not an execution failure.
final class ToolInterrupt {
  final String id;
  final ToolCall call;
  final bool clientExecuted;
  const ToolInterrupt({
    required this.id,
    required this.call,
    required this.clientExecuted,
  });

  ResumeAnswer approve({JsonObject? editedArgs}) {
    if (clientExecuted) {
      throw StateError(
        'Client tools resolve an output instead of an approval.',
      );
    }
    if (call is NativeToolCall && editedArgs != null) {
      throw StateError('Native tool arguments cannot be edited.');
    }
    return ResumeAnswer(
      interruptId: id,
      value: editedArgs == null
          ? true
          : {'approved': true, 'editedArgs': editedArgs},
    );
  }

  ResumeAnswer reject() {
    if (clientExecuted) {
      throw StateError(
        'Cancel a client tool instead of rejecting an approval.',
      );
    }
    return ResumeAnswer(interruptId: id, value: false);
  }

  ResumeAnswer resolve(Object? output) {
    if (!clientExecuted) {
      throw StateError('Server tools require an approval decision.');
    }
    return ResumeAnswer(interruptId: id, value: output);
  }

  ResumeAnswer cancel() => ResumeAnswer.cancelled(interruptId: id);
}

/// A failed Future-based agent run. Never serialize [cause] to a UI client.
final class AgentRunException implements Exception {
  final String code;
  final AgentResult result;
  final Object cause;
  final StackTrace causeStackTrace;
  const AgentRunException({
    required this.code,
    required this.result,
    required this.cause,
    required this.causeStackTrace,
  });
  @override
  String toString() =>
      'AgentRunException($code): The AI run could not complete.';
}

final class ObjectResult<T> {
  final T value;
  final AgentResult generation;
  const ObjectResult({required this.value, required this.generation});
}
