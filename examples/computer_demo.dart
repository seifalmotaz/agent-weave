import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_http/agent_weave_http.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

Future<void> main(List<String> args) async {
  String requiredEnv(String name) {
    final value = Platform.environment[name];
    if (value == null || value.trim().isEmpty) throw StateError('Set $name.');
    return value;
  }

  if (args.length != 1 || args.single.trim().isEmpty) {
    throw ArgumentError('Pass one quoted task as the argument.');
  }
  final apiKey = requiredEnv('OPENAI_API_KEY');
  final modelId = requiredEnv('OPENAI_COMPUTER_MODEL');
  final environmentId = requiredEnv('COMPUTER_ENVIRONMENT_ID');
  final driverUrl = Uri.parse(requiredEnv('COMPUTER_DRIVER_URL'));
  final driverToken = requiredEnv('COMPUTER_DRIVER_TOKEN');
  if (driverUrl.scheme != 'https' ||
      driverUrl.host.isEmpty ||
      driverUrl.userInfo.isNotEmpty ||
      driverUrl.hasFragment) {
    throw ArgumentError(
      'COMPUTER_DRIVER_URL must be an HTTPS URL without credentials or fragment.',
    );
  }
  // The CLI operator is the trusted identity, not a request-body field.
  final ownerId = requiredEnv('USER');
  final driver = JsonHttpClient(
    baseUrl: driverUrl.origin,
    requestTimeout: const Duration(seconds: 30),
  );
  final client = openai.OpenAIClient(
    config: openai.OpenAIConfig(
      authProvider: openai.ApiKeyProvider(apiKey),
      retryPolicy: const openai.RetryPolicy(maxRetries: 0),
    ),
  );
  try {
    final agent = AiAgent<void>(
      model: openai.OpenAIResponsesModel(client: client, model: modelId),
      tools: [
        openai.OpenAIComputerTool<void>(
          environmentId: environmentId,
          execute: (call, context) async {
            context.cancellation.throwIfCancelled();
            if (!context.approved) throw StateError('Approval required.');
            final response = await driver.sendJson(
              driverUrl.path.isEmpty ? '/' : driverUrl.path,
              query: driverUrl.queryParametersAll,
              cancellation: context.cancellation,
              prepare: () => JsonHttpRequest(
                headers: {'Authorization': 'Bearer $driverToken'},
                body: {
                  'environment_id': environmentId,
                  'idempotency_key': context.idempotencyKey,
                  'actions': [
                    for (final action in call.actions) action.toJson(),
                  ],
                },
              ),
            );
            context.cancellation.throwIfCancelled();
            if (response.statusCode != 200) {
              throw StateError(
                'Computer driver failed (${response.statusCode}).',
              );
            }
            final result = jsonDecode(response.body);
            if (result is! Map ||
                result['environment_id'] != environmentId ||
                result['image_url'] is! String ||
                (result['image_url'] as String).isEmpty) {
              throw const FormatException('Invalid computer driver response.');
            }
            return openai.OpenAIComputerScreenshot.url(
              result['image_url'] as String,
            );
          },
        ),
      ],
    );
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    var result = await agent.generate(
      ChatRequest(
        threadId: 'computer-$id',
        runId: 'run-$id',
        messages: [ChatMessage.user(args.single, id: 'message-$id')],
      ),
      ownerId: ownerId,
      context: null,
    );
    var continuation = 0;
    while (result.status == RunStatus.interrupted) {
      final answers = <ResumeAnswer>[];
      for (final interrupt in result.interrupts) {
        stdout.writeln(
          'Proposed computer call: ${jsonEncode(interrupt.call.arguments)}',
        );
        stdout.write('Approve this entire call and its safety checks? [y/N] ');
        final approved = stdin.readLineSync()?.trim().toLowerCase() == 'y';
        answers.add(approved ? interrupt.approve() : interrupt.reject());
      }
      result = await agent.generate(
        ChatRequest(
          threadId: result.threadId,
          runId: 'run-$id-${++continuation}',
          parentRunId: result.runId,
          resume: answers,
        ),
        ownerId: ownerId,
        context: null,
      );
    }
    stdout.writeln(result.text);
  } on RunCancelled {
    stderr.writeln(
      'Computer run stopped. Inspect the environment before starting a new thread.',
    );
  } finally {
    driver.close();
    client.close();
  }
}
