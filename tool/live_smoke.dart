import 'dart:convert';
import 'dart:io';
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:http/http.dart' as http;
import 'live_budget.dart';

/// Explicitly run with OPENAI_API_KEY. Never runs as part of normal CI.
Future<void> main() async {
  final key = Platform.environment['OPENAI_API_KEY'];
  if (key == null || key.isEmpty) {
    throw StateError('Set OPENAI_API_KEY in the environment.');
  }
  final ledger = File('.dart_tool/live-budget.json');
  final client = api.OpenAIClient(
    config: api.OpenAIConfig(
      authProvider: api.ApiKeyProvider(key),
      timeout: const Duration(seconds: 40),
      retryPolicy: const api.RetryPolicy(maxRetries: 0),
    ),
    httpClient: BudgetClient(http.Client(), ledger),
    streamClientFactory: () => BudgetClient(http.Client(), ledger),
  );
  final responses = api.OpenAIResponsesModel(
    client: client,
    model: 'gpt-5.4-nano',
    configure: (request) => request.copyWith(
      reasoning: const api.ReasoningConfig(effort: api.ReasoningEffort.none),
    ),
  );
  final chat = api.OpenAIChatModel(
    client: client,
    model: 'gpt-5.4-nano',
    configure: (request) => api.ChatCompletionCreateRequest.fromJson({
      ...request.toJson(),
      'reasoning_effort': 'none',
    }),
  );
  final results = <String, Object?>{};
  try {
    for (final (name, model) in [('responses', responses), ('chat', chat)]) {
      final events = await AiAgent<void>(model: model, maxOutputTokens: 128)
          .run(
            ChatRequest(
              threadId: name,
              runId: name,
              messages: [
                ChatMessage.user('Reply with exactly OK.', id: 'user'),
              ],
            ),
            ownerId: 'live-smoke',
            context: null,
          )
          .toList();
      _verify(
        events.any((e) => e.type == 'TEXT_MESSAGE_CONTENT'),
        '$name text',
      );
      _verify(events.last.type == 'RUN_FINISHED', '$name completion');
      results[name] = _usage(events);
    }
    final structured =
        await AiAgent<void>(
              model: responses,
              maxOutputTokens: 128,
              outputSchema: const {
                'type': 'object',
                'properties': {
                  'answer': {'type': 'integer'},
                },
                'required': ['answer'],
                'additionalProperties': false,
              },
            )
            .run(
              ChatRequest(
                threadId: 'structured',
                runId: 'structured',
                messages: [
                  ChatMessage.user('Return answer equal to 42.', id: 'user'),
                ],
              ),
              ownerId: 'live-smoke',
              context: null,
            )
            .toList();
    _verify(structured.last.type == 'RUN_FINISHED', 'structured output');
    results['structured'] = _usage(structured);
    var called = false;
    final tools =
        await AiAgent<void>(
              model: responses,
              maxOutputTokens: 128,
              tools: [
                Tool<int, int, void>(
                  name: 'double',
                  description: 'Double a number',
                  inputSchema: const {
                    'type': 'object',
                    'properties': {
                      'n': {'type': 'integer'},
                    },
                    'required': ['n'],
                    'additionalProperties': false,
                  },
                  outputSchema: const {'type': 'integer'},
                  decode: (json) => json['n'] as int,
                  encode: (value) => value,
                  execute: (n, context) {
                    called = true;
                    return n * 2;
                  },
                ),
              ],
              instructions:
                  'Always call double to answer arithmetic. After its result, reply briefly.',
            )
            .run(
              ChatRequest(
                threadId: 'tool',
                runId: 'tool',
                messages: [
                  ChatMessage.user('Use double with n=2.', id: 'user'),
                ],
              ),
              ownerId: 'live-smoke',
              context: null,
            )
            .toList();
    _verify(called && tools.last.type == 'RUN_FINISHED', 'tool execution');
    results['tools'] = _usage(tools);
    final embedding = await api.OpenAIEmbeddingModel(client).embed(
      api.EmbeddingRequest(
        model: 'text-embedding-3-small',
        input: api.EmbeddingInput.text('Hello'),
        dimensions: 8,
      ),
    );
    _verify(
      embedding.data.single.embedding.length == 8,
      'embedding dimensions',
    );
    results['embedding'] = 'passed';
    final report = {
      'status': 'passed',
      'checks': results,
      'budget': jsonDecode(ledger.readAsStringSync()),
    };
    File(
      '.dart_tool/live-report.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } catch (error) {
    stderr.writeln(
      'Live smoke failed: ${error.runtimeType}. No credential or provider body logged.',
    );
    exitCode = 1;
  } finally {
    client.close();
  }
}

void _verify(bool condition, String name) {
  if (!condition) throw StateError('Live check failed: $name');
}

List<Object?> _usage(List<AgentEvent> events) => [
  for (final event in events)
    if (event.type == 'CUSTOM' && event.json['name'] == 'agent_weave:usage')
      event.json['value'],
];
