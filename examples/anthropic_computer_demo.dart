import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;
import 'package:agent_weave_http/agent_weave_http.dart';

String environment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) throw StateError('Set $name.');
  return value;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) throw ArgumentError('Pass the task as command arguments.');
  final driverUrl = environment('COMPUTER_DRIVER_URL');
  if (Uri.parse(driverUrl).scheme != 'https') {
    throw ArgumentError('COMPUTER_DRIVER_URL must use HTTPS.');
  }
  final driverToken = environment('COMPUTER_DRIVER_TOKEN');
  final environmentId = environment('COMPUTER_ENVIRONMENT_ID');
  final driver = JsonHttpClient(
    baseUrl: driverUrl,
    requestTimeout: const Duration(seconds: 30),
  );
  final client = anthropic.AnthropicNativeClient.withApiKey(
    apiKey: environment('ANTHROPIC_API_KEY'),
    apiVersion: Platform.environment['ANTHROPIC_VERSION'] ?? '2023-06-01',
  );
  try {
    final agent = AiAgent<void>(
      model: client.chatModel(model: environment('ANTHROPIC_MODEL')),
      tools: [
        anthropic.AnthropicComputerTool<void>(
          environmentId: environmentId,
          needsApproval: true,
          allowedCallers: const ['direct'],
          execute: (call, context) async {
            final response = await driver.sendJson(
              '/execute',
              cancellation: context.cancellation,
              prepare: () => JsonHttpRequest(
                headers: {'Authorization': 'Bearer $driverToken'},
                body: {
                  'environment_id': environmentId,
                  'tool_call_id': context.toolCallId,
                  'idempotency_key': context.idempotencyKey,
                  'call': call.raw,
                },
              ),
            );
            final value = jsonDecode(response.body);
            if (value is! Map<String, dynamic>) {
              throw const FormatException('Expected a driver result object.');
            }
            return anthropic.AnthropicComputerResult.fromJson(value);
          },
        ),
      ],
    );
    var sequence = 0;
    var result = await agent.generate(
      ChatRequest(
        threadId: 'computer-demo',
        runId: 'run-${sequence++}',
        messages: [ChatMessage.user(args.join(' '), id: 'user')],
      ),
      ownerId: 'local-user',
      context: null,
    );
    while (result.status == RunStatus.interrupted) {
      stdout.writeln('Requested actions:');
      for (final interrupt in result.interrupts) {
        stdout.writeln(jsonEncode(interrupt.call.toJson()));
      }
      stdout.write('Approve this turn? [y/N] ');
      final approve = stdin.readLineSync()?.trim().toLowerCase() == 'y';
      final previous = result;
      result = await agent.generate(
        ChatRequest(
          threadId: previous.threadId,
          runId: 'run-${sequence++}',
          parentRunId: previous.runId,
          resume: [
            for (final interrupt in previous.interrupts)
              approve ? interrupt.approve() : interrupt.reject(),
          ],
        ),
        ownerId: 'local-user',
        context: null,
      );
    }
    stdout.writeln(result.text);
  } finally {
    driver.close();
    client.close();
  }
}
