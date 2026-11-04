# Test your application offline

Use `ScriptedChatModel` to test an application workflow without paying a provider or depending on a nondeterministic response.

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';
import 'package:test/test.dart';

void main() {
  test('sends the expected instruction and returns the answer', () async {
    final model = ScriptedChatModel(steps: [
      [const TextDelta('Approved.'), const ModelFinished()],
    ]);
    final result = await generateText(
      model: model,
      instructions: 'Answer in one sentence.',
      prompt: 'Review this request.',
    );

    expect(result.text, 'Approved.');
    expect(model.requests.single.instructions, 'Answer in one sentence.');
    expect(model.remainingSteps, 0);
  });
}
```

## Script a tool round trip

Each model invocation consumes one step. A tool workflow normally needs a tool call step followed by an answer step:

```dart
final model = ScriptedChatModel(
  capabilities: const ModelCapabilities(tools: true),
  steps: [
    [
      ToolCallReady(ToolCall(
        id: 'call-1',
        name: 'double',
        arguments: {'number': 2},
      )),
      const ModelFinished(),
    ],
    [const TextDelta('The result is 4.'), const ModelFinished()],
  ],
);
```

Register a tool named `double` with a matching input schema. Test the execute callback's call count and its application effect. An approval test must also prove that the effect has not happened before approval.

An exhausted script fails with an explanatory error. Add the missing invocation rather than reusing the last response silently. See [the Dart API guide](dart-api.md) for complete tool and approval recipes.

## Test failure paths

Cover the behavior your application depends on:

- Reject malformed tool input before its execute callback runs.
- Keep approvals pending after an invalid continuation.
- Preserve text already delivered when a response is cancelled.
- Prevent one authenticated owner from loading or resuming another owner's conversation.
- Deduplicate external effects using the tool context's idempotency key.
- Close provider clients and active subscriptions when their owner is disposed.

For integration changes, run `dart run tool/check.dart` from the repository root. It includes a real isolated PostgreSQL database and Serverpod transports. [Validation evidence](validation.md) records which checks have run and which capabilities have only fixture coverage.
