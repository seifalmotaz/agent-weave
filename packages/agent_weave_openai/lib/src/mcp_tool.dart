import 'dart:async';
import 'dart:convert';

import 'package:agent_weave/agent_weave.dart';
import 'package:openai_dart/openai_dart.dart' as api;

/// Credentials resolved for each request. Do not put secrets in other options.
final class OpenAIMcpCredentials {
  final String? authorization;
  final Map<String, String> headers;

  OpenAIMcpCredentials({
    this.authorization,
    Map<String, String> headers = const {},
  }) : headers = Map.unmodifiable(headers);
}

/// Provider-executed MCP configuration with separately resolved credentials.
final class OpenAIMcpTool {
  final JsonObject definition;
  final JsonObject contract;
  final FutureOr<OpenAIMcpCredentials> Function()? _credentials;

  factory OpenAIMcpTool(
    api.McpTool tool, {
    String? credentialBindingId,
    FutureOr<OpenAIMcpCredentials> Function()? credentials,
  }) => OpenAIMcpTool.fromJson(
    tool.toJson(),
    credentialBindingId: credentialBindingId,
    credentials: credentials,
  );

  factory OpenAIMcpTool.fromJson(
    JsonObject input, {
    String? credentialBindingId,
    FutureOr<OpenAIMcpCredentials> Function()? credentials,
  }) {
    final json = jsonDecode(jsonEncode(input)) as JsonObject;
    if (json['type'] != 'mcp' || !_nonempty(json['server_label'])) {
      throw ArgumentError('MCP requires type mcp and a nonempty server label.');
    }
    final addresses = ['server_url', 'connector_id', 'tunnel_id'];
    if (addresses.where((key) => json[key] != null).length != 1 ||
        addresses.any((key) => json[key] != null && !_nonempty(json[key]))) {
      throw ArgumentError('MCP requires exactly one nonempty server address.');
    }
    final serverUrl = json['server_url'];
    if (serverUrl != null) {
      final uri = Uri.tryParse(serverUrl as String);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          uri.authority.contains('@') ||
          uri.hasFragment ||
          serverUrl.contains(RegExp(r'\s'))) {
        throw ArgumentError('Invalid MCP server URL.');
      }
    }
    if (json['server_description'] != null &&
        json['server_description'] is! String) {
      throw ArgumentError('Invalid server_description.');
    }
    if (json['defer_loading'] != null && json['defer_loading'] is! bool) {
      throw ArgumentError('Invalid defer_loading.');
    }
    if (json['allowed_callers'] != null &&
        (!_stringList(json['allowed_callers']) ||
            (json['allowed_callers'] as List).isEmpty ||
            (json['allowed_callers'] as List).any(
              (value) => value != 'direct' && value != 'programmatic',
            ))) {
      throw ArgumentError('Invalid allowed_callers.');
    }
    final allowed = json['allowed_tools'];
    if (allowed != null && !_stringList(allowed) && !_filter(allowed)) {
      throw ArgumentError('Invalid allowed_tools.');
    }
    final approval = json['require_approval'];
    if (approval != null &&
        !(approval is String &&
            (approval == 'always' || approval == 'never')) &&
        !(approval is Map &&
            (approval['always'] == null || _filter(approval['always'])) &&
            (approval['never'] == null || _filter(approval['never'])))) {
      throw ArgumentError('Invalid require_approval.');
    }
    final authorization = json.remove('authorization');
    final headers = json.remove('headers');
    if ((authorization != null && authorization is! String) ||
        (headers != null &&
            (headers is! Map ||
                headers.entries.any(
                  (entry) => entry.key is! String || entry.value is! String,
                )))) {
      throw ArgumentError('Invalid MCP credentials.');
    }
    final hasLiteral = authorization != null || headers != null;
    if (hasLiteral && credentials != null) {
      throw ArgumentError('Use literal credentials or a resolver, not both.');
    }
    if ((hasLiteral || credentials != null) &&
        !_nonempty(credentialBindingId)) {
      throw ArgumentError('Credentials require a stable credentialBindingId.');
    }
    if (credentialBindingId != null && !_nonempty(credentialBindingId)) {
      throw ArgumentError('credentialBindingId must be nonempty.');
    }
    final literal = hasLiteral
        ? OpenAIMcpCredentials(
            authorization: authorization as String?,
            headers: headers == null
                ? const {}
                : Map<String, String>.from(headers as Map),
          )
        : null;
    final definition = immutableJson(json);
    return OpenAIMcpTool._(
      definition,
      immutableJson({
        'version': 1,
        'definition': definition,
        'credential_binding_id': credentialBindingId,
      }),
      credentials ?? (literal == null ? null : () => literal),
    );
  }

  OpenAIMcpTool._(this.definition, this.contract, this._credentials);

  Future<JsonObject> resolveDefinition() async {
    final value = await _credentials?.call();
    return {
      ...definition,
      if (value?.authorization != null) 'authorization': value!.authorization,
      if (value != null && value.headers.isNotEmpty) 'headers': value.headers,
    };
  }
}

bool _nonempty(Object? value) => value is String && value.trim().isNotEmpty;
bool _stringList(Object? value) =>
    value is List && value.every((item) => item is String);
bool _filter(Object? value) =>
    value is Map &&
    (value['tool_names'] == null || _stringList(value['tool_names'])) &&
    (value['read_only'] == null || value['read_only'] is bool);
