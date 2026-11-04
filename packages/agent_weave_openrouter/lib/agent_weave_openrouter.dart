/// OpenRouter Chat Completions for AgentWeave.
library;

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:http/http.dart' as http;

export 'package:agent_weave_openai/agent_weave_openai.dart'
    show
        ChatCompletionCreateRequest,
        OpenRouterProviderPreferences,
        OpenRouterReasoning,
        OpenRouterUsageConfig;

/// Creates an SDK client configured for OpenRouter. The caller closes it.
api.OpenAIClient openRouterClient({
  required String apiKey,
  String baseUrl = 'https://openrouter.ai/api/v1',
  String? siteUrl,
  String? appName,
  String? sessionId,
  Map<String, String> headers = const {},
  http.Client? httpClient,
  http.Client Function()? streamClientFactory,
}) => api.OpenAIClient.withApiKey(
  apiKey,
  baseUrl: baseUrl,
  defaultHeaders: {
    'HTTP-Referer': ?siteUrl,
    'X-Title': ?appName,
    'X-Session-Id': ?sessionId,
    ...headers,
  },
  httpClient: httpClient,
  streamClientFactory: streamClientFactory,
);

/// OpenRouter chat model. The caller owns [client].
final class OpenRouterChatModel implements ChatModel {
  final api.OpenAIClient client;
  final String model;
  final api.OpenRouterProviderPreferences? provider;
  final List<String>? fallbackModels;
  final String? route;
  final api.OpenRouterReasoning? reasoning;
  final api.OpenRouterUsageConfig? usage;
  final api.ChatCompletionCreateRequest Function(
    api.ChatCompletionCreateRequest,
  )?
  configure;

  const OpenRouterChatModel({
    required this.client,
    required this.model,
    this.provider,
    this.fallbackModels,
    this.route,
    this.reasoning,
    this.usage,
    this.configure,
  });

  api.OpenAIChatModel get _delegate => api.OpenAIChatModel(
    client: client,
    model: model,
    configure: (request) {
      final options = request.copyWith(
        openRouterProvider: provider,
        models: fallbackModels,
        route: route,
        openRouterReasoning: reasoning,
        openRouterUsage: usage,
      );
      return configure?.call(options) ?? options;
    },
  );

  @override
  ModelCapabilities get capabilities => _delegate.capabilities;

  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) => _delegate.stream(request, cancellation: cancellation);
}
