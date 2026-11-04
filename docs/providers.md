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

## Completed media

Emit `ContentPartReady(ImagePart(url))` for a completed generated image. Text
continues through `TextDelta`. The optional `textOffset` places media at a UTF-16
offset in the text accumulated for this invocation; omit it to use the current
position. Offsets must be nondecreasing and cannot point beyond received text.
The runtime preserves this order in assistant history and sanitized client
snapshots. `AgentResult.images` collects assistant images from the current run.

Validate provider URLs and complete payloads before emitting media. Keep opaque
image signatures and continuation fields in `ProviderOutput`, with a distinct
provider namespace. Bind replay to its public content before restoring it;
provider data must not overwrite roles, registered calls, schema or history.
Partial image previews need a separate progress contract; do not publish them
as completed content.

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


## Text citations

Emit `CitationReady(TextCitation(...))` after its answer text is available.
Offsets are UTF-16 code units into all `TextDelta` output for that invocation;
source coordinates remain separate. The runtime validates boundaries, persists
annotations with the assistant message and exposes safe citation metadata to
clients. Put only public fields in a typed citation. Keep native replay fields
in `ProviderOutput`. See [citations](citations.md) for source types and wire data.


## Native output positions

Emit `ReferenceReady(OutputReference(...))` when a source has a native range,
insertion point or file-list ordinal that cannot be treated as a verified Dart
text highlight. Supply the known UTF-16 enclosing `partStart`/`partEnd` separately.
Keep provider positions opaque and use typed source fields. Scoped file handles
are deliberate public data and require application authorization.
See [output references](output-references.md).


## Provider-owned approvals

Implement `ProviderApprovalModel` when the provider executes tools remotely and
can request a human decision. Emit `ProviderApprovalReady` with a
`ProviderApprovalCall`. Generate a distinct local call ID for public display;
keep `providerRequestId` in backend state. Do not register a dummy `AgentTool`
or emit a local tool result for a remote approval.

`approvalContract(call)` returns an immutable, versioned configuration snapshot
for resume checks. Bind all relevant remote tools and authorization identities;
resolve secrets at request time. Approval and denial arrive as trusted
`ModelRequest.providerApprovalDecisions` across the saved conversation. Preserve
their native correlation and order. Reject a different provider's decision
history before dispatch. Never accept raw continuation state from a client.

Emit `ProviderExecutionStarting` immediately before a request that can cause
provider-managed effects, after preflight and credential resolution. The runtime
checkpoints an indeterminate marker before advancing your stream. A known
terminal checkpoint clears it; failure or cancellation cannot automatically
resend the request. Omitting this event on an initial remotely executing request
would leave that failure boundary unprotected. Include it even when no approval
has occurred, such as a server configured to execute without asking.

The [OpenAI MCP adapter](openai-mcp.md) demonstrates this contract. Its pinned
clients use generic approval payloads. Native computer execution remains a
separate local-driver contract with different denial behavior.

## Bind provider-controlled continuations

Implement `ModelContinuationContract` when an adapter has provider-controlled
execution configuration. Return a stable, immutable JSON object with integer
`v: 1`, a nonempty adapter-defined `kind`, and all nonsecret execution authority: provider/model, endpoint or a
stable transport/account binding, managed tools, policies and effective options.
Keep live credentials separate. Core saves the original snapshot and compares
it before resumed local effects or dispatch, including local-only approvals
that share a turn with remote tools.

Build requests from the same frozen configuration. An arbitrary callback cannot
safely redefine that configuration after a pause. Reject such combinations or
provide an immutable options API, as native OpenAI Responses does. Preserve the
private snapshot in custom storage. Never reconstruct a missing historical
profile from current settings.

This capability does not validate arbitrary application code or infer identity
from tokens. An undeclared adapter gets an unbound marker, not a verified
no-effects contract. See [approval contracts](approval-contracts.md).
