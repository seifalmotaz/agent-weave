import 'package:agent_weave/agent_weave.dart';
import 'package:tanstack_ai_dart/tanstack_ai_dart.dart';

/// Owner-visible remote tool request, independent of private provider IDs.
/// Obtain a new snapshot from the current ChatClient state after reconnecting.
final class ProviderApproval {
  final ChatInterrupt _interrupt;
  final String provider;
  final String serverLabel;
  final String toolName;
  final String toolCallId;
  final JsonObject arguments;

  ProviderApproval._(
    this._interrupt, {
    required this.provider,
    required this.serverLabel,
    required this.toolName,
    required this.toolCallId,
    required JsonObject arguments,
  }) : arguments = immutableJson(arguments);

  String get id => _interrupt.id;
  bool get canResolve => _interrupt.canResolve;

  /// Stage approval. Observe ChatClient.states for the resumed run's outcome.
  Future<void> approve({String? reason}) => _decide(true, reason);

  /// Stage denial; the provider can continue to explain or propose another call.
  Future<void> reject({String? reason}) => _decide(false, reason);

  Future<void> _decide(bool approved, String? reason) async {
    if (!canResolve) {
      throw StateError('This provider approval cannot be resolved.');
    }
    await _interrupt.resolveInterrupt({
      'approved': approved,
      'reason': ?reason,
    });
  }
}

extension ProviderApprovalInterrupt on ChatInterrupt {
  /// Typed access for AgentWeave provider approvals; null for other interrupts.
  /// Malformed declared metadata throws without including its private contents.
  ProviderApproval? get providerApproval {
    final metadata = this.metadata;
    if (metadata == null || !metadata.containsKey('providerApproval')) {
      return null;
    }
    final details = metadata['providerApproval'];
    final arguments = input;
    if (details is! Map<String, Object?> ||
        arguments is! Map<String, Object?> ||
        (kind != 'generic' && kind != 'unbound')) {
      throw const FormatException('Invalid provider approval metadata.');
    }
    return ProviderApproval._(
      this,
      provider: _identifier(details['provider']),
      serverLabel: _identifier(details['serverLabel']),
      toolName: _identifier(metadata['toolName'] ?? toolName),
      toolCallId: _identifier(toolCallId),
      arguments: arguments,
    );
  }
}

String _identifier(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid provider approval metadata.');
  }
  return value;
}
