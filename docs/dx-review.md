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
