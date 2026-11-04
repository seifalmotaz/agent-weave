# Write a provider

Implement `ChatModel`. Keep provider credentials, HTTP details, and provider
options inside your adapter.

```dart
final class LocalModel implements ChatModel {
  @override
  ModelCapabilities get capabilities => const ModelCapabilities();

  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    yield const TextDelta('Hello from a custom provider');
    yield const ModelFinished();
  }
}
```

Emit exactly one `ModelFinished` after a successful invocation. Do not emit
later events. An interrupted transport must throw or end without that event;
the runtime treats premature EOF as a failure.

Emit a `ToolCallReady` only after accumulating and parsing the complete argument
object. The runtime handles schema validation and execution. Do not execute a
tool inside the provider adapter.

Use `ReasoningDelta` for provider-supported reasoning summaries and
`ProviderOutput` for opaque continuation state. Never expose private replay
state as user-facing text. Emit `TokenUsage` when the provider reports it.

Pass `cancellation.whenCancelled` to the provider's abort mechanism. Check
pre-cancellation before submission. If an operation cannot abort after
submission, document that limit rather than silently promising cancellation.

The fixture providers in `packages/agent_weave/test` and the offline example
demonstrate custom implementations without any OpenAI dependency.

## Native tools

Use `NativeModelTool` and `NativeToolCallReady` for provider-native protocols,
with matching provider namespaces and stable execution bindings. Preserve the
original provider continuation privately; UI tool names can differ from native
toolset member names. Validate the full native turn before exposing executable
calls. Native approvals are read-only, and changed definitions cannot resume.

Implement `SequentialNativeTool` only when the provider supports valid skipped
results after a failed action. Its `skippedResult` must never perform an action.
OpenAI computer calls have no such denial result; Anthropic's computer toolset
uses its documented error results. See the provider guides for each contract.
