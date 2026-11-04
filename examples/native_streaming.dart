import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

Future<void> main() async {
  // Replace this deterministic model with a configured provider model.
  final model = ScriptedChatModel(
    steps: [
      [const TextDelta('Hello'), const TextDelta('!'), const ModelFinished()],
    ],
  );

  try {
    await for (final update in streamText(model: model, prompt: 'Say hello')) {
      switch (update) {
        case AgentTextDelta(:final text):
          stdout.write(text);
        case AgentRunFinished(:final result):
          print('\nRun status: ${result.status.name}');
        default:
          break;
      }
    }
  } on AgentRunException catch (error) {
    print('Run failed: ${error.message}');
    // error.result contains the partial backend snapshot for recovery.
  } on RunCancelled {
    print('Run cancelled.');
  }
}
