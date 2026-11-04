import 'dart:convert';
import 'dart:io';
import 'package:agent_weave_together/agent_weave_together.dart';

/// Executable fixture: compare actual Dart option serialization to upstream fields.
void main() {
  final options = TogetherChatOptions(
    chatTemplateKwargs: {'enable_thinking': false},
    compliance: TogetherCompliance.hipaa,
    contextLengthExceededBehavior: TogetherContextLengthBehavior.error,
    echo: true,
    frequencyPenalty: 0.1,
    logitBias: {'42': -1},
    logprobs: 5,
    minP: 0.1,
    presencePenalty: 0.2,
    reasoningEnabled: false,
    reasoningEffort: TogetherReasoningEffort.low,
    repetitionPenalty: 1.1,
    safetyModel: 'account-selected-safety-model',
    seed: 42,
    stop: ['end'],
    temperature: 0.3,
    toolChoice: TogetherToolChoice.function('lookup'),
    topK: 10,
    topP: 0.9,
  );
  final file = File('.dart_tool/together-options.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(options.toJson()));
}
