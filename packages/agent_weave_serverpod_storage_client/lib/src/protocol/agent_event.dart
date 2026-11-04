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

abstract class AgentStoredEvent
    implements _isc.SerializableModel, _isc.ProtocolSerialization {
  AgentStoredEvent._({
    this.id,
    required this.ownerId,
    required this.threadId,
    required this.runId,
    required this.sequence,
    required this.eventJson,
  });

  factory AgentStoredEvent({
    int? id,
    required String ownerId,
    required String threadId,
    required String runId,
    required int sequence,
    required String eventJson,
  }) = _AgentStoredEventImpl;

  factory AgentStoredEvent.fromJson(Map<String, dynamic> jsonSerialization) {
    return AgentStoredEvent(
      id: jsonSerialization['id'] as int?,
      ownerId: jsonSerialization['ownerId'] as String,
      threadId: jsonSerialization['threadId'] as String,
      runId: jsonSerialization['runId'] as String,
      sequence: jsonSerialization['sequence'] as int,
      eventJson: jsonSerialization['eventJson'] as String,
    );
  }

  /// The database id, set if the object has been inserted into the
  /// database or if it has been fetched from the database. Otherwise,
  /// the id will be null.
  int? id;

  String ownerId;

  String threadId;

  String runId;

  int sequence;

  String eventJson;

  /// Returns a shallow copy of this [AgentStoredEvent]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  AgentStoredEvent copyWith({
    int? id,
    String? ownerId,
    String? threadId,
    String? runId,
    int? sequence,
    String? eventJson,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentStoredEvent',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      'runId': runId,
      'sequence': sequence,
      'eventJson': eventJson,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentStoredEvent',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      'runId': runId,
      'sequence': sequence,
      'eventJson': eventJson,
    };
  }

  @override
  String toString() {
    return _isc.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AgentStoredEventImpl extends AgentStoredEvent {
  _AgentStoredEventImpl({
    int? id,
    required String ownerId,
    required String threadId,
    required String runId,
    required int sequence,
    required String eventJson,
  }) : super._(
         id: id,
         ownerId: ownerId,
         threadId: threadId,
         runId: runId,
         sequence: sequence,
         eventJson: eventJson,
       );

  /// Returns a shallow copy of this [AgentStoredEvent]
  /// with some or all fields replaced by the given arguments.
  @_isc.useResult
  @override
  AgentStoredEvent copyWith({
    Object? id = _Undefined,
    String? ownerId,
    String? threadId,
    String? runId,
    int? sequence,
    String? eventJson,
  }) {
    return AgentStoredEvent(
      id: id is int? ? id : this.id,
      ownerId: ownerId ?? this.ownerId,
      threadId: threadId ?? this.threadId,
      runId: runId ?? this.runId,
      sequence: sequence ?? this.sequence,
      eventJson: eventJson ?? this.eventJson,
    );
  }
}
