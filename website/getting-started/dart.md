# Generate a response in Dart

Run an offline model through the same runtime used by the Serverpod integration. This example makes no network requests and requires no credentials.

## Open the workspace

The packages are not yet published to pub.dev. Clone the repository and resolve the workspace dependencies:

```sh
git clone https://github.com/seifalmotaz/agent-weave.git
cd agent-weave
dart pub get
dart run examples/basic_chat.dart
```

Expected output:

```text
Hello from AgentWeave. No API key needed.
```

## Get a typed result

For a one-off request, use `generateText`. In a workspace Dart file, run:

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

Future<void> main() async {
  final model = ScriptedChatModel(steps: [
    [const TextDelta('Hello from Dart.'), const ModelFinished()],
  ]);
  final result = await generateText(model: model, prompt: 'Say hello.');
  print(result.text);
}
```

`ScriptedChatModel` is an offline test provider. It records requests and consumes one response step per model invocation. Replace it with an OpenAI adapter or your own `ChatModel` when you connect a provider.

## Choose the right API

Run the [offline support application](../offline-support.md) next. It pauses a
typed tool before effects, resumes with approval using a recreated agent, and
reads a synthetic file reference. It requires no provider account or database.

Use `generateText` or `generateObject` for a stateless request. Use `AiAgent.generate` for typed results with trusted context and stored conversations.

For native Dart streaming, use `streamText` or `AiAgent.stream`. They emit sealed
`AgentUpdate` values and finish with `AgentRunFinished`, which contains the result
from that same execution. Follow the [typed streaming recipe](../native-streaming.md)
for text, tools, errors and cancellation. Use `AiAgent.run` when an integration
needs streaming protocol events, including TanStack clients.

Continue with [the Dart API guide](../dart-api.md) for structured output, typed tools, approvals, errors, and conversation history. For provider ownership and cancellation rules, read [architecture](../architecture.md).
