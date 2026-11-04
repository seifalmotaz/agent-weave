import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

Future<void> main() async {
  try {
    await generateObject<int>(
      model: ScriptedChatModel(
        capabilities: const ModelCapabilities(structuredOutput: true),
        steps: [
          [const TextDelta('{"priority":"urgent"}'), const ModelFinished()],
        ],
      ),
      prompt: 'Classify priority',
      schema: const {
        'type': 'object',
        'properties': {
          'priority': {'type': 'integer'},
        },
        'required': ['priority'],
        'additionalProperties': false,
      },
      decode: (json) => (json as Map<String, Object?>)['priority'] as int,
    );
    throw StateError('The intentionally invalid fixture was accepted.');
  } on AgentRunException catch (error) {
    print('Public error: ${error.code}: ${error.message}');
    if (error.cause case SchemaValidationException(:final issues)) {
      // Backend diagnostics only. Issue messages may contain schema/input data.
      for (final issue in issues) {
        print('${issue.instancePath} (${issue.schemaPath}): ${issue.message}');
      }
    } else {
      rethrow;
    }
  }
}
