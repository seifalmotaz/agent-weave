import 'dart:convert';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;

void main() {
  final tool = api.OpenAICustomTool<void>(
    name: 'execute',
    localName: 'local',
    bindingId: 'fixture',
    description: 'Execute',
    namespace: api.OpenAIToolNamespace(name: 'crm', description: 'CRM'),
    format: api.OpenAICustomToolFormat.grammar(
      'start: /x/',
      syntax: api.OpenAICustomGrammarSyntax.lark,
    ),
    deferLoading: false,
    isAsync: false,
    allowedCallers: [api.OpenAICustomAllowedCaller.direct],
    execute: (input, _) => api.OpenAICustomToolResult.text(input),
  );
  final call = api.OpenAICustomCall.fromJson({
    'type': 'custom_tool_call',
    'id': 'item',
    'call_id': 'call',
    'name': 'execute',
    'input': 'raw',
    'status': 'completed',
    'namespace': 'crm',
    'async': false,
    'caller': {'type': 'direct'},
    'created_by': 'actor',
  });
  final cache = api.OpenAICustomPromptCacheBreakpoint(ttl: '30m');
  final blocks = [
    api.OpenAICustomToolContent.text('text', cache: cache),
    api.OpenAICustomToolContent.image(
      detail: 'original',
      fileId: 'id',
      imageUrl: 'url',
      cache: cache,
    ),
    api.OpenAICustomToolContent.file(
      detail: 'high',
      fileData: 'data',
      fileId: 'id',
      fileUrl: 'url',
      filename: 'name',
      cache: cache,
    ),
  ];
  Object? choice(Object value) => api.ResponsesProtocolModel.native(
    model: 'fixture',
    toolChoice: value,
    transport: (_, _) => const Stream.empty(),
  ).continuationContract['toolChoice'];
  final result = api.OpenAICustomToolResult.text(
    'raw result',
    id: 'out',
    caller: {'type': 'direct'},
  ).toJson();
  print(
    jsonEncode({
      'namespace': tool.definition.definition,
      'customChoice': choice({'type': 'custom', 'name': 'execute'}),
      'allowedChoice': choice({
        'type': 'allowed_tools',
        'mode': 'required',
        'tools': [
          {'type': 'custom', 'name': 'execute'},
        ],
      }),
      'textFormat': api.OpenAICustomToolFormat.text().toJson(),
      'regexFormat': api.OpenAICustomToolFormat.grammar(
        'x',
        syntax: api.OpenAICustomGrammarSyntax.regex,
      ).toJson(),
      'call': call.raw,
      'outputItem': api.CustomToolCallOutputInputItem.fromJson({
        'type': 'custom_tool_call_output',
        'call_id': 'call',
        'output': result['output'],
        'id': result['id'],
        'caller': result['caller'],
      }).toJson(),
      'textResult': result,
      'contentResult': api.OpenAICustomToolResult.content(blocks).toJson(),
      'errorResult': api.OpenAICustomToolResult.error('known error').toJson(),
    }),
  );
}
