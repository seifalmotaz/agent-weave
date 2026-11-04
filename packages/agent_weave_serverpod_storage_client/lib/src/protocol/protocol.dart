/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member
// ignore_for_file: dead_code, unnecessary_type_check

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:serverpod_client/serverpod_client.dart' as _isc;
import 'agent_event.dart' as _ihtx122v;
import 'agent_run.dart' as _iqmrjvou;
import 'agent_thread.dart' as _iri743z8;
export 'agent_event.dart';
export 'agent_run.dart';
export 'agent_thread.dart';
export 'client.dart';

class Protocol extends _isc.SerializationManager
    implements _isc.ProtocolDeserializationProvider {
  Protocol._();

  factory Protocol() => _instance;

  static final Protocol _instance = Protocol._();

  final Set<_isc.SerializationManager> _hostProtocols = {};

  @override
  _isc.ProtocolDeserialization get deserializationMetadata =>
      _isc.ProtocolDeserialization.cached(
        this,
        types: const [
          _isc.getType<_ihtx122v.AgentStoredEvent>,
          _isc.getType<_iqmrjvou.AgentRun>,
          _isc.getType<_iri743z8.AgentThread>,
          _isc.getType<_ihtx122v.AgentStoredEvent?>,
          _isc.getType<_iqmrjvou.AgentRun?>,
          _isc.getType<_iri743z8.AgentThread?>,
        ],
        modules: const [],
        classNames: const ['AgentStoredEvent', 'AgentRun', 'AgentThread'],
        classNamePrefix: 'agent_weave_serverpod_storage.',
      );

  void registerHostProtocol(
    String projectName,
    _isc.SerializationManager protocol,
  ) {
    _hostProtocols.add(protocol);
  }

  static String? getClassNameFromObjectJson(dynamic data) =>
      _isc.ProtocolDeserialization.normalizeClassName(
        _isc.ProtocolDeserialization.readClassName(data),
        prefix: 'agent_weave_serverpod_storage.',
      );

  @override
  T deserialize<T>(dynamic data, [Type? t]) {
    t ??= T;
    final rawDataClassName = _isc.ProtocolDeserialization.readClassName(data);
    final dataClassName = _isc.ProtocolDeserialization.normalizeClassName(
      rawDataClassName,
      prefix: 'agent_weave_serverpod_storage.',
    );
    if (dataClassName != null && dataClassName != getClassNameForType(t)) {
      try {
        return deserializeByClassName({
          'className': dataClassName,
          'data': data,
        });
      } on _isc.DeserializationClassNameNotFoundException catch (_) {
        // If the className is not recognized (e.g., older client receiving
        // data with a new subtype), fall back to deserializing without the
        // className, using the expected type T.
      }
    }

    if (t == _ihtx122v.AgentStoredEvent) {
      return _ihtx122v.AgentStoredEvent.fromJson(data) as T;
    }
    if (t == _iqmrjvou.AgentRun) {
      return _iqmrjvou.AgentRun.fromJson(data) as T;
    }
    if (t == _iri743z8.AgentThread) {
      return _iri743z8.AgentThread.fromJson(data) as T;
    }
    if (t == _isc.getType<_ihtx122v.AgentStoredEvent?>()) {
      return (data != null ? _ihtx122v.AgentStoredEvent.fromJson(data) : null)
          as T;
    }
    if (t == _isc.getType<_iqmrjvou.AgentRun?>()) {
      return (data != null ? _iqmrjvou.AgentRun.fromJson(data) : null) as T;
    }
    if (t == _isc.getType<_iri743z8.AgentThread?>()) {
      return (data != null ? _iri743z8.AgentThread.fromJson(data) : null) as T;
    }
    return super.deserialize<T>(data, t);
  }

  static String? getClassNameForType(Type type) {
    return switch (type) {
      _ihtx122v.AgentStoredEvent => 'AgentStoredEvent',
      _iqmrjvou.AgentRun => 'AgentRun',
      _iri743z8.AgentThread => 'AgentThread',
      _ => null,
    };
  }

  @override
  String? getClassNameForObject(Object? data) {
    String? className = super.getClassNameForObject(data);
    if (className != null) return className;

    if (data is Map<String, dynamic> && data['__className__'] is String) {
      return (data['__className__'] as String).replaceFirst(
        'agent_weave_serverpod_storage.',
        '',
      );
    }

    switch (data) {
      case _ihtx122v.AgentStoredEvent():
        return 'AgentStoredEvent';
      case _iqmrjvou.AgentRun():
        return 'AgentRun';
      case _iri743z8.AgentThread():
        return 'AgentThread';
    }
    return null;
  }

  @override
  dynamic deserializeByClassName(Map<String, dynamic> data) {
    var dataClassName = data['className'];
    if (dataClassName is! String) {
      return super.deserializeByClassName(data);
    }
    if (dataClassName == 'AgentStoredEvent') {
      return deserialize<_ihtx122v.AgentStoredEvent>(data['data']);
    }
    if (dataClassName == 'AgentRun') {
      return deserialize<_iqmrjvou.AgentRun>(data['data']);
    }
    if (dataClassName == 'AgentThread') {
      return deserialize<_iri743z8.AgentThread>(data['data']);
    }
    return super.deserializeByClassName(data);
  }

  @override
  Object? dynamicFieldToJson(Object? object, {bool forProtocol = false}) {
    if ((object is List || object is Set || object is Map) ||
        getClassNameForObject(object) != null) {
      return super.dynamicFieldToJson(object, forProtocol: forProtocol);
    }
    for (final protocol in _hostProtocols) {
      final className = protocol.getClassNameForObject(object);
      if (className == null) continue;
      final host = protocol.getModuleName();
      final wrapped = {
        'className': className.contains('.') ? className : '$host.$className',
        'data': object,
      };
      return forProtocol
          ? _isc.SerializationManager.toEncodableForProtocol(wrapped)
          : _isc.SerializationManager.toEncodable(wrapped);
    }
    return super.dynamicFieldToJson(object, forProtocol: forProtocol);
  }

  @override
  dynamic deserializeDynamicFieldValue(Object? value) {
    if (value == null) return null;
    if (value is! Map<String, dynamic> || value['className'] is! String) {
      throw FormatException(
        'Dynamic fields are encoded as a Map with className and data, but got '
        '${value.runtimeType} instead.',
      );
    }
    final className = value['className'] as String;
    for (final protocol in _hostProtocols) {
      final host = protocol.getModuleName();
      final hostPrefix = '$host.';
      if (className.startsWith(hostPrefix)) {
        final strippedClassName = className.substring(hostPrefix.length);
        if (strippedClassName.contains('.')) {
          throw FormatException(
            'Dynamic field className must not use multiple prefixes: $className',
          );
        }
        final hostData = Map<String, dynamic>.from(value);
        hostData['className'] = strippedClassName;
        return protocol.deserializeByClassName(hostData);
      }
    }
    if (className.contains('.')) {
      for (final protocol in _hostProtocols) {
        try {
          return protocol.deserializeByClassName(value);
        } on _isc.DeserializationClassNameNotFoundException catch (_) {}
      }
    }
    return deserializeByClassName(value);
  }

  @override
  String getModuleName() => 'agent_weave_serverpod_storage';

  /// Maps any `Record`s known to this [Protocol] to their JSON representation
  ///
  /// Throws in case the record type is not known.
  ///
  /// This method will return `null` (only) for `null` inputs.
  Map<String, dynamic>? mapRecordToJson(Record? record) {
    if (record == null) {
      return null;
    }
    throw Exception('Unsupported record type ${record.runtimeType}');
  }
}
