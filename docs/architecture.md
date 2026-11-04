# Architecture

The public Dart API and the TanStack wire protocol are separate contracts.
Provider adapters convert provider requests and responses. The runtime owns
agent execution. Serverpod owns the framework session, authentication, and
database connection.

## Model invocations

`ChatModel.stream` performs one invocation and emits sealed `ModelEvent` values.
The runtime validates tool calls, executes configured server tools, appends the
results, and invokes the model again. `maxSteps` bounds the loop.

`ProviderOutput` preserves provider-specific replay state, such as encrypted
reasoning. That state stays in server storage and is excluded from UI history.
Adapters must retain any state their provider requires to continue a tool call.

Images, speech, transcription, embeddings, Decisions, video jobs, and realtime
use separate capability interfaces. A provider implements only the interfaces
it supports. `GenerationTask<P, R>` adds result/progress streaming to a typed
operation.

## Native computer calls

`NativeModelTool` and `NativeToolCall` distinguish provider-native definitions
and calls from function tools, using a provider namespace to match the adapter.
The selected OpenAI Responses computer implementation and Anthropic computer
toolset each register one native server tool. The application owns action execution and the resulting screenshot;
the runtime owns approval, sequencing, and continuation. Other native tool
kinds and client-executed native tools are unsupported.

Native approvals use an approval-only response schema; arguments cannot be
edited. A paused call is bound to its tool definition and stable environment
ID, so a changed binding cannot resume it. Rejection, cancellation, or execution
failure closes the native continuation while retaining its audit history. Start
a new thread after inspecting the environment; never synthesize a screenshot or
acknowledgement. Provider continuation data is private, separate from UI history.
See [computer use](computer-use.md) for the application contract.

## Ordered native batches

`SequentialNativeTool` defines provider-valid failure and skipped-result policy.
After its first failed result, later executors in the same model turn stop.
Sequential native tools return their provider-valid skipped results and ordinary
functions return generic skipped errors. A native tool that cannot represent a
skipped result closes the continuation. The policy resets for
the next model turn and is included in the persisted definition binding.

When one sequential native call requires approval, the entire mixed turn pauses
before any executor runs. All answers are validated before execution, and approved
calls retain model order. A computer failure stops later mixed-turn effects; the
next model turn can recover from the error results.

## Anthropic normalization

`AnthropicProtocolModel` encodes canonical runtime history and normalizes raw
Messages events. `AnthropicNativeClient` uses the shared HTTP transport for
request-scoped cancellation and deadlines. The SDK-backed facade uses the same
normalizer without first decoding provider events into lossy SDK models.
Typed SDK configuration applies only differences from a pre-callback snapshot,
preserving unknown unchanged JSON fields. Canonical guards still reject changes
to server-owned messages, tools, bounds and requested output schemas.

Original supported content blocks are stored in `anthropic.messages`; compact
message and usage metadata live separately in `anthropic.messages.metadata`.
Only content blocks are replayed. Neither namespace enters UI hydration.

## Ownership and cancellation

The caller owns provider clients. Close them at application shutdown.
Each invocation owns a child cancellation token. `CancellationToken.bindStream`
links it to a caller signal and forwards pause/resume. Cancelling one subscription
signals only that invocation; cancelling the caller signal synchronously signals
all active children. The run releases its reservation after cleanup.

An HTTP response owns a separate Serverpod session for the duration of its
stream. Create tool context from that session. The incoming HTTP request session
is unsuitable for work that continues while the response body is streamed.

## Persistence

`RunStore` reserves a thread atomically and rejects reused run IDs. Reservations
are scoped to the authenticated owner. Event logs are append-only, and complete
conversation checkpoints are saved separately. Terminal events, final checkpoints, and reservation release commit atomically.
Observers cannot see successful completion before the final state is committed.

`MemoryRunStore` is for development. `ServerpodRunStore` uses PostgreSQL row
locking and unique indexes. Applications can implement the same contract for
their own storage.

A durable event log permits replay. It does not provide exactly-once execution
of an external tool after a process crash. Active reservations are deliberately
not stolen automatically. Reconcile external effects using `ToolContext.idempotencyKey` before
recovering an abandoned run.

## Transport

`AgentChatRoute` supports POST for execution, GET with `threadId` for history,
and GET with `runId` and `offset` for event replay. Authentication applies to
every operation. Replay observes persisted events; it does not rerun the model.

`streamAgent` fits a generated Serverpod endpoint returning `Stream<String>`.
`serverpodConnection` connects that endpoint to `tanstack_ai_dart`.

## Native provider boundaries

Together uses its own request serializer and HTTP stream transport. Delegating
its requests to the OpenAI SDK would lose unrepresented fields and change native
numeric `logprobs` into an OpenAI boolean. Adding hidden HTTP body rewriting
would also separate the public types from what was actually sent. The native
boundary keeps those provider differences visible in `TogetherChatOptions`.

`TogetherChatModel` converts one `ModelRequest` into one native request and maps
streamed text, reasoning, tools and usage back into core events. `AiAgent` owns
approvals, validation, tool execution and authoritative history. The raw client
provides a separate JSON contract for native choices and metadata that the agent
does not normalize. Cancellation and timeout belong to each HTTP request;
cancelling one stream does not close a shared client.

## Compatible protocol reuse

`ResponsesProtocolModel` and `ChatCompletionsProtocolModel` own canonical request
serialization, runtime option guards and event normalization. The OpenAI SDK
facades retain their existing client API and supply typed SDK transports. Gateway
supplies a native JSON transport instead, appending its documented
`providerOptions.gateway` extension after canonical request construction.

This keeps one tested implementation of each wire protocol. Copying the entire
encoder/parser into each compatible provider would make continuation fixes drift.
Rewriting HTTP bodies behind an SDK client would obscure the actual request type.
The explicit protocol boundary avoids both problems.

Provider replay is namespaced separately. Gateway Responses cannot replay a
message's private OpenAI Responses state, and it rejects provider file handles
until their gateway/account ownership can be established. URLs and inline input
remain separate source variants.

`agent_weave_http` owns HTTP methods with explicit empty, JSON or binary bodies
and JSON SSE/NDJSON I/O for native adapters. Together, Gateway and Cloudflare use the
same per-request deadline, abort, metadata and error-body handling. Provider adapters own finish/EOF semantics and credential redaction.
This package does not add an HTTP dependency to the core agent runtime.

`CancellationToken.whenCancelled` remains the one-shot Future API.
`onCancelled` supplies a single-event Stream when a component needs a removable
listener. Late subscribers still receive cancellation. Native request scopes and
linked model subscriptions dispose that listener after completion or cancellation
so a long-lived parent token does not retain completed request callbacks.

## Native OpenRouter fields

OpenRouter uses the shared Chat/Responses codecs for canonical agent messages,
tools, schema and token bounds, then appends native options through its explicit
JSON transport. This preserves fields the OpenAI SDK does not represent. Keeping
the old SDK-only transport would discard those fields; copying a complete codec
would duplicate continuation and validation logic.

Responses replay uses the SDK's existing raw `ResponseInput.fromOutputItems`
constructor with immutable snapshots. Re-parsing returned output through typed
input unions would reject reasoning items or drop valid output fields. Typed
configuration is compared against a pre-callback snapshot, including absent
runtime fields and Chat's alternate token bound and stream options.

Chat reasoning fragments and response-level metadata have separate private
namespaces. Only reasoning fragments are replayed as Chat continuation. Metadata
is a compact snapshot of reported fields; raw native methods retain complete
events without storing every text chunk twice in assistant history.

## Ollama and Dart Frog

Ollama uses native NDJSON rather than the compatible SSE codecs. The adapter
assembles selected message fields, retains original frames privately and maps
native call IDs to separate local runtime IDs. It replays thinking, tool indexes
and native IDs without exposing them through UI hydration. Tools with conflicting
repeated indexes fail before execution; raw streaming remains available.

Dart Frog handlers use core chat requests, generation tasks, stores and event
encoding. Authentication supplies owner identity and trusted context. Both chat
and generation derive identity on the server; generation decoding can use that
context to bind parameters. The application owns provider/store lifetimes and
keeps request-context resources valid until its response stream ends.

## Provider-owned continuations

`ModelFinished.continuation` ends one complete invocation and requests the next
model step without local tool results. The runtime checkpoints the assistant
message and private provider data before dispatch. It counts the step, retains
usage and protects unfinished continuation from new user messages. A paused
step-limit run can be continued explicitly using a new run ID and no new
messages; ordinary provider errors are never automatically retried.

Anthropic hosted tools belong to provider model configuration rather than the
application executor registry. Their native blocks and container IDs remain
private replay state. Local tool calls still pass through the core approval
and schema-validation path, including programmatic callers from code execution.

Successful structured responses retain parsed data with the original JSON in
`ChatMessage.structuredOutput`. Providers continue to encode the original text.
Hydration preserves completed structured parts; a structured pause emits a
sanitized message snapshot so intermediate progress cannot remain an errored
answer in either client. Private provider replay never enters that snapshot.


## Approval identity belongs to the Dart runtime

Private pending tool contracts preserve declared configuration and Dart numeric
values. The runtime validates the whole batch before any execution. Public
TanStack schema hashes retain their protocol semantics and do not decide whether
a server-owned contract changed. This keeps native Dart validation independent
of client numeric conversion; see [approval contracts](approval-contracts.md).


## Public text citations

`ChatMessage.citations` holds typed annotations over flattened assistant text.
The range uses UTF-16 answer offsets; source locations retain their native
character, page or block units. Providers emit `CitationReady` after the referenced
text is available. The runtime validates ranges before publishing the additive
`agent_weave:citation` event and persists annotations with their message.
Hydration and terminal snapshots include only typed public citation JSON in
`metadata.agent_weave.citations`.

Citation-bearing content parts would require every text and media converter to
understand a new text shape. Message annotations preserve the existing content
contract and let ordinary clients retain metadata. Provider replay remains a
separate private contract, including opaque fields that cannot be public. See
[citations](citations.md) for the five supported Anthropic projections and replay
input differences.
