import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:json_schema/json_schema.dart';
import 'cancellation.dart';
import 'model.dart';
import 'schema_validation.dart';

final class ToolContext<C> {
  final C value;
  final String ownerId;
  final String threadId;
  final String runId;

  /// Use this key to deduplicate external effects in your own service.
  final String toolCallId;
  final CancellationToken cancellation;
  final bool approved;
  const ToolContext({
    required this.value,
    required this.ownerId,
    required this.threadId,
    required this.runId,
    required this.toolCallId,
    required this.cancellation,
    this.approved = false,
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

/// A native tool whose failure stops later executors in the same model turn.
/// Skipped results must be valid provider results and must not execute actions.
abstract interface class SequentialNativeTool<C> implements AgentTool<C> {
  @override
  NativeModelTool get definition;
  bool isFailure(Object? result);
  Object? skippedResult();
}

/// A native tool with declared, provider-valid denial and skipped outcomes.
/// These factories must be pure. Their values are bound into approval contracts.
/// Exceptions and uncertain execution still close native continuations.
abstract interface class NativeToolFallback<C> implements AgentTool<C> {
  @override
  NativeModelTool get definition;
  Object? declinedResult({required bool cancelled});
  Object? skippedResult();
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
  final result = JsonSchema.create(schema).validate(value);
  if (!result.isValid) {
    throw SchemaValidationException([
      for (final error in result.errors)
        SchemaValidationIssue(
          instancePath: error.instancePath,
          schemaPath: error.schemaPath,
          message: error.message,
        ),
    ]);
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
