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
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart'
    as _itt1u4oh;
import 'package:serverpod/serverpod.dart' as _is;
import '../ai/ai_endpoint.dart' as _i4qeki52;

class Endpoints extends _is.EndpointDispatch {
  @override
  void initializeEndpoints(_is.Server server) {
    var endpoints = <String, _is.Endpoint>{
      'ai': _i4qeki52.AiEndpoint()
        ..initialize(
          server,
          'ai',
          null,
        ),
    };
    connectors['ai'] = _is.EndpointConnector(
      name: 'ai',
      endpoint: endpoints['ai']!,
      methodConnectors: {
        'history': _is.MethodConnector(
          name: 'history',
          params: {
            'threadId': _is.ParameterDescription(
              name: 'threadId',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
              ) async => (endpoints['ai'] as _i4qeki52.AiEndpoint).history(
                session,
                params['threadId'],
              ),
        ),
        'chat': _is.MethodStreamConnector(
          name: 'chat',
          params: {
            'requestJson': _is.ParameterDescription(
              name: 'requestJson',
              type: _is.getType<String>(),
              nullable: false,
            ),
          },
          streamParams: {},
          returnType: _is.MethodStreamReturnType.streamType,
          call:
              (
                _is.Session session,
                Map<String, dynamic> params,
                Map<String, Stream> streamParams,
              ) => (endpoints['ai'] as _i4qeki52.AiEndpoint).chat(
                session,
                params['requestJson'],
              ),
        ),
      },
    );
    modules['agent_weave_serverpod_storage'] = _itt1u4oh.Endpoints()
      ..initializeEndpoints(server);
  }
}
