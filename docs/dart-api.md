# Dart API and application recipes

Use `generateText` for a single backend operation, `generateObject<T>` for a
schema-validated Dart value, and `AiAgent<C>.generate` for a conversation with
trusted application context and storage. `AiAgent.run` remains the streaming
transport API. They share the same validation and tool loop.

Runnable offline examples: [consumer scenarios](https://github.com/seifalmotaz/agent-weave/blob/main/examples/review_cases/consumer.dart)
and [failure diagnostics](https://github.com/seifalmotaz/agent-weave/blob/main/examples/review_cases/failures.dart).
Run `dart run examples/review_cases/consumer.dart` from the workspace root.
For a complete application with typed tools, approval, shared memory history,
and a synthetic file reference, run the [offline support example](offline-support.md).

## Generate text

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

final client = openai.OpenAIClient.fromEnvironment();
try {
  final result = await generateText(
    model: openai.OpenAIResponsesModel(client: client, model: 'gpt-5.4-nano'),
    prompt: 'Summarize the support ticket.',
    maxOutputTokens: 256,
  );
  print(result.text);
  print(result.usage?.outputTokens); // null means unreported, not zero.
} finally {
  client.close();
}
```

Pass exactly one of `prompt` or `messages`. The `messages` argument is trusted
backend history and can include assistant/tool messages. Never pass unchecked
browser history as trusted seed data. HTTP routes accept only user additions
to server-owned history.

`result.text` contains the final assistant message. `responseMessages` includes
this run's intermediate assistant/tool messages. `images` is an immutable list of
images produced by assistant messages in this run, including intermediate tool
steps; it excludes user inputs and previous runs. `messages` is the complete
server-side conversation snapshot, including private provider continuation
state. Use `chatHydration` when returning stored history to a UI.

## Decode structured output

```dart
final answer = await generateObject<int>(
  model: model,
  prompt: 'Return the number of days in a week.',
  schema: const {
    'type': 'object',
    'properties': {'days': {'type': 'integer'}},
    'required': ['days'],
    'additionalProperties': false,
  },
  decode: (json) => (json as Map<String, Object?>)['days'] as int,
);
print(answer.value);
print(answer.generation.usage?.inputTokens);
```

Validation runs before your decoder. Decoder exceptions are application errors
and propagate normally. A provider that does not support structured output is
rejected before submission.

### Inspect schema errors on the backend

`validateSchema` throws `SchemaValidationException`, a `FormatException` subclass.
Its immutable `issues` list contains `instancePath`, `schemaPath`, and `message`
from the installed JSON Schema validator. Tool input, tool output, structured
output, and edited approval arguments use the same validation function.
An agent failure retains this exception in its private `cause`.

```dart
try {
  await agent.generate(request, ownerId: ownerId, context: context);
} on AgentRunException catch (error) {
  if (error.cause case SchemaValidationException(:final issues)) {
    for (final issue in issues) {
      backendLogger.error('${issue.instancePath}: ${issue.message}');
    }
  }
  showSafeError(error.message);
}
```

Keep `issues` in backend diagnostics. Messages can include input or schema values.
The exception's default `message` and `toString()` remain generic, and client
errors do not include the issues. Original model text and user messages still
belong to conversation history; this does not redact their contents.

Paths follow `json_schema` conventions, not escaped JSON Pointers. A root path
can be empty; property names containing `/` or `~` are not escaped. Combinators
such as `oneOf` can report only a summary without nested branch errors.
Edited tool arguments are validated against their original schema separately
from the approval envelope, preserving their field paths and local references.
The public approval schema and its wire hash are unchanged. The pinned validator
cannot resolve some local references when directly validating that embedded
public approval union. Both real clients do complete the tested raw object
schema's local-reference edit; see [client edited approvals](tools.md#edit-tool-arguments-in-a-client).
They can forward an invalid edit for the backend to reject. Client-side schema
validation and server-side authorization remain separate responsibilities.

Run `dart run examples/schema_diagnostics.dart` for a complete offline example.
It prints a safe `INVALID_OUTPUT` message and a private `/priority` diagnostic.

## Typed tools, approvals, and durable Serverpod history

Keep the agent factory in your backend. It can be recreated on each request;
the shared database holds the conversation and pending approval.

```dart
AiAgent<Session> agentFor(Session session) => AiAgent<Session>(
  model: model,
  store: ServerpodRunStore(session),
  tools: [
    Tool<String, String, Session>(
      name: 'send_message',
      description: 'Send an approved message',
      needsApproval: true,
      inputSchema: const {
        'type': 'object',
        'properties': {'text': {'type': 'string'}},
        'required': ['text'],
        'additionalProperties': false,
      },
      outputSchema: const {'type': 'string'},
      decode: (json) => json['text'] as String,
      encode: (result) => result,
      execute: (text, context) => messageService.send(
        ownerId: context.ownerId,
        text: text,
        idempotencyKey: context.idempotencyKey,
      ),
    ),
  ],
);
```

`messageService` is your application service. It must enforce permissions and
use the idempotency key at the destination. AgentWeave cannot make an external
service execute exactly once after a crash.

```dart
final paused = await agentFor(session).generate(
  ChatRequest(
    threadId: conversationId,
    runId: firstRunId,
    messages: [ChatMessage.user('Send the update', id: userMessageId)],
  ),
  ownerId: session.authenticated!.userIdentifier,
  context: session,
);

if (paused.status == RunStatus.interrupted) {
  final completed = await agentFor(session).generate(
    ChatRequest(
      threadId: paused.threadId,
      runId: newRunId,
      parentRunId: paused.runId,
      resume: [for (final interrupt in paused.interrupts) interrupt.approve()],
    ),
    ownerId: session.authenticated!.userIdentifier,
    context: session,
  );
  print(completed.text);
}
```

The approval loop illustrates the backend API; a real application waits for a
human decision. Do not automatically approve tools in production. Use
`reject()`, `approve(editedArgs: ...)`, or `cancel()` as appropriate. Client-tool
interrupts use `resolve(output)` and reject approval methods. Resolve every
pending interrupt once, using a new run ID and the interrupted parent run ID.
Do not add a new user message until pending tools have been resolved.

For UI streaming use the authenticated endpoint in the
[Serverpod example](../examples/serverpod/README.md). Its dedicated stream
session remains open until the response closes.

## Restore a client-side conversation

Use `serverpodConnection(send: client.ai.chat, loadHistory: client.ai.history)`
with `persistence: const ChatPersistenceOptions.server()` on `ChatClient`, then
`await chat.attach()`. Register matching `ChatClientTool` input/output schemas
for typed tool approvals. Without server persistence the client does not call
the loader; without matching schemas a pending tool may be exposed as a generic
interrupt rather than a typed tool approval.

The [runnable two-command approval example](../examples/serverpod/README.md#run-an-approval-across-process-restarts)
includes the complete client setup and an automated real process-restart test.
Native `loadHistory` supports full snapshots. Advanced paging remains available
through an explicit `hydrate` callback.

## Cancel a running operation

Create one `CancellationToken` per operation and pass it to `generate` or `run`.
Your application's stop action calls `cancel()` on that token.

```dart
final cancellation = CancellationToken();
final work = agent.generate(
  request,
  ownerId: ownerId,
  context: context,
  cancellation: cancellation,
);
// Call this from the application's stop action while work is in progress.
cancellation.cancel();
try {
  await work;
} on RunCancelled {
  // Treat this as a cancelled run, not a completed answer.
}
```

Cancellation is cooperative. Custom models and tool executors must observe
`context.cancellation` or the invocation's token. Cancellation does not undo an
external effect or prove the provider stopped billing. Retained partial history
is available from the run store; use `chatHydration` to expose a safe snapshot.

Run `dart run examples/cancellation.dart` to cancel an already-started offline
provider and verify its cancelled checkpoint. It needs no timer or API key.

## Handle failures

```dart
try {
  final result = await agent.generate(request, ownerId: ownerId, context: context);
  // A paused result has status interrupted and typed tool interrupts.
} on AgentRunException catch (error) {
  logger.error(error.code, error.cause, error.causeStackTrace);
  // error.result retains partial text and this run's snapshot.
} on RunCancelled {
  // Cancellation is deliberate and does not imply a completed answer.
} on RunConflict {
  // Another run owns the thread, the ID was reused, or the parent is stale.
}
```

| Code | Meaning |
| --- | --- |
| `INVALID_INPUT` | Invalid caller input or continuation |
| `INVALID_OUTPUT` | Invalid provider JSON or tool-call format |
| `MODEL_FAILED` | Model invocation failed or ended prematurely |
| `TOOL_FAILED` | A tool failed; reconcile possible external effects |
| `STEP_LIMIT` | The configured agent loop bound was reached |

Private causes stay on the backend. Error observers are best-effort synchronous
callbacks; a throwing observer does not replace the original failure. Do not
supply an unawaited asynchronous logger callback. Client streaming errors expose
safe codes/messages rather than private exceptions.

## Test without a provider account

```dart
import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave/testing.dart';

final model = ScriptedChatModel(steps: [
  [
    const TextDelta('Hello'),
    const TokenUsage(inputTokens: 2, outputTokens: 1),
    const ModelFinished(),
  ],
]);
final result = await generateText(model: model, prompt: 'Hi');
assert(result.text == 'Hello');
assert(model.requests.single.messages.single.text == 'Hi');
assert(model.remainingSteps == 0);
```

Declare the capabilities used by your fixture (`tools`, `structuredOutput`,
multimodal input). Supply one step per model invocation, including post-tool
invocations. Missing terminal events and exhausted scripts fail explicitly.
For custom providers see [the provider guide](providers.md).

## Connect a local OpenAI-compatible endpoint

```dart
final client = openai.OpenAIClient(
  config: openai.OpenAIConfig(
    baseUrl: 'http://localhost:11434/v1',
    authProvider: openai.ApiKeyProvider('local-development'),
  ),
);
final model = openai.OpenAIChatModel(client: client, model: 'your-installed-model');
final result = await generateText(model: model, prompt: 'Hello');
```

This uses the Chat Completions wire format; the target must implement it.
Local server/model capability support varies. This recipe is not a claim of
Ollama, OpenRouter, Together, or gateway-specific option parity. Use an
application-controlled URL; keep hosted provider keys on the backend. Flutter
may call a local/on-device provider directly, but this repository has not yet
verified mobile device networking or model execution.

## Structured output in history

Successful schema-validated assistant messages retain a `StructuredMessageOutput`
in `ChatMessage.structuredOutput`. Its `data` is immutable JSON parsed from
`raw`; providers still replay the original text. `chatHydration` returns a
completed structured-output part instead of duplicating that text as a plain
answer. Legacy messages without this field keep their existing representation.

Provider-owned pauses count against `maxSteps`. A paused intermediate response
can contain progress text; only the final response is validated against the
output schema. The streaming protocol replaces that intermediate structured UI
state with a sanitized message snapshot before continuing.


## Safe failure messages

`AgentRunException.code` classifies a failed Future-based run. Its `message` is
the same sanitized explanation sent in a `RUN_ERROR` event and can be displayed
to the user. Its `cause` and `causeStackTrace` are private backend diagnostics.
For example, changed or legacy pending tool contracts provide a recovery
instruction without exposing schemas or native configuration. See
[approval contract migration](approval-contracts.md).
