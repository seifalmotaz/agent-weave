/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod_client/serverpod_client.dart' as _isc;

abstract class AgentRun
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  AgentRun._({
    this.id,
    required this.ownerId,
    required this.threadId,
    required this.runId,
  });

  factory AgentRun({
    int? id,
    required String ownerId,
    required String threadId,
    required String runId,
  }) = _AgentRunImpl;

  factory AgentRun.fromJson(Map<String, dynamic> jsonSerialization) {
    return AgentRun(
      id: jsonSerialization['id'] as int?,
      ownerId: jsonSerialization['ownerId'] as String,
      threadId: jsonSerialization['threadId'] as String,
      runId: jsonSerialization['runId'] as String,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  String ownerId;

  String threadId;

  String runId;

  /// Returns a shallow copy of this [AgentRun]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  AgentRun copyWith({
    int? id,
    String? ownerId,
    String? threadId,
    String? runId,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentRun',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      'runId': runId,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentRun',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      'runId': runId,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AgentRunImpl extends AgentRun {
  _AgentRunImpl({
    int? id,
    required String ownerId,
    required String threadId,
    required String runId,
  }) : super._(id: id, ownerId: ownerId, threadId: threadId, runId: runId);

  /// Returns a shallow copy of this [AgentRun]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  AgentRun copyWith({
    Object? id = _Undefined,
    String? ownerId,
    String? threadId,
    String? runId,
  }) {
    return AgentRun(
      id: id is int? ? id : this.id,
      ownerId: ownerId ?? this.ownerId,
      threadId: threadId ?? this.threadId,
      runId: runId ?? this.runId,
    );
  }
}
