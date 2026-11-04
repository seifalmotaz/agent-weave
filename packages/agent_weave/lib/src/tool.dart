import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:json_schema/json_schema.dart';
import 'cancellation.dart';
import 'model.dart';

final class ToolContext<C> {
  final C value;
  final String ownerId;
  final String threadId;
  final String runId;

  /// Use this key to deduplicate external effects in your own service.
  final String toolCallId;
  final CancellationToken cancellation;
  const ToolContext({
    required this.value,
    required this.ownerId,
    required this.threadId,
    required this.runId,
    required this.toolCallId,
    required this.cancellation,
  });

  /// Stable across approval continuations; isolated across owners and threads.
  String get idempotencyKey => sha256
      .convert(utf8.encode(jsonEncode([ownerId, threadId, toolCallId])))
      .toString();
}

/// Public contract for heterogeneous collections of typed tools.
abstract interface class AgentTool<C> {
  ModelTool get definition;
  JsonObject? get outputSchema;
  bool get needsApproval;
  bool get clientExecuted;
  Future<Object?> invoke(JsonObject input, ToolContext<C> context);
}

final class Tool<I, O, C> implements AgentTool<C> {
  @override
  final ModelTool definition;
  @override
  final JsonObject? outputSchema;
  @override
  final bool needsApproval;
  @override
  final bool clientExecuted = false;
  final I Function(JsonObject) decode;
  final Object? Function(O) encode;
  final FutureOr<O> Function(I, ToolContext<C>) execute;

  Tool({
    required String name,
    required String description,
    required JsonObject inputSchema,
    JsonObject? outputSchema,
    this.needsApproval = false,
    required this.decode,
    required this.encode,
    required this.execute,
  }) : definition = ModelTool(
         name: name,
         description: description,
         inputSchema: immutableJson(inputSchema),
       ),
       outputSchema = outputSchema == null
           ? null
           : immutableJson(outputSchema) {
    validateToolDefinition(definition, this.outputSchema);
  }

  @override
  Future<Object?> invoke(JsonObject input, ToolContext<C> context) async {
    context.cancellation.throwIfCancelled();
    validateSchema(definition.inputSchema, input);
    final result = encode(await execute(decode(input), context));
    if (outputSchema case final schema?) validateSchema(schema, result);
    return result;
  }
}

final class ClientTool<C> implements AgentTool<C> {
  @override
  final ModelTool definition;
  @override
  final JsonObject? outputSchema;
  @override
  final bool needsApproval = false;
  @override
  final bool clientExecuted = true;
  const ClientTool({required this.definition, this.outputSchema});
  @override
  Future<Object?> invoke(JsonObject input, ToolContext<C> context) =>
      throw StateError('Client tools execute on the client.');
}

void validateSchema(JsonObject schema, Object? value) {
  if (!JsonSchema.create(schema).validate(value).isValid) {
    throw const FormatException(
      'Value does not match the declared JSON Schema.',
    );
  }
}

/// Validate declarations before a model request can be submitted.
void validateToolDefinition(ModelTool definition, JsonObject? outputSchema) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(definition.name)) {
    throw ArgumentError.value(definition.name, 'name', 'Invalid tool name');
  }
  JsonSchema.create(definition.inputSchema);
  if (outputSchema != null) JsonSchema.create(outputSchema);
}
