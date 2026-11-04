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
Each run owns its cancellation token. Cancelling a run subscription signals
the provider and releases its reservation after cleanup.

An HTTP response owns a separate Serverpod session for the duration of its
stream. Create tool context from that session. The incoming HTTP request session
is unsuitable for work that continues while the response body is streamed.

## Persistence

`RunStore` reserves a thread atomically and rejects reused run IDs. Reservations
are scoped to the authenticated owner. Event logs are append-only, and complete
conversation checkpoints are saved separately. Terminal events are published
after releasing the reservation.

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
