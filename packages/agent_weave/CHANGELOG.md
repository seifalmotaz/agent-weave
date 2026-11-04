# Unreleased

- Add ordered completed media parts, sanitized client snapshots and hydration.
- Add lossless typed JSON patches and exact numeric JSON comparison for provider ownership guards.

- Preserve typed structured results in history and replace paused structured placeholders with sanitized snapshots.

- Add checkpointed, step-bounded provider continuations and protect pending turns from new user input.

- Add sequential native batch policies, bind them across approvals, and pause whole mixed turns before execution when required.

- Add provider-namespaced native tool calls and approval-only continuation,
  with definition and environment binding and closed continuations on denial
  or failure. Client-executed native tools are unsupported.

- Isolate stream subscription cancellation per call while retaining shared parent cancellation.

- Add a disposable cancellation event stream while preserving the existing Future signal.

- Add URL, inline bytes, and provider-scoped document inputs with canonical media hydration.
- Release run reservations safely when stored history cannot be decoded.

- Add typed result APIs, scripted providers, atomic run completion and failure recovery.

## 0.1.0-dev.1

Initial development version. See the workspace compatibility and validation
documents for implemented contracts, tests, and remaining work.
