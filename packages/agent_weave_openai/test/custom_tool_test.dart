import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart';
import 'package:agent_weave_openai/src/custom_definition.dart';
import 'package:agent_weave_openai/src/custom_output.dart';
import 'package:test/test.dart';

void main() {
  OpenAICustomTool<void> tool({
    OpenAIToolNamespace? namespace,
    bool? isAsync,
    List<OpenAICustomAllowedCaller>? callers,
  }) => OpenAICustomTool<void>(
    name: 'execute',
    localName: 'local',
    namespace: namespace,
    bindingId: 'owner',
    description: 'Execute',
    format: OpenAICustomToolFormat.grammar(
      'start: /.+/',
      syntax: OpenAICustomGrammarSyntax.lark,
    ),
    deferLoading: false,
    isAsync: isAsync,
    allowedCallers: callers,
    execute: (input, _) => OpenAICustomToolResult.text(input),
  );
  test(
    'definition retains native options and namespace, input only holds text',
    () {
      final t = tool(
        namespace: OpenAIToolNamespace(name: 'crm', description: 'CRM'),
        isAsync: false,
        callers: [OpenAICustomAllowedCaller.direct],
      );
      expect(t.definition.name, 'local');
      expect(t.definition.bindingId, 'owner');
      expect(t.definition.definition, {
        'type': 'namespace',
        'name': 'crm',
        'description': 'CRM',
        'tools': [
          {
            'type': 'custom',
            'name': 'execute',
            'description': 'Execute',
            'format': {
              'type': 'grammar',
              'definition': 'start: /.+/',
              'syntax': 'lark',
            },
            'defer_loading': false,
            'async': false,
            'allowed_callers': ['direct'],
          },
        ],
      });
      expect(t.definition.inputSchema['required'], ['input']);
      expect(() => tool(isAsync: true), throwsUnsupportedError);
      expect(
        () => tool(callers: [OpenAICustomAllowedCaller.programmatic]),
        throwsUnsupportedError,
      );
      expect(() => tool(callers: []), throwsUnsupportedError);
      expect(OpenAICustomToolFormat.text().toJson(), {'type': 'text'});
      expect(
        OpenAICustomToolFormat.grammar(
          'x',
          syntax: OpenAICustomGrammarSyntax.regex,
        ).toJson()['syntax'],
        'regex',
      );
    },
  );
  test(
    'tool invokes callback with exact input and approved trusted context',
    () async {
      final t = tool();
      final context = ToolContext<void>(
        value: null,
        ownerId: 'o',
        threadId: 't',
        runId: 'r',
        toolCallId: 'c',
        cancellation: CancellationToken(),
      );
      expect(await t.invoke({'input': 'not JSON\n☃'}, context), {
        'output': 'not JSON\n☃',
        'isError': false,
      });
      await expectLater(
        t.invoke({'input': 'x', 'extra': true}, context),
        throwsA(isA<Exception>()),
      );
    },
  );
  test('content options and unknown fields survive immutable round trip', () {
    final raw = <String, Object?>{
      'type': 'input_file',
      'file_data': 'data',
      'file_id': null,
      'file_url': 'url',
      'filename': 'n',
      'detail': 'high',
      'prompt_cache_breakpoint': {'mode': 'explicit', 'ttl': '30m'},
      'future': <String, Object?>{
        'nested': <Object?>[1],
      },
    };
    final result = OpenAICustomToolResult.content([
      OpenAICustomToolContent.text(
        'hello',
        cache: OpenAICustomPromptCacheBreakpoint(ttl: '12h'),
      ),
      OpenAICustomToolContent.image(
        detail: 'original',
        imageUrl: 'url',
        fileId: 'file',
      ),
      OpenAICustomToolContent.fromJson(raw),
    ]);
    (raw['future'] as Map)['nested'] = <Object?>[];
    final wire = result.toJson();
    expect(((wire['output'] as List)[2] as Map)['future'], {
      'nested': [1],
    });
    expect(OpenAICustomToolResult.fromJson(wire).toJson(), wire);
    expect(() => (wire['output'] as List).clear(), throwsUnsupportedError);
    expect(OpenAICustomToolResult.error('declined').toJson(), {
      'output': 'declined',
      'isError': true,
    });
  });
  test('invalid content and results are rejected', () {
    for (final input in <JsonObject>[
      {'type': 'input_image'},
      {'type': 'input_text', 'text': 1},
      {'type': 'input_video'},
      {'type': 'input_file', 'detail': 'original'},
      {
        'type': 'input_text',
        'text': 'x',
        'prompt_cache_breakpoint': {'mode': 'other'},
      },
    ]) {
      expect(
        () => OpenAICustomToolContent.fromJson(input),
        throwsFormatException,
      );
    }
    expect(
      () => OpenAICustomToolResult.fromJson({'output': 'x'}),
      throwsFormatException,
    );
    expect(
      () => OpenAICustomToolResult.fromJson({
        'output': [
          {'type': 'input_video'},
        ],
        'isError': false,
      }),
      throwsFormatException,
    );
  });
  test('call parser accepts completed direct calls only', () {
    final raw = <String, Object?>{
      'type': 'custom_tool_call',
      'id': 'item',
      'call_id': 'call',
      'name': 'execute',
      'input': 'raw',
      'status': 'completed',
      'namespace': 'crm',
      'caller': {'type': 'direct'},
      'async': false,
    };
    final call = OpenAICustomCall.fromJson(raw);
    expect(call.input, 'raw');
    expect(call.namespace, 'crm');
    expect(call.callId, 'call');
    for (final patch in <JsonObject>[
      {'status': 'incomplete'},
      {'async': true},
      {
        'caller': {'type': 'program', 'caller_id': 'p'},
      },
      {'input': 1},
    ]) {
      expect(
        () => OpenAICustomCall.fromJson({...raw, ...patch}),
        throwsFormatException,
      );
    }
  });
  test(
    'approval prevents executor and fallback envelopes distinguish decisions',
    () async {
      var calls = 0;
      final t = OpenAICustomTool<void>(
        name: 'run',
        bindingId: 'account',
        needsApproval: true,
        execute: (_, _) {
          calls++;
          return OpenAICustomToolResult.error('reported');
        },
      );
      ToolContext<void> context(bool approved) => ToolContext<void>(
        value: null,
        ownerId: 'o',
        threadId: 't',
        runId: 'r',
        toolCallId: 'c',
        cancellation: CancellationToken(),
        approved: approved,
      );
      await expectLater(
        t.invoke({'input': 'source'}, context(false)),
        throwsStateError,
      );
      expect(calls, 0);
      expect(await t.invoke({'input': 'source'}, context(true)), {
        'output': 'reported',
        'isError': true,
      });
      expect(calls, 1);
      expect(
        OpenAICustomToolResult.fromJson(
          t.declinedResult(cancelled: false)! as JsonObject,
        ).isError,
        true,
      );
      expect(
        t.declinedResult(cancelled: false),
        isNot(t.declinedResult(cancelled: true)),
      );
      expect(
        OpenAICustomToolResult.fromJson(
          t.skippedResult()! as JsonObject,
        ).isError,
        true,
      );
    },
  );
  test('raw declarations validate known fields before registry use', () {
    const base = <String, Object?>{'type': 'custom', 'name': 'run'};
    for (final patch in <JsonObject>[
      {'format': null},
      {
        'format': {'type': 'other'},
      },
      {
        'format': {'type': 'grammar', 'definition': 1, 'syntax': 'lark'},
      },
      {
        'format': {'type': 'grammar', 'definition': 'x', 'syntax': 'other'},
      },
      {'description': null},
      {'async': null},
      {'defer_loading': 'yes'},
      {'allowed_callers': []},
      {
        'allowed_callers': [null],
      },
      {
        'allowed_callers': ['programmatic'],
      },
      {'async': true},
    ]) {
      final value = {...base, ...patch};
      expect(
        () => validateCustomToolDefinition(value),
        throwsA(anyOf(isA<ArgumentError>(), isA<UnsupportedError>())),
      );
      final model = NativeModelTool(
        name: 'local',
        description: '',
        inputSchema: const {'type': 'object'},
        provider: 'openai.responses',
        bindingId: 'b',
        definition: value,
      );
      expect(
        () => CustomRegistry([model], 'openai.responses'),
        throwsA(anyOf(isA<ArgumentError>(), isA<UnsupportedError>())),
      );
    }
    validateCustomToolDefinition({
      ...base,
      'allowed_callers': null,
      'format': {
        'type': 'grammar',
        'definition': '',
        'syntax': 'regex',
        'future': true,
      },
      'future': {'kept': true},
    });
    expect(OpenAIToolNamespace(name: 'crm', description: '').description, '');
  });
  test('result metadata is explicit, validated and snapshotted', () {
    final caller = <String, Object?>{'type': 'direct'};
    final result = OpenAICustomToolResult.text(
      'result',
      id: 'output-id',
      caller: caller,
    );
    caller['type'] = 'changed';
    expect(result.id, 'output-id');
    expect(result.caller, {'type': 'direct'});
    expect(() => result.caller!['type'] = 'changed', throwsUnsupportedError);
    expect(
      OpenAICustomToolResult.fromJson(result.toJson()).toJson(),
      result.toJson(),
    );
    final nullCaller = OpenAICustomToolResult.fromJson({
      'output': 'x',
      'isError': false,
      'caller': null,
    });
    expect(nullCaller.toJson().containsKey('caller'), true);
    expect(nullCaller.toJson()['caller'], isNull);
    expect(
      OpenAICustomToolResult.error(
        'x',
        id: 'i',
        caller: {'type': 'direct'},
      ).toJson()['id'],
      'i',
    );
    expect(
      OpenAICustomToolResult.content(
        [],
        id: 'i',
        caller: {'type': 'direct'},
      ).toJson()['id'],
      'i',
    );
    for (final patch in <JsonObject>[
      {'id': null},
      {'id': 1},
      {'caller': 'direct'},
      {
        'caller': {'type': 'program', 'caller_id': 'p'},
      },
      {
        'caller': {'type': 'direct', 'extra': true},
      },
      {'call_id': 'forged'},
      {'type': 'custom_tool_call_output'},
    ]) {
      expect(
        () => OpenAICustomToolResult.fromJson({
          'output': 'x',
          'isError': false,
          ...patch,
        }),
        throwsFormatException,
      );
    }
  });
}
