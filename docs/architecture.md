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
and JSON SSE I/O for native adapters. Together, Gateway and Cloudflare use the
same per-request deadline, abort, metadata and error-body handling. Provider adapters own finish/EOF semantics and credential redaction.
This package does not add an HTTP dependency to the core agent runtime.

`CancellationToken.whenCancelled` remains the one-shot Future API.
`onCancelled` supplies a single-event Stream when a component needs a removable
listener. Late subscribers still receive cancellation. Native request scopes and
linked model subscriptions dispose that listener after completion or cancellation
so a long-lived parent token does not retain completed request callbacks.
