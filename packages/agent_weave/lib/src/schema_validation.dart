/// Backend diagnostic from the installed JSON Schema validator.
///
/// Paths and messages follow that validator's conventions and may contain
/// sensitive schema or input data. Do not expose them to untrusted clients.
final class SchemaValidationIssue {
  final String instancePath;
  final String schemaPath;
  final String message;
  const SchemaValidationIssue({
    required this.instancePath,
    required this.schemaPath,
    required this.message,
  });
}

/// A safe public error with opt-in private validator diagnostics.
final class SchemaValidationException extends FormatException {
  final List<SchemaValidationIssue> issues;
  SchemaValidationException(Iterable<SchemaValidationIssue> issues)
    : issues = List.unmodifiable(issues),
      super('Value does not match the declared JSON Schema.');
}
