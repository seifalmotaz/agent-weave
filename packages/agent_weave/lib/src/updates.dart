import 'citations.dart';
import 'model.dart';
import 'references.dart';
import 'result.dart';

/// Typed backend updates from one agent run. Tool and result data may be private.
sealed class AgentUpdate {
  const AgentUpdate();
}

/// Text appended to an assistant message.
final class AgentTextDelta extends AgentUpdate {
  final String messageId;
  final String text;
  const AgentTextDelta({required this.messageId, required this.text});
}

/// Reasoning appended to an assistant message, when supplied by the model.
final class AgentReasoningDelta extends AgentUpdate {
  final String messageId;
  final String text;
  const AgentReasoningDelta({required this.messageId, required this.text});
}

/// A complete non-text content part and its UTF-16 offset in the assistant text.
final class AgentContentPart extends AgentUpdate {
  final String messageId;
  final ContentPart part;
  final int textOffset;
  const AgentContentPart({
    required this.messageId,
    required this.part,
    required this.textOffset,
  });
}

/// A citation and its zero-based index within the assistant message.
final class AgentCitation extends AgentUpdate {
  final String messageId;
  final int index;
  final TextCitation citation;
  const AgentCitation({
    required this.messageId,
    required this.index,
    required this.citation,
  });
}

/// A reference and its zero-based index within the assistant message.
final class AgentReference extends AgentUpdate {
  final String messageId;
  final int index;
  final OutputReference reference;
  const AgentReference({
    required this.messageId,
    required this.index,
    required this.reference,
  });
}

/// A proposed tool call. This does not imply approval or execution.
final class AgentToolCallReady extends AgentUpdate {
  final String messageId;
  final ToolCall call;
  const AgentToolCallReady({required this.messageId, required this.call});
}

/// A recorded tool outcome, including execution, denial or client resolution.
/// JSON collections are deeply immutable snapshots.
/// Encode custom Dart objects into JSON values before constructing an outcome.
final class AgentToolResult extends AgentUpdate {
  final ToolCall call;
  final Object? result;
  AgentToolResult({required this.call, required Object? result})
    : result = immutableJson({'result': result})['result'];
}

/// Model-reported usage for one invocation.
final class AgentUsage extends AgentUpdate {
  final TokenUsage usage;
  const AgentUsage({required this.usage});
}

/// The committed result of a finished or interrupted run.
final class AgentRunFinished extends AgentUpdate {
  final AgentResult result;
  const AgentRunFinished({required this.result});
}
