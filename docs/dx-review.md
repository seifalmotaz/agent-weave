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
