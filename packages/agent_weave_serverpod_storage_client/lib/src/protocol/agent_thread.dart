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

abstract class AgentThread
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  AgentThread._({
    this.id,
    required this.ownerId,
    required this.threadId,
    this.activeRun,
    required this.stateJson,
  });

  factory AgentThread({
    int? id,
    required String ownerId,
    required String threadId,
    String? activeRun,
    required String stateJson,
  }) = _AgentThreadImpl;

  factory AgentThread.fromJson(Map<String, dynamic> jsonSerialization) {
    return AgentThread(
      id: jsonSerialization['id'] as int?,
      ownerId: jsonSerialization['ownerId'] as String,
      threadId: jsonSerialization['threadId'] as String,
      activeRun: jsonSerialization['activeRun'] as String?,
      stateJson: jsonSerialization['stateJson'] as String,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  String ownerId;

  String threadId;

  String? activeRun;

  String stateJson;

  /// Returns a shallow copy of this [AgentThread]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  AgentThread copyWith({
    int? id,
    String? ownerId,
    String? threadId,
    String? activeRun,
    String? stateJson,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentThread',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      if (activeRun != null) 'activeRun': activeRun,
      'stateJson': stateJson,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentThread',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      if (activeRun != null) 'activeRun': activeRun,
      'stateJson': stateJson,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AgentThreadImpl extends AgentThread {
  _AgentThreadImpl({
    int? id,
    required String ownerId,
    required String threadId,
    String? activeRun,
    required String stateJson,
  }) : super._(
         id: id,
         ownerId: ownerId,
         threadId: threadId,
         activeRun: activeRun,
         stateJson: stateJson,
       );

  /// Returns a shallow copy of this [AgentThread]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  AgentThread copyWith({
    Object? id = _Undefined,
    String? ownerId,
    String? threadId,
    Object? activeRun = _Undefined,
    String? stateJson,
  }) {
    return AgentThread(
      id: id is int? ? id : this.id,
      ownerId: ownerId ?? this.ownerId,
      threadId: threadId ?? this.threadId,
      activeRun: activeRun is String? ? activeRun : this.activeRun,
      stateJson: stateJson ?? this.stateJson,
    );
  }
}
