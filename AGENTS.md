# AgentWeave

AgentWeave is an independent Dart AI runtime. It is not an official TanStack,
OpenAI, or Serverpod SDK. Preserve protocol interoperability without copying
TypeScript API conventions into the Dart developer API.

## Start here

- Read `README.md`, `docs/architecture.md`, and `docs/compatibility.md`.
- Core model contracts and agent execution live in `packages/agent_weave`.
- Provider-specific types stay in `packages/agent_weave_openai` and
  `packages/agent_weave_anthropic`, `packages/agent_weave_openrouter`, and
  `packages/agent_weave_together`, `packages/agent_weave_vercel_gateway`, and
  `packages/agent_weave_cloudflare`, and `packages/agent_weave_ollama`.
  Shared JSON HTTP transport belongs in `packages/agent_weave_http`.
  The Anthropic normalizer consumes raw events; preserve opaque block fields
  and signed thinking before SDK decoding. Typed SDK configuration must apply
  changes to a pre-callback snapshot without erasing unknown replay fields.
  Anthropic hosted tools never invoke local executors. Preserve container IDs
  and exact tools across unfinished turns. Use ModelFinished.continuation so
  checkpoints and maxSteps govern provider-owned pauses; never hide retry loops
  inside adapters. Native provider protocols require their own
  serialization, continuation, and option-preservation tests.
- HTTP/session integration lives in `packages/agent_weave_serverpod`.
  Dart Frog handlers live in `packages/agent_weave_dart_frog`.
  Ollama uses native NDJSON transport, not the compatible SSE codecs.
  Preserve native IDs privately and use distinct local tool-call IDs.
- Native client transport lives in `packages/agent_weave_serverpod_client`.
- Optional storage is a Serverpod module, `agent_weave_serverpod_storage_server`,
  with a generated `agent_weave_serverpod_storage_client`.
- The runnable backend and its real PostgreSQL/network tests live in
  `examples/serverpod/agent_weave_demo_server`.

## Rules

Use named parameters, immutable values, sealed events, patterns, and Dart
Streams. Prefer typed provider options and schema-validated tool inputs.
Use prefixes for provider imports to avoid collisions such as `Tool`.
Use `jsonEquals` for Dart-owned JSON guards; `canonicalJson` deliberately uses
JavaScript numeric semantics for protocol hashing and is not a guard comparison.
Pending tool contracts are private versioned snapshots. Never reconstruct an
older contract from current definitions or use wire schema hashes as server
authorization guards. Validate the entire resume batch before effects.
Completed media and typed citations are public content; native output/replay
metadata stays private. Citation answer offsets use UTF-16; source coordinates
retain native units. Preserve citations and references when cloning canonical
history. Reference part spans are verified UTF-16 context, not native highlights;
file-list positions are not text offsets. Scoped public file handles do not
authorize retrieval.
Keep credentials on the backend and outside source control.

Authentication owns `ownerId`. Never accept it from a request body.
Validate all approval answers before invoking any tool in that batch.
Preserve run reservations, event ordering, and server-owned history.
Never automatically rerun external effects after a crash. Tools use their
`idempotencyKey` to implement idempotency with the destination service.

Never edit generated protocol/model files. Change `.spy.yaml` or endpoint
sources, then run Serverpod 4.1.0 generation and create migrations. Keep module
and example migrations in sync. Do not hand-edit migration metadata.

## Verification

Run `dart run tool/check.dart`. It includes unit tests, actual PostgreSQL and
Serverpod network tests, and interoperability with the official JavaScript
client. It does not make paid API calls.

Live tests require explicit authorization, an environment-only key, and a
persisted cumulative budget. Do not reset the ledger or increase its limit to
make a failing test pass. Do not store a live key in examples, logs, or fixtures.

Read `docs/updating.md` before changing upstream pins or claiming new coverage.
Keep `docs/validation.md` honest about fixture, live, and untested behavior.

## Product acceptance and developer reviews

Read `ROADMAP.md` before narrowing the scope or claiming completion. Native Dart
DX is the main contract; TanStack compatibility can be an optional integration.
Use an independent consumer-development subagent on each implementation round.
It must write/run realistic cases and score the experience honestly out of ten.
Use GPT-6.1 Terra with low/medium reasoning for subagents. Never convert a green
test count or forwarded provider parameters into a full-support claim.
