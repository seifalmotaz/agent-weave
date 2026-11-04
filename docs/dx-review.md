# Independent Dart consumer review — round 2

Reviewed the current uncommitted worktree on 2026-11-04, using `docs/dart-api.md`, public imports and offline executable consumer probes. This is a snapshot, not a release or production-readiness certification. No runtime code was edited and no network or paid API call was made.

## Result: 7.7/10 (round 1: 6.7/10)

Each dimension has equal weight. A 5 requires substantial implementation reading or glue; an 8 is a documented, working application path with clear boundaries; a 10 requires independent adoption and broader failure testing. Scores represent the tested developer journey, not provider parity.

| Dimension | Score | Evidence |
| --- | ---: | --- |
| Discoverability | 7 | New Dart guide collects text, structured output, typed tools, approvals, testing and local endpoint in one place. Most recipes are fragments with application-defined names, and durable setup still requires the separate Serverpod example. |
| Clarity | 8 | `generateText`, `generateObject`, `AiAgent.generate`, `approve()` and typed context express common tasks directly. The approval example explicitly says a human must decide. The developer still assembles IDs, storage, service, session, identity and interruption UI. |
| Types | 8 | Typed tool input/output/context, decoded object and usage work in the consumer. Status and interrupts are accessible, but application JSON schema and decoder must be kept consistent manually. |
| Debugging | 7.5 | Malformed structured output now reports `INVALID_OUTPUT`, and executable probes identified `MODEL_FAILED`, `TOOL_FAILED` and `STEP_LIMIT` while retaining backend cause; partial text survived premature stream termination. Diagnose real storage and network failures separately. |
| Testing | 8 | `ScriptedChatModel` supports deterministic offline tests, checks received requests and fails clearly when exhausted. The example uses assertions, which are not a substitute for test-runner expectations in all execution modes. |

## Executed consumer checks

From repository root:

```sh
dart run examples/review_cases/consumer.dart
dart run examples/review_cases/failures.dart
```

Both exited 0. The first tested text plus usage, schema-validated `int`, typed tool with approval and trusted context, agent recreation with the same `MemoryRunStore`, subsequent history, a custom provider, and invalid structured output (`INVALID_OUTPUT`). The second checked a stream without a terminal event and exhausted fixture (`MODEL_FAILED`), a tool exception (`TOOL_FAILED`), and loop exhaustion (`STEP_LIMIT`). Causes were retained and premature stream failure retained partial text.

## Remaining developer friction and limits

1. **Durable approval recipe is not a runnable standalone setup.** It uses undefined `Session`, `messageService`, IDs and configured `model`. This is reasonable application pseudocode, but a first-time developer must still combine it with Serverpod setup, migrations, authentication and tool registration. The offline recreation probe shares an in-memory store within one process: it does not verify database persistence, restart recovery, or `atomicRunStore.complete` rollback/atomicity. Add a linked, runnable Serverpod consumer integration with process recreation and injected persistence failures.
2. **The local endpoint recipe is not a live compatibility test.** It usefully specifies the Chat Completions protocol and cautions that capability support varies. The custom provider probe is in-process only; it did not exercise HTTP, local inference, cancellation or model-specific options. A fixture-backed HTTP consumer example and separately documented real-server test would close this gap.
3. **Failure coverage remains selective.** The new codes and causes worked in probes above. They do not establish behavior for approval rejection or edited arguments, storage failure, cancellation, a decoder exception, concurrent runs, or a side effect that succeeds before persistence fails. Clarify and test those paths before increasing the debugging score. Tool failure cause includes private detail; the guide correctly says to keep causes on the backend.
4. **Examples are not uniformly copy-and-run.** The first guide snippet lacks a `main`; later snippets rely on definitions outside their code block. Link a small compilable complete sample and run it in CI. Use test framework expectations for the test recipe rather than relying exclusively on `assert`.
5. **Provider and SDK capability claims remain separate.** A custom `ChatModel` is straightforward, but scripted model success says nothing about real OpenAI-compatible implementations, tool protocol variants, media, caching or production performance.

No PostgreSQL, Serverpod restart, Flutter device, local model server, paid provider, network, crash recovery, or complete provider option parity was tested.


# Independent Dart consumer review — round 3

Reviewed main a4f4a93 on 2026-11-04. Score: **8.0/10** (round 2: 7.7). Equal weight; this reflects the exercised developer journey, not provider parity or production certification.

| Dimension | /10 | Evidence and remaining gap |
| --- | ---: | --- |
| Discoverability | 7.5 | Guide links runnable consumer samples and Serverpod example, but the PostgreSQL approval integration is buried in a test rather than linked as a setup recipe. |
| Clarity | 8 | Typed approval operations are clear; OpenAI integration lists realtime without prominently saying it exposes a connection rather than orchestrated voice and tools. The detailed limitation is in the separate options audit. |
| Types | 8 | Edited and rejected tool approvals worked. Provider-specific configure callbacks exist; generic options and cross-provider parity were outside this snapshot. |
| Debugging | 8 | Pre-cancellation and cooperative in-flight cancellation throw RunCancelled; prior round established error codes and partial text. Cancellation during a real HTTP request and storage faults remain untested. |
| Testing | 8.5 | A real loopback HTTP fixture, application approval cases, and the repository's PostgreSQL-backed approval integration passed offline. Real process restart and failure injection are not established by the integration. |

## Executed

From repository root:

```sh
dart run examples/review_cases/reliability.dart
cd examples/serverpod/agent_weave_demo_server
PATH="$(git rev-parse --show-toplevel)/.dart_tool/dart-3.12.2/dart-sdk/bin:$PATH" dart test test/integration/agent_test.dart --plain-name 'a recreated agent resumes a PostgreSQL-backed approval without repeating its tool'
```

The first example starts a local HTTP server implementing a minimal Chat Completions SSE response; checks the request route and model and resulting text; checks pre-cancellation and cooperative in-flight model cancellation; and checks rejection (no tool execution) and edited approval (one execution, edited output) using a shared MemoryRunStore. It is a fixture, not an actual local inference server. The PostgreSQL test recreates the agent and resumes a pending approval with the same database; it runs in one test process, not a restarted process. The exact executed test command was `cd examples/serverpod/agent_weave_demo_server` followed by `PATH="$(git rev-parse --show-toplevel)/.dart_tool/dart-3.12.2/dart-sdk/bin:$PATH" dart test test/integration/agent_test.dart --plain-name 'a recreated agent resumes a PostgreSQL-backed approval without repeating its tool'`.

## Highest priority friction

1. Publish and link a runnable persisted approval example: the Dart guide's Serverpod snippet depends on application-specific definitions; the working PostgreSQL integration is not discoverable from that recipe. Show setup and real human decision boundary, and distinguish process restart, storage faults, and external idempotency from agent recreation. The existing integration passed; it does not prove restart recovery.
2. State realtime scope beside its entry in the OpenAI guide: the public page lists the connection and says to close it, while the options audit explains it does not provide voice/tool orchestration and connection handshake cancellation is limited. Show a minimal lifecycle example and direct consumers to provider SDK events.
3. Document what cancellation guarantees: the cooperative fake stops when its token is signalled; this does not prove a provider's in-flight I/O aborts or undo an external effect. Add reproducible transport and storage-failure examples, including effects-before-checkpoint, rather than imply exactly-once behavior.
4. Switching Dart SDKs in the same workspace caused a sqlite3 build-hook kernel mismatch (expected 138, found 130) before tests ran. Re-running with the SDK that built the cache passed. This is observed environment/cache friction, not evidence of a package bug; a clean separate build cache or consistent SDK version is advisable.

No paid calls, external provider keys, real inference server, real HTTP in-flight cancellation, process restart, injected database failure, or live realtime session was exercised. Source implementation was not edited.

## Anthropic adapter follow-up: 7.8/10

Independent consumer snapshot of the new native adapter, reviewed separately from the main a4f4a93 score: discoverability 7, clarity 8, types 8, debugging 8, testing 8. Equal weighting. A minimal consumer still needs to find the underlying SDK client and understand its ownership; the application-facing API, typed tool and exception code are straightforward. Documentation and exports were being revised concurrently, so this is a point-in-time assessment.

```sh
PATH="$PWD/.dart_tool/dart-3.12.2/dart-sdk/bin:$PATH" dart run examples/review_cases/anthropic.dart
```

A local real HTTP fixture validated the native Messages path and authentication header, text generation, serialized structured-output schema and decoded object, a two-invocation agent tool loop, signed thinking replay and corresponding tool result. A simulated HTTP 400 surfaced as `AgentRunException` with `MODEL_FAILED` and an `ApiException(400)` cause containing the provider diagnostic. The fake endpoint does not validate actual Anthropic model compatibility, supported schemas or provider-side restrictions. No paid calls were made; no implementation bug was established by these probes.


# Round 4 consumer review

Score: **7/10** (discoverability 5, clarity 6, types 7, debugging 7, testing 8). The new native history loader removes a manual JSON conversion, and the typed approval hashes match across backend and client. Recovery still needs explicit client configuration and a complete consumer recipe.

## Tested offline

From the workspace root, run:

```sh
PATH="$PWD/.dart_tool/dart-3.12.2/dart-sdk/bin:$PATH" dart run .dart_tool/dx-review/round4/hydrate.dart
```

The probe creates a real approval interruption in MemoryRunStore with a scripted provider, serializes the actual `chatHydration` snapshot through JSON, passes it through the new `serverpodConnection(loadHistory: ...)` bridge and attaches a real TanStack ChatClient. It verifies by inspection that a tool with identical `RawJsonSchema` restores `kind=tool-approval`, while omitting the client tool restores `kind=generic` (still resolvable). The input/approval/response schema hashes matched. No provider calls or keys were used.

## Findings

1. The default `ChatClient` persistence is ephemeral. Even if `serverpodConnection` has a working history callback, `await chat.attach()` silently skips it unless configured with `persistence: const ChatPersistenceOptions.server()`. The original README connection recipe omitted both the callback and server persistence. A reader following it cannot restore approvals after an app restart.
2. To surface a typed tool approval, register a `ChatClientTool` with the same name, `needsApproval: true`, and an identical input schema wrapped in `RawJsonSchema`. Without it, the interrupt is silently downgraded to generic, with `canResolve=true`. Schema drift likewise matters because the client checks hashes. Explain both paths and show the actual Dart imports; a raw map is rejected by `ChatClientTool.inputSchema`.
3. Existing PostgreSQL approval integration recreates the backend agent but retains the prior in-memory `paused.interrupts`; it does not prove client restart/hydration/resolution. A consumer scenario that restores from authenticated Serverpod history and resumes via the generated client would close this gap.

## Limits

The probe uses the new uncommitted bridge and a memory store, not a running Serverpod database or generated-client WebSocket. It checks hydration and classification, not resumed execution, reconnect during an active stream, mobile UI, or schema drift behavior. The existing PostgreSQL integration source was inspected, but its full suite was not run here.

## Follow-up: runnable process restart journey

Targeted journey score: **8.5/10**. The new `example/approval_workflow.dart` supplies server persistence, the native `loadHistory` callback, matching client tool schema, and `attach()`. The CLI now rejects generic fallback by checking the interrupt kind and tool name as well as resolvability. This addresses the configuration and schema-binding gaps above. Documentation was being updated during this review, so its final discoverability was not assessed.

Independently passed with Dart 3.12.2: from `examples/serverpod/agent_weave_demo_server`, run `PATH="$PWD/../../../.dart_tool/dart-3.12.2/dart-sdk/bin:$PATH" dart test test/integration/restart_test.dart`. Output: `00:17 +1: All tests passed!` The test starts a fresh local Serverpod process and embedded PostgreSQL, starts the actual CLI in a fresh process, gracefully terminates and restarts the server using the same database files, approves from another fresh CLI process, and rejects a subsequent completed decision. No paid calls or keys were used.

This demonstrates the tested graceful restart and completed-decision replay scenario. It does not establish behavior after arbitrary crash timing, exactly-once external effects, or a mobile UI.


The round-four hydration behavior is now a checked-in regression suite:
`dart test packages/agent_weave_serverpod_client/test/history_test.dart`. It
covers real serialized interruptions with ephemeral/server persistence and
registered/unregistered tool schemas. The process-restart command above runs
the complete CLI directly, rather than a private review-only script.


## Round 5: document and OpenRouter consumers

Tested with pinned Dart 3.12.2, no API keys or paid calls. Scores reflect these specific journeys, not complete provider coverage.

| Journey | Discoverability | Clarity | Types | Debugging | Testing | Overall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Portable document inputs | 4/10 | 6/10 | 8/10 | 7/10 | 7/10 | 6.4/10 |
| OpenRouter text and routing | 7/10 | 8/10 | 8/10 | 6/10 | 7/10 | 7.2/10 |

Document constructors are straightforward once located, with typed variants and a scoped provider ID. At review time there was no complete public document recipe, so discovering construction, supported formats, provider-specific IDs, and storage implications required source reading. Anthropic file-ID and unsupported inline formats fail with useful messages; a non-OpenAI handle is rejected by Responses. The wire/history round trip preserves filename and content, but hydration contains the original base64 data and URLs. Explain that document contents and signed URLs can persist in server history and be returned to authorized history clients, and recommend appropriate retention/access controls. Actual persistence and restart depend on the configured store and were not tested.

`documents.dart` constructs URL, inline text and scoped file-ID documents, asserts native JSON and hydration/request round trips, verifies actual mock HTTP request bodies for OpenAI Responses and Anthropic, and checks invalid URL/base64/empty ID and explicit unsupported cases. Anthropic file-ID is unsupported by the pinned SDK. OpenAI Chat Completions and OpenRouter document inputs are unsupported by the current adapter. This probe uses in-process fixtures, not provider endpoints.

`openrouter_consumer.dart` follows the public README shape, uses a loopback HTTP endpoint, verifies the path, model, message, attribution header and routing preference, then receives streamed text through `generateText`. It demonstrates a practical setup without exposing a credential. The README clearly states that billing, provider identity, some OpenRouter features and live behavior are not verified. Troubleshooting remains less certain without a real service or an inline error consumer probe.

Reproduce the checked-in consumer cases:

```sh
dart --enable-asserts run examples/review_cases/documents.dart
dart --enable-asserts run examples/review_cases/openrouter.dart
```

### Follow-up after guides and canonical wire sources

The original scores above remain the first review. After reading `docs/documents.md` and `docs/openrouter.md` and re-running the examples, the document journey scores **8.0/10** (discoverability 8, clarity 8, types 8, debugging 8, testing 8). The guide now provides a runnable bytes example, URL/base64/file-ID alternatives, a provider matrix, and concrete history/privacy guidance. It still requires choosing a compatible provider/model and performing a paid call to verify actual acceptance; an offline fixture cannot establish file limits or durable restart.

The OpenRouter text/routing journey scores **7.8/10** (discoverability 8, clarity 8, types 8, debugging 7, testing 8). The new guide describes setup and limits. A new inline stream error consumer probe found that `generateText` wraps the underlying SDK failure as `AgentRunException`; the original guide implied direct propagation. The guide and package README now explain the distinction and trusted backend access to `cause`. Provider-specific metadata and live model behavior remain outside the tested contract.

The polished, reusable cases are `examples/review_cases/documents.dart` and `examples/review_cases/openrouter.dart`. Run with assertions enabled using the commands in the file headers. They pass on Dart 3.12.2 and strict `dart analyze` reports no issues. Document checks now assert canonical `source.value` for URL, inline bytes and scoped ID in hydration, and verify Anthropic PDF/base64 and text request serialization alongside Responses. The OpenRouter case verifies both the successful loopback and an inline error reaching the high-level exception's trusted backend `cause`. No actual provider calls, persistent store restart, billing, cancellation, or complete format support were tested.


## Round 6: native Together consumer

Initial score: 8/10. Updated offline developer experience score: 8/10.

| Criterion | Score | Reason |
| --- | --- | --- |
| Getting started and documentation | 8/10 | The guide shows client ownership, environment keys, a complete text example, and model-dependent limits. |
| Typed configuration | 8/10 | Named options and enums are discoverable; raw native JSON remains less discoverable and lacks static field checks. |
| Agent workflows | 8/10 | The loopback app exercised structured output, approval, tool execution and replay; model-dependent support remains unverified. |
| Errors and lifecycle | 8/10 | High-level errors retain safe-to-string provider causes and immutable diagnostics; cancellation was checked before sending, not during every network phase. |
| Streaming and output | 8/10 | Fragmented arguments, repeated call metadata, usage and length-limited partial text passed synthetic fixtures; real provider variants remain unverified. |

The initial review exposed dropped usage after a finish event; the fix passed the consumer test. The updated example also checks HTTP 429 status, request ID, nested immutable details and redacted exception string through `generateText`, as well as partial text and finish reason. It exercises the new enums through the public constructor.

Commands passed: `dart test packages/agent_weave_together/test/consumer_test.dart`; `dart --enable-asserts run examples/review_cases/together.dart`.

All checks used offline loopback responses with synthetic data. No paid calls, live Together model acceptance, billing, real network interruption, or exhaustive native fields were tested.


## Round 7: Gateway consumer review

Independent offline consumer exercise using Dart 3.12.2 with assertions and a real loopback HTTP server: `dart --enable-asserts run examples/review_cases/gateway.dart`. Synthetic fixtures model expected wire events; they do not establish actual Vercel Gateway API behavior, routing, or live compatibility.

Initial run: Responses structured output and approval continuation passed, including per-request rotating bearer and BYOK, routing options, provider options, credential-free stored history and serialized UI hydration. A separately generated request confirms wrong-provider Responses replay is excluded. Native JSON client preserved a response header and an unknown metadata field. Cancellation while awaiting a resolver prevented late dispatch.

Chat structured output and approval interrupt passed, but the approved continuation failed before HTTP dispatch with `AgentRunException(MODEL_FAILED)`, caused by `AssistantMessage.fromJson` during `ChatCompletionsProtocolModel.stream`. The test remains a runnable repro pending fix.

Scores (targeted experience, not SDK-wide acceptance): discoverability 5/10 (README lacks runnable usage and option examples), clarity 6/10 (simple constructor but credential and endpoint behavior need recipes), type safety 6/10 (typed routing, but BYOK and provider options are JSON maps), debugging 5/10 (generic run failure obscures continuation issue), testing 7/10 (real loopback is practical; provider service contract not verified). Overall 5.8/10.

Limits: no real Gateway, paid requests, deployed service, actual Flutter UI, concurrency/backpressure or complete provider surface. Header/metadata test covers native JSON response, not streamed model metadata. Hydration checks the serialized UI payload, not a running client UI.

### Retest after protocol fix

The same command now passes all four loopback checks, including the approved Chat tool continuation, credential-free stored history, and serialized pending UI hydration. `dart analyze examples/review_cases/gateway.dart` also reports no issues. The initial scores above remain the review record; the corrected continuation improves reliability, but the missing runnable package README and the unverified live Gateway contract still constrain the DX assessment. A revised targeted score is 6.4/10: discoverability 5, clarity 6, type safety 6, debugging 6, testing 9. The testing score reflects the consumer exercise and reproducibility, not production service coverage.

### Guide and diagnostic re-review

Both complete code blocks in `docs/vercel-gateway.md` were copied unchanged into fresh temporary Dart files and compiled with the workspace package configuration and Dart 3.12.2; neither was run because the examples use a live, potentially paid endpoint. The offline consumer journey was rerun successfully. It now additionally exercises `withApiKey`, enum-based cache/service-tier/sort configuration, forward-compatible extra options, and HTTP and stream errors with status/request ID and provider details. Known bearer and BYOK values were redacted in diagnostics while error codes remained available. These are synthetic loopback responses, not confirmation of the Gateway's production error shapes. The dynamic resolver journey rotates credentials between requests; the guide's environment-based example itself was compiled, not executed against a secret manager.

Revised targeted DX score: 7.6/10 — discoverability 8, clarity 8, type safety 7, debugging 7, testing 8. The complete runnable guide and typed routing materially improve setup and diagnosis; provider-specific configuration and BYOK still require JSON, and live provider behavior remains unverified. Earlier 5.8 and 6.4 assessments remain above as the initial and first-retest records.


## Round 8: Cloudflare consumer review


Offline loopback review, Dart 3.12.2, assertions enabled. No credentials, Cloudflare requests, license acceptance, or paid services were used.

| Criterion | First read | Current | Evidence and remaining friction |
| --- | ---: | ---: | --- |
| Getting started and ownership | 7/10 | 7/10 | Separate client and Gateway contracts and client ownership are explained; account/model availability still requires external verification. |
| Typed data and wire fidelity | 6/10 | 8/10 | Typed embedding and transcription results expose useful fields and raw responses; typed image bytes cover binary and decoded Flux JSON. Embedding vectors and image bytes reject mutation. |
| Agent and tool workflow | 7/10 | 7/10 | One native call pauses for approval and resumes with the documented replay; compatible chat and Responses replay a tool result in two requests. Native multiple calls are explicitly rejected. |
| Control and error handling | 7/10 | 7/10 | Loopback covers cancellation and deadline during token resolution, cancellation after send with pending headers and after a streamed event, request-scoped token rotation, and redaction on HTTP errors. |
| Documentation and discoverability | 6/10 | 8/10 | The expanded guide separates all four contracts, shows typed setup, states ownership and retry behavior, and qualifies model availability and live verification. It does not establish which models work in a particular account. |

Overall qualitative assessment: 7/10 initially, 8/10 now. These are reviewer judgments, not measured benchmarks; the typed-result and documentation improvements do not establish broader provider compatibility.

Run: `.dart_tool/dart-3.12.2/dart-sdk/bin/dart --enable-asserts run examples/review_cases/cloudflare.dart`. Also ran `dart analyze examples/review_cases/cloudflare.dart`; both passed. The loopback fixture checks native versus Gateway path, payload and headers; schema GET query; embedding shape and pooling; transcription bytes and JSON; image JSON and bytes; native approval, replay and multiple-call rejection before execution; compatible chat and Responses tool continuation; immutable embedding vectors and image bytes; credential rotation; error privacy; cancellation and timeout during token resolution; cancellation after send with pending headers; Gateway default and override headers across native, Gateway and compatible endpoints; and stream cancellation after headers and an event.

No defect was reproduced in those scenarios. Fixtures do not establish live Cloudflare behavior, model or account availability, license status, or all model schemas. Live service errors, actual Gateway billing and real inference were not checked in this independent example. Native traditional continuation is limited to the documented single-call replay; multiple-call continuation is not verified or claimed.

The first `docs/cloudflare.md` Dart block was extracted unchanged, verified identical to `examples/cloudflare_demo.dart`, analyzed, and compiled with Dart 3.12.2. It was not executed; no live or paid calls were made. The API inventory classifies operations rather than claiming parity.


## Round 9: native OpenRouter consumer


Offline loopback review with Dart 3.12.2 and assertions enabled; no real OpenRouter calls or credentials. Scores are qualitative judgments of this targeted workflow, not an SDK acceptance assessment.

| Criterion | Before | After | Evidence and limits |
| --- | ---: | ---: | --- |
| Discoverability | 6/10 | 8/10 | The guide identifies native client, Chat and Responses entry points and private metadata namespaces. |
| Clarity | 7/10 | 8/10 | The guide explains ownership, endpoints, private metadata, migration and limits; raw metadata still requires JSON inspection. |
| Types | 6/10 | 7/10 | Routing options and typed generation help; native requests and provider metadata remain JSON by design. |
| Diagnosis | 6/10 | 7/10 | A loopback 400 exposes status while redacting a fixture credential, but this is not a live error survey. |
| Testing | 6/10 | 8/10 | The independent network consumer covers the workflows below; it cannot prove upstream behavior. |

The original delegated adapter documented missing metadata and continuation. The new native path passes `dart --enable-asserts run examples/review_cases/openrouter_native.dart` and `dart analyze examples/review_cases/openrouter_native.dart`. The fixture exercises raw JSON provider and cost, Chat and Responses schema generation, two tool turns with persisted approvals and recreated agents, exact ordered replay of unknown and encrypted reasoning details, hydration privacy, unrelated provider state isolation, reported model/token/provider/cost preservation, absent usage remaining absent, rotating credentials and attribution headers, and HTTP error redaction. It also tests pre-cancellation, cancellation while headers are pending, unsubscribe after a flushed SSE event with a shared-parent sibling continuing, and borrowed HTTP client ownership. These are local fixtures, not evidence of actual billing, live model behavior, or provider compatibility. The native client did not expose a GET operation at initial review, so GET was not tested. Responses approval is independently exercised through a recreated agent and two loopback invocations: the continuation preserves ordered reasoning, opaque encrypted content, signature, unknown fields, assistant message and function call IDs and statuses, followed by the matching tool result. Cancellation through a real upstream, retries and all upstream unions remain unverified here.

The updated guide describes the tested scenarios and separates fixture evidence from live behavior. Its first complete Dart block was copied unchanged, compared byte-for-byte with `examples/openrouter_demo.dart`, analyzed, and compiled with Dart 3.12.2 without executing it. Other behaviors beyond the scenarios listed remain outside this independent fixture.


## Round 10: independent computer-tool consumer

Initial assessment before exercising it: discoverability 5/10 (new type and safety contract needed a guide); type ergonomics 7/10 (typed context and SDK actions, but protocol and replay details are not obvious); correctness confidence 4/10 (no independent run yet); testing 5/10 (provider fixtures existed, no consumer loopback evidence yet). These are qualitative judgments for this feature, not scores for the whole SDK.

After the loopback consumer: discoverability 6/10 pending review of the new guide; type ergonomics 8/10 because a typed app-owned executor, approval policy, and screenshot result are straightforward; debugging 7/10 because failures propagate but remote protocol details still need inspection; correctness confidence 7/10 for the exercised cases, not live computer use; testing 8/10 for a reproducible local consumer, with no real operating-system, browser, paid-model, or PostgreSQL claims.

Run `.dart_tool/dart-3.12.2/dart-sdk/bin/dart run examples/review_cases/computer.dart`. It uses a real loopback HTTP server and the pinned OpenAI client with a fake executor. It checks all nine action types as an ordered batch, a fresh screenshot, context and idempotency, no execution before terminal response or approval, recreated-agent continuation, call ID, reasoning replay and UI hydration, safety checks and legacy preview, benign automatic execution, rejection and rejected thread reuse, changed environment, invalid action, truncated response, malformed UTF-8, edited native arguments, pre-cancellation, and mismatched call kinds. A passing fixture does not establish real provider, OS, browser, cross-process persistence, or crash behavior.

Final guide and transport review: discoverability 8/10 (the complete sample, driver contract, policy choices, and continuation limits are now together); type safety 8/10 (typed executor and actions are useful, though consumers must inspect upstream action classes and serialize them to understand the full union); debugging 7/10 (local failures are observable but provider protocol failures still require investigation); testing 8/10 (a self-contained loopback exercises real HTTP without spending money); overall 7.8/10 for this feature, not the SDK as a whole. The full CLI guide block exactly matches `examples/computer_demo.dart`; both that sample and this consumer analyze cleanly. The sample was compiled to a native executable and analyzed, not run against a driver or provider. Final checks were rerun after the transport freeze.

Additional consumer cases send unknown top-level computer item data and verify it is in the private stored snapshot and replayed on continuation, but absent from UI hydration. Unknown action fields, click modifiers, and unknown drag point fields fail without executor invocation. This is limited to the specific malformed shapes tested; the fixture does not prove all future provider changes are safe. The legacy preview example in the consumer needed its environment updated from the old string to the current enum; the guide already uses the enum. Review commands use the pinned `.dart_tool/dart-3.12.2/dart-sdk/bin/dart`: `analyze examples/computer_demo.dart examples/review_cases/computer.dart` , `run examples/review_cases/computer.dart`, and `compile exe examples/computer_demo.dart -o /tmp/agentweave-computer-guide-review`.


## Round 11: Anthropic native consumer

## Before changes

Score: 7.8/10. Standard text, structured output, tool execution and signed thinking continuation are approachable. The typed SDK configuration is useful, but the SDK's union decoder and endpoint surface limit native protocol coverage and can discard fields not represented by its models. The HTTP error cause included the provider's response message, which can expose sensitive content. The current docs clearly state several limits.

`dart run examples/review_cases/anthropic.dart` passed against loopback HTTP: text, structured output, two-invocation tool loop, signed thinking replay, and HTTP 400 mapping. No provider request was made.

## Native API review

Score: 8.4/10. The native client is discoverable from the guide and makes raw and normalized access distinct. The JSON configuration callback is convenient for new fields, though it gives up compile-time option checking; unsupported blocks fail closed in normalized chat, with raw streaming available for custom handling. This is useful coverage, not full Anthropic parity.

Using the pinned Dart 3.12.2 SDK, `dart analyze examples/anthropic_demo.dart examples/review_cases/anthropic_native.dart` passed. The guide's first Dart block matches the demo byte-for-byte, and `dart compile exe examples/anthropic_demo.dart` passed. `dart run examples/review_cases/anthropic_native.dart` passed against loopback HTTP: text, JSON schema, approved tool call resumed by a recreated agent, signature and unknown fields on thinking replay, hidden hydration, request cache control and unknown options, final cumulative cache input and thinking-token usage, model, private metadata, citation replay and hydration privacy, key rotation, credential redaction in HTTP errors, raw create/count requests with query and header, pending-header and stream cancellation, sibling stream isolation, borrowed client ownership, malformed SSE rejection, and unknown block raw access with normalized failure.

The first run exposed two native client compile errors; implementation owner corrected them before the passing run. Provider error details are retained after credential scrubbing, so callers should treat error details as sensitive; other private response text is not generally redacted. The guide's executable demo was analyzed, not run, because it makes a billable request. No live provider, operating system, or browser behavior was tested. Unknown block types and deltas remain unsupported by the normalized agent loop. The fixture validates a selected cache-control request shape, not a provider cache hit or exhaustive native options.




## Round 12: Anthropic computer consumer review

Initial assessment: 3/10 for this specific path. The native Messages client and general tool approval pattern are discoverable from `anthropic_native.dart`, but no computer tool exists in the provider package at the start of this round. A consumer cannot safely represent toolset actions, execute them, or resume their results through this API yet. This is not an SDK-wide score.

Review environment: local loopback HTTP, `MemoryRunStore`, fixture credentials and app-owned fake executor. No provider calls, real desktop driver, or paid usage.

Initial integration run: the 17 documented members passed in consecutive batches of up to three; error batch halting, environment change, decline, unknown member/input/caller, disabled member, incomplete stream, invalid stop, cancellation, typed image result and ID matching also passed. An ordinary function mixed with a computer action ran before the computer approval and its result was serialized before the preceding computer call. Reported both to the implementation owner. The implementation was then changed to pause the entire mixed batch and sort the result blocks.

Final assessment: **7.8/10 for this Anthropic computer path**, not an SDK-wide grade. The typed action/result API and stable environment ID make the executor understandable and prevent accidental replay to a changed environment. Defaults require approval, and the private provider data is separated from the safe callback and hydration. A consumer still needs to implement and secure all real desktop operations, resize screenshots, choose a stable environment identity, and understand how a failed action halts the rest of a batch. Debugging is helped by typed actions and the loopback fixture, but there is no real driver or model evidence here.

Final run with Dart 3.12.2: `dart run examples/review_cases/anthropic_computer.dart` passed all 12 modes, including mixed function/computer approval and continuation ordering after the fix. `dart analyze examples/review_cases/anthropic_computer.dart` passed on the final fixture. These are fixture-backed observations only: no live Anthropic request, actual image capture, desktop effects, or persisted database restart was tested.

The official JavaScript client also passed a mixed three-interrupt scenario against an actual `AnthropicComputerTool` with a scripted model. Before approval both executors had zero effects; response schemas excluded native argument edits. After approval, the first computer error skipped the second computer call, the ordinary function was initially allowed to run, result IDs reached the model in order, and hydration excluded private replay and the environment binding. The full existing interop script passed all 17 cases. This does not exercise a real Anthropic model or native desktop.

The guide explains the HTTPS driver contract, approvals, idempotency, error behavior and security boundaries clearly. The standalone example analyzes cleanly. Its live network and console behavior remain untested. The 7.8/10 assessment stands: the entry point is usable and safer, while the application still owns substantial driver and operational work.

After the final API freeze, the guide's first Dart block matched the executable example byte-for-byte, and Dart 3.12.2 analysis passed for that example, the consumer fixture and interop server. All 12 consumer modes and all 17 JavaScript interop scenarios passed again. The guide now states the default approval policy accurately and documents typed coordinates and scroll directions.

A subsequent safety fix stops all later executors in the same mixed turn after a computer error. The final rerun passed all 13 consumer modes, including mixed error and no regular effect, and all 17 JavaScript interop scenarios, with one computer effect and zero ordinary effects. Analysis remained clean.

Final guide review: the mixed-turn failure wording now matches the verified halt behavior, and its Dart block still matches the executable example exactly. The scoped 7.8/10 assessment remains unchanged.


## Round 13: Local model and Dart Frog consumer review

Baseline: **0/10 runnable integration for each new path**. At the start of the review, the Ollama package and both review cases were absent; the Dart Frog package contained only its pubspec. No consumer integration could be compiled or run. These are path-specific baseline scores, not an SDK-wide assessment.

Review uses loopback HTTP and scripted fixtures only. No model downloads, external provider calls, or paid usage.

Dart Frog final provisional score: **8/10 for the tested adapter path**. The handler and trusted identity callback are straightforward; the consumer still owns authentication, durable storage, deployment, and disconnection behavior through intermediaries. The loopback fixture passed with Dart 3.12.2 and assertions enabled: HTTP method/auth/invalid payload handling, forged body owner isolation, approval and server-stored continuation, history, typed generation, event replay with offset and foreign-owner isolation, and client subscription disconnect stopping the model. This is local HTTP evidence only, not proof for reverse proxies, production authentication, persistent-store restart, or every official client interaction. The guide's example compiles; workspace analysis initially reported a missing direct `dart_frog` dependency for example imports, sent to the implementation owner.

Ollama provisional score: **7.8/10 for the exercised local-model path**, not an SDK-wide score. Native client construction, typed SDK options and embeddings, structured generation, and approval continuation are approachable. Replay state and provider metadata remain deliberately server-side; the application must know that URLs are not fetched for image input and supply inline data. The first compile exposed the missing `EmbeddingModel.embed` implementation while it was being developed; the owner fixed it before the final run. The embedding method name corrected the earlier announced API.

Dart 3.12.2 with assertions enabled passed loopback tests for schema output, typed temperature, approval with no execution before resume, thinking and unknown fields plus native ID/index replay, hidden thinking and provider ID in UI hydration, terminal duration and cached token usage, immutable vector results, HTTP and malformed NDJSON errors followed by successful stream, inline image bytes, pre-cancelled token with no HTTP request, stream unsubscription with a surviving sibling, and borrowed HTTP client reuse after client close. Analysis of both review scripts and the Dart Frog example passed with no issues. The test does not establish real Ollama/model behavior, model downloads, production deployment, in-flight cancellation-token timing, every error/status or provider endpoint, or live JavaScript interoperability for the Dart Frog handler.

Final guide and API check: the first Dart block in `docs/ollama.md` matches `examples/ollama_demo.dart` byte-for-byte and compiles unchanged to a Dart kernel artifact. The guide's SDK option and embedding signatures match the current API; no live server or model was used. After the Dart Frog generation decoder gained trusted application context, the loopback fixture was updated to derive an execution parameter from that context and passed again. Analysis of both review scripts and both demo examples reports no issues. Scores remain unchanged.

Additional official JavaScript integration: the pinned TanStack client passed text, schema and stored approval/resume over a real Dart Frog SSE handler backed by `OllamaNativeClient` and a local fake NDJSON server. The fake verified thinking, unknown field, original native call ID/index and tool name/result on continuation; counters confirmed no tool effect before approval and one afterward. Owner isolation, private data absent from history, authenticated typed generation and redacted generation failure also passed. Dart analysis is clean. This is a local protocol fixture, not a live model, durable restart or proxy test; scores remain unchanged.


## Round 13: provider option review


Scope: selected pinned provider inventories, adapters and offline tests; not a complete field-by-field audit. No external provider or paid calls. Score: 6/10 for the reviewed all-provider developer experience: useful typed options and replay examples, but the requested complete parity is explicitly unfinished; this review found and then verified a fix for a common Gateway override failure.

### Finding and fix verification

Before the fix, Cloudflare Gateway `@cf/` requests rejected a client-default gateway ID whenever a per-request options object contains only another header, such as cache TTL. `_run` validated `(gateway ?? client.gateway)` in `packages/agent_weave_cloudflare/lib/agent_weave_cloudflare.dart` near line 470, whereas `_send` merges the client and per-request header maps. The input is valid under the merge semantics documented in `docs/cloudflare.md`. Validation now follows the merged headers; per-request keys override client defaults, absent per-request keys inherit client defaults, and do not mutate either map.

Reproduction: `.dart_tool/dart-3.12.2/dart-sdk/bin/dart --enable-asserts run examples/review_cases/provider_options.dart`. Before the fix it failed immediately with `Invalid argument(s): @cf models require a gateway ID.` After the fix, the same command passed with Dart 3.12.2. The consumer checks request cache/default precedence, default immutability, cache/request ID response headers and Together query/header forwarding after the Cloudflare check. The original failure occurred only when the request omitted the inherited Gateway ID; explicitly repeating it already worked.

### Coverage boundaries

The provider coverage page is appropriately qualified as an incremental inventory. Anthropic hosted tools and pause-turn, OpenRouter management/hosted tools/media, Together native legacy calls and multiple choices in the adapter, Vercel model semantics, and Cloudflare model-specific/live behavior are explicit gaps rather than newly discovered defects. OpenRouter tests cover selected ordered reasoning replay, Together tests exercise headers/query and reasoning replay, and Anthropic documents its raw/typed replay limitations. Fixture evidence cannot prove live billing, acceptance, cache hits or complete nested field semantics. This review did not exercise every option, streaming branch, native tool, or provider.

Existing Together test `dart test packages/agent_weave_together/test/together_test.dart --name 'native options snapshot and numeric logprobs; tools, schema and replay'` passed with the pinned Dart SDK. It verifies query, custom header, options snapshots, tool calls, schema, and reasoning replay through a loopback server.

### Guide and integration verification

Extracted the first Dart block from each Ollama and Dart Frog guide and analyzed both without executing them: no issues found with Dart 3.12.2. The Ollama and Dart Frog offline consumer programs passed. `node tool/interop/dart-frog.mjs` passed all four official JavaScript client scenarios using the pinned Dart SDK and local fixture server. These checks are offline, not live provider evidence.


## Round 14: Anthropic hosted tools consumer review

Scope: independent Dart consumer over a local HTTP Messages fixture. No provider key, paid calls, downloads, or live provider were used. Run with `.dart_tool/dart-3.12.2/dart-sdk/bin/dart run examples/review_cases/anthropic_hosted.dart`.

Initial expectation: configure a validated provider-hosted search tool at the model, run an ordinary agent, let `pause_turn` continue within the normal step budget, and retain opaque hosted blocks for automatic replay without treating them as application tools. Ordinary approval and persistence should work across a recreated agent.

Result: eight cases pass: search pause and follow-up replay, mixed server and approved app tool across recreated agents, two pauses exhausting maxSteps with checkpoint and accumulated usage, rejection of a new user message followed by empty-message recovery, truncated stream, unknown stop reason, cancellation, rejection of a server tool not configured by the application, and an opted-in programmatic code-execution call that pauses for local-tool approval. A typed SDK `WebSearchTool` configures the search; `message_delta` container metadata survives both automatic continuation and recreated approval resume. The fixture asserts private search-result content and citation metadata survive replay and are absent from hydration; it does not establish public citation rendering. It verifies no extra HTTP calls or application execution in the error paths. `dart analyze examples/review_cases/anthropic_hosted.dart` reports no issues.

During development the first compile failed because the API had not landed. A repeated-pause fixture initially reused a server tool ID and was rejected as INVALID_OUTPUT; distinct IDs made the intended step-limit scenario valid. These were fixture/timing issues. Inspection also identified that a hosted server call could be accepted when another hosted tool was configured; the implementation was corrected and the consumer negative case now rejects it without another HTTP call.

Scoped DX score: **8/10**. Native configuration is concise, and the same ordinary agent and approval APIs work across pause and recreation. Typed SDK hosted definitions work, while programmatic callers still require knowledge of provider wire names and the consumer must understand that citations remain private backend metadata rather than rendered UI output. This score covers only the tested native loopback flow, not all hosted tool variants or provider parity.

Not tested: live Anthropic behavior, actual search results, live container lifecycle, other hosted tool families, backend restart with durable storage, client citation display, or production networking. Fixture agreement cannot establish those capabilities.

Final frozen-code rerun: all eight consumer cases pass and the consumer analyzes without issues. Copied the first Dart block of `docs/anthropic-hosted.md` byte-for-byte into `.dart_tool/dx-review/round14/guide.dart`, verified equality, analyzed it without issues and compiled it to kernel without running it or calling a provider. Inspected replay, tool ownership, container configuration and hosted caller validation; the unconfigured hosted call identified during review is now rejected. This inspection is scoped and is not a comprehensive security audit.

Additional Dart client review: `examples/review_cases/structured_continuation_client.dart` runs the pinned `tanstack_ai_dart` ChatClient against a local SSE server and scripted model. Across two runs, including a structured-output pause and `MESSAGES_SNAPSHOT`, it observes exactly two completed outputs with the expected data; a newly attached client hydrates the same two completed outputs. The script runs successfully and analyzes without issues. This is local protocol interop, not Flutter device or live provider evidence.

Final programmatic fixture correction: the earlier fixture omitted the container needed for a pending programmatic call. After the runtime enforced that requirement, the fixture was updated to return a container and assert its replay after approval. Both the direct `20260120` caller and configured `20260521` alias with the `20260120` wire caller pass, as do all other loopback cases. Analyzer reports no issues. The earlier pass did not verify the required programmatic container.


## Round 15: OpenAI hosted tools and cross-provider guards

# Round 15: OpenAI Responses hosted tools consumer review

**Scoped score: 8.2/10.** The native Dart API makes the common hosted definitions straightforward, and its raw constructor provides a clear escape hatch for fields the pinned SDK cannot represent. The split between typed and native configuration and the need to inspect private provider data for hosted metadata take some discovery. This score covers only the local scenarios below, not overall provider parity or production readiness.

`examples/review_cases/openai_hosted.dart` uses a real loopback HTTP/SSE server and no provider credentials or paid requests. Dart 3.12.2 analysis reported no issues, and the consumer passed all twelve cases:

- Typed web and file search plus native code interpreter and image generation definitions, including unknown request and nested tool fields on the actual HTTP body.
- Four hosted output items and an application function call, exact unknown-field replay across a persisted approval and recreated agent, and private metadata excluded from hydration. A generated 1x1 PNG data URL is accessible in the result.
- Automatic local execution only after completion, plus EOF, incomplete responses, terminal call mismatch, pre-cancellation, and cancellation after the server flushed a call event without execution. An unrelated owner cannot resume an approval.
- Wrong-provider replay ignored; configuration cannot replace instructions, output schema or registered hosted definitions, or inject an unregistered function.

The initial run exposed an unregistered function injection through native configuration. After the implementation fix, that same case passed before dispatch. The initial image-result assertion also failed while the feature was being implemented; it passes on the final rerun.

Limits: this review did not call OpenAI, render the image, test every nested provider option or hosted tool, validate search quality, or exercise a live code container. Loopback fixtures cannot establish production provider behavior. Tool-search/MCP and other native continuation workflows are not certified by this score.

Additional media consumer review: `examples/review_cases/output_media_client.dart` passed against a local SSE server using a real 1x1 PNG fixture. The native Dart client received text-image-text in order live and after server hydration; provider replay remained private and another owner could not load the checkpoint. A separate PostgreSQL recreation test checks the same ordering and privacy, plus provider replay in a subsequent recreated agent request; it analyzes clean and passed in the coordinated PostgreSQL suite after the follow-up fixture declared image input capability. Neither fixture renders pixels or calls a provider.


### Independent contract and ownership review

# Upstream image-generation tool patch review

Static review of sparse worktree `.dart_tool/upstream/openai-image-tool-options` against pinned OpenAI Responses declaration and [current official request reference](https://developers.openai.com/api/reference/resources/responses/methods/create). No tests run here to avoid colliding with the root agent's checks; no paid requests. Reviewed upstream `AGENTS.md` and `.agents/skills/create-pr/SKILL.md` via `git show` because sparse checkout omits that file.

## Findings

1. **P2 — mask representation enforces a stricter contract than the published schema.** `ImageReference.fromJson` (`packages/openai_dart/lib/src/models/images/image_edit_json_request.dart:27`) requires exactly one of `file_id` and `image_url`, and its constructor relies on an assert for that invariant. The Responses API and pinned TypeScript `Tool.ImageGeneration.InputImageMask` declare both keys independently optional; no exclusivity requirement is specified. New tests label empty and both-key objects invalid. Those cases are schema-permitted but not verified accepted by the live API, so this is a schema-parity risk rather than a claimed production failure. Either establish an authoritative stricter rule or use a dedicated mask model with independently optional fields and appropriate tests. Importantly, Dart asserts are disabled in production, so direct construction can bypass the assumed invariant regardless.

2. **P2 — unknown enum values are silently changed on a request round-trip.** `ImageModerationLevel.fromJson` and `ImageInputFidelity.fromJson` convert unrecognized strings to `.unknown`, which serializes literally as `unknown`. For example future `moderation: 'future'` is changed instead of preserved or rejected. The current API only documents auto/low and high/low; this is forward-compatibility risk rather than a supported-current-value failure. Consider rejecting unknown values for request models or preserving raw strings; add a decoding test for each. Avoid silently asserting unknown inputs are lossless.

3. **P3 — model option combination in the new fixture is not an official supported example.** It pairs `model: gpt-image-2.5-flare` with `input_fidelity: high`; current reference documents fidelity for `gpt-image-1.5` and `gpt-image-1-mini`, not 2.5. This offline serialization test doesn't call the provider, but `gpt-image-1.5` would make the example contract-coherent. Model-specific acceptance remains untested.

## What looks correct and release guidance

The patch updates factory and constructor, reads/writes the structured mask, string moderation and integer compression, adds action and fidelity, and updates equality/hash consistently. New tests exercise both normal mask variants, exact request/tool round-trips, omission/null, wrong wire types and identity. The change breaks caller source compatibility for three existing parameter types. `AGENTS.md` requires conventional breaking marker; create-pr skill requires `## Breaking Changes` with before/after migration examples and accurate `## Test Plan`. Include replacements for all three parameters and an official API reference. No other repo callsites using changed parameter names were found by `rg`.

The reference additionally specifies output compression 0–100 and partial images 0–3. Current patch preserves any integer; whether to validate locally should follow the package's existing boundary-validation policy rather than invent extra constraints. Existing enum fallback and shared ImageReference behavior predate this patch, but reuse makes them visible in this new API path.

## Re-review of revision

The revised patch resolves all three observations: `ImageGenerationMask` models two independent optional fields and tests empty/both-key cases, unknown moderation/fidelity values are rejected in decoding and encoding instead of rewritten, and the fixture uses `gpt-image-1.5`. No new actionable defect identified by static review. This is not an API acceptance or live execution check; no tests were rerun here.

## Cross-provider concrete finding

The shared Chat Completions configuration guard accepts extra unregistered function tools. `_preserveRequest` in `packages/agent_weave_openai/lib/src/chat_models.dart` only requires each canonical tool to appear once. A callback can add a new function with no corresponding runtime tool, so the provider may call a tool the runtime cannot execute. Reproduced using an actual OpenRouter `MockClient` and no registered tools with `.dart_tool/dx-review/round15/rogue_chat_tool.dart`; it printed `Reproduced: unregistered tool sent with no runtime tools`. Shared delegates affect OpenRouter, Vercel Gateway and Cloudflare compatible Chat adapters as well as OpenAI. The native APIs and Responses-specific hosted tool controls are separate.

Regression `packages/agent_weave_openai/test/chat_tool_ownership_test.dart` tests additions with zero and one registered tool (both fail before fix), preserves an unmodified registered tool and rejects removal (existing guard handles removal). Fix Chat tool ownership by requiring configured tool definitions to match canonical registered definitions, accounting for absent versus empty arrays. Do not globally disallow hosted Responses additions as that protocol has a separate hosted-tools contract. Remaining listed provider coverage gaps are not established as new defects by this review.

## Round 15 follow-up: shared codec and provider guards

Static review scope: changed core JSON helpers, provider replay/ownership guards, OpenAI Responses parser, media snapshots, and selected compatible provider wrappers; not a whole-codebase security audit. Scoped score 6/10: selected regressions verify real failures but broad provider parity and live behavior remain open.

The Chat ownership fix and conditional OpenAI-only Responses hosted-tool exception are verified by local mock HTTP wrapper tests. `test/compatible_responses_tool_ownership_test.dart` passes all three OpenRouter/Vercel/Cloudflare additions checks; `test/compatible_chat_tool_ownership_test.dart` adds native `int` versus `double` edge cases. Shared `jsonEquals` initially still used Dart scalar `==`: the pinned Dart VM considers `9007199254740993 == 9007199254740992.0` true, and all three compatible Chat wrapper tests confirmed this reaches HTTP. Fix must compare integral doubles with exact integer conversion and handle signed-int bounds, including `+2^63` saturation. As of the failing run, these three cases were red pending root's concurrent fix.

`packages/agent_weave_anthropic/test/tool_ownership_test.dart` reproduces the pre-fix integer-to-integer `canonicalJson` collision and now passes with the native guard fix; adding a wholly unregistered native tool is rejected. `packages/agent_weave_ollama/test/tool_ownership_test.dart` verifies a forged replay tool argument differing by one above 2^53 fails before HTTP. Together normalized Chat exposes no arbitrary configure callback and serializes runtime tool definitions after its typed options; no matching extra-tool injection found in the inspected path.

OpenAI hosted image option `output_compression` validation currently accepts any numeric value from 0 to 100, including fractional numbers; official Responses reference specifies integer. Reject fractional values and add an offline invalid-input test. This is provider validation, not evidence of a live service failure.

## Final fix verification

Root fixed mixed int/double comparisons using finite integral validation and exact `BigInt` comparison. Reran all five independently owned regression files with pinned Dart 3.12.2: **20/20 passed**, including all three compatible Chat nested-double cases and compatible Responses tool ownership. Root also tightened hosted image compression to `int`; independent assert-based check `image_compression_check.dart` confirmed 2.5 is rejected. Prior findings are resolved within this offline scope. No paid requests or exhaustive provider/security audit were performed.

Final guide review: the first Dart block in `docs/openai-hosted.md` byte-matches `examples/openai_hosted_demo.dart` (1,112 bytes). Dart analysis and kernel compilation both passed without running the billable example. Inspection of the current hosted API and guide found no actionable mismatch or unsafe instruction; the guide explicitly flags billing and server-side credentials. This is a source-level review, not a live provider test.
