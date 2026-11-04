import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

Future<void> main() async {
  final environment = Platform.environment;
  final key = environment['ANTHROPIC_API_KEY'];
  final model = environment['ANTHROPIC_MODEL'];
  final url = environment['MCP_SERVER_URL'];
  final tool = environment['MCP_ALLOWED_TOOL'];
  if ([key, model, url, tool].any((value) => value == null || value.isEmpty)) {
    throw StateError(
      'Set ANTHROPIC_API_KEY, ANTHROPIC_MODEL, MCP_SERVER_URL and MCP_ALLOWED_TOOL.',
    );
  }
  final token = environment['MCP_ACCESS_TOKEN'];
  final client = anthropic.AnthropicNativeClient.withApiKey(apiKey: key!);
  try {
    final agent = AiAgent<void>(
      model: client.chatModel(
        model: model!,
        authorityBindingId: 'local-example/anthropic-account',
        options: {'temperature': 0.2},
        mcpServers: [
          anthropic.AnthropicMcpServer(
            name: 'support',
            url: Uri.parse(url!),
            beta: anthropic.AnthropicMcpBeta.client20260915,
            toolset: anthropic.AnthropicMcpToolset(
              defaultConfig: anthropic.AnthropicMcpToolConfig(enabled: false),
              configs: {tool!: anthropic.AnthropicMcpToolConfig(enabled: true)},
            ),
            credentialBindingId: token == null
                ? null
                : 'local-example/mcp-account',
            authorizationToken: token == null ? null : () => token,
          ),
        ],
      ),
      maxSteps: 4,
      maxOutputTokens: 1024,
    );
    final result = await agent.generate(
      ChatRequest(
        threadId: 'support',
        runId: 'question',
        messages: [
          ChatMessage.user(
            environment['MCP_PROMPT'] ??
                'Use $tool to find information about Dart streams.',
            id: 'u',
          ),
        ],
      ),
      ownerId: 'local-example',
      context: null,
    );
    print(result.text);
  } on AgentRunException catch (error) {
    stderr.writeln('${error.code}: ${error.message}');
    exitCode = 1;
  } finally {
    client.close();
  }
}
