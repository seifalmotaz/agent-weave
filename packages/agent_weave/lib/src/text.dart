import 'package:uuid/uuid.dart';
import 'cancellation.dart';
import 'model.dart';
import 'protocol.dart';
import 'result.dart';
import 'runtime.dart';
import 'tool.dart';

/// Run a stateless request with the same tool loop and validation as [AiAgent].
/// For persisted conversations and typed context, use [AiAgent.generate].
Future<AgentResult> generateText({
  required ChatModel model,
  String? prompt,
  Iterable<ChatMessage>? messages,
  String? instructions,
  Iterable<AgentTool<void>> tools = const [],
  int maxSteps = 8,
  int maxOutputTokens = 1024,
  CancellationToken? cancellation,
}) => _generate(
  model: model,
  prompt: prompt,
  messages: messages,
  instructions: instructions,
  tools: tools,
  maxSteps: maxSteps,
  maxOutputTokens: maxOutputTokens,
  cancellation: cancellation,
);

/// Validate provider JSON against [schema] before invoking your Dart decoder.
Future<ObjectResult<T>> generateObject<T>({
  required ChatModel model,
  required JsonObject schema,
  required T Function(Object? json) decode,
  String? prompt,
  Iterable<ChatMessage>? messages,
  String? instructions,
  int maxOutputTokens = 1024,
  CancellationToken? cancellation,
}) async {
  final result = await _generate(
    model: model,
    prompt: prompt,
    messages: messages,
    instructions: instructions,
    outputSchema: schema,
    maxOutputTokens: maxOutputTokens,
    cancellation: cancellation,
  );
  return ObjectResult(value: decode(result.output), generation: result);
}

Future<AgentResult> _generate({
  required ChatModel model,
  String? prompt,
  Iterable<ChatMessage>? messages,
  String? instructions,
  JsonObject? outputSchema,
  Iterable<AgentTool<void>> tools = const [],
  int maxSteps = 8,
  int maxOutputTokens = 1024,
  CancellationToken? cancellation,
}) {
  if ((prompt == null) == (messages == null)) {
    throw ArgumentError('Provide exactly one of prompt or messages.');
  }
  final id = const Uuid().v4;
  final input = messages?.toList() ?? [ChatMessage.user(prompt!, id: id())];
  if (input.isEmpty) throw ArgumentError('Provide at least one message.');
  return AiAgent<void>(
    model: model,
    initialMessages: input,
    instructions: instructions,
    tools: tools,
    outputSchema: outputSchema,
    maxSteps: maxSteps,
    maxOutputTokens: maxOutputTokens,
  ).generate(
    ChatRequest(threadId: id(), runId: id(), messages: const []),
    ownerId: 'stateless',
    context: null,
    cancellation: cancellation,
  );
}
