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
import 'dart:async' as _ida;
import 'package:agent_weave_serverpod_storage_client/agent_weave_serverpod_storage_client.dart'
    as _imhkuxib;
import 'package:http/http.dart' as _i85jenna;
import 'package:serverpod_client/serverpod_client.dart' as _isc;
import 'protocol.dart' as _il2as5qe;

/// Native Serverpod streaming, usable through the generated Dart client.
/// {@category Endpoint}
class EndpointAi extends _isc.EndpointRef {
  EndpointAi(_isc.EndpointCaller caller) : super(caller);

  @override
  String get name => 'ai';

  _ida.Stream<String> chat(String requestJson) =>
      caller.callStreamingServerEndpoint<_ida.Stream<String>, String>(
        'ai',
        'chat',
        {'requestJson': requestJson},
        {},
      );

  _ida.Future<String> history(String threadId) =>
      caller.callServerEndpoint<String>(
        'ai',
        'history',
        {'threadId': threadId},
      );
}

class Modules {
  Modules(Client client) {
    agent_weave_storage = _imhkuxib.Caller(client);
  }

  late final _imhkuxib.Caller agent_weave_storage;
}

class Client extends _isc.ServerpodClientShared {
  Client(
    String host, {
    dynamic securityContext,
    Duration? streamingConnectionTimeout,
    Duration? connectionTimeout,
    Function(
      _isc.MethodCallContext,
      Object,
      StackTrace,
    )?
    onFailedCall,
    Function(_isc.MethodCallContext)? onSucceededCall,
    bool? disconnectStreamsOnLostInternetConnection,
    _i85jenna.Client? httpClientOverride,
  }) : super(
         host,
         _il2as5qe.Protocol(),
         securityContext: securityContext,
         streamingConnectionTimeout: streamingConnectionTimeout,
         connectionTimeout: connectionTimeout,
         onFailedCall: onFailedCall,
         onSucceededCall: onSucceededCall,
         disconnectStreamsOnLostInternetConnection:
             disconnectStreamsOnLostInternetConnection,
         httpClientOverride: httpClientOverride,
       ) {
    ai = EndpointAi(this);
    modules = Modules(this);
  }

  late final EndpointAi ai;

  late final Modules modules;

  @override
  Map<String, _isc.EndpointRef> get endpointRefLookup => {'ai': ai};

  @override
  Map<String, _isc.ModuleEndpointCaller> get moduleLookup => {
    'agent_weave_storage': modules.agent_weave_storage,
  };
}
