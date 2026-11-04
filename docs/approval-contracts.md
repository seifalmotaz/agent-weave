# Persisted tool approvals

An approval applies to the tool contract that produced the pending call.
Recreating an agent must not reinterpret a client result as a server approval
or execute a call under changed schemas or native bindings.

AgentWeave records a versioned `toolContract` snapshot in private pending state.
Before resuming, it compares the complete resolution batch with the current
tool definitions. No executor or subsequent model request runs until every
pending contract and answer has been validated.

## What the contract binds

The snapshot contains the tool's name, description, input and output schemas,
function/native kind, client execution and approval flags, and sequential
failure-policy trait. Native tools also bind their provider, execution binding
and declared native definition.

Comparison retains Dart integers and ignores JSON object-key order. Equivalent
integer and integral-double values compare equally when their values are
exactly equal. Adjacent large integers and rounded doubles do not become equal
through JavaScript conversion. Memory and PostgreSQL tests exercise these rules.

The contract does not serialize Dart closures, application permissions or live
driver state. If an executor's meaning changes without changes to its declared
configuration, version the tool name or native binding. Keep authorization and
idempotency checks in the application service.

## Private contracts and public client hashes

| Data | Purpose | Where it belongs |
| --- | --- | --- |
| `toolContract` | Exact declared tool contract for server-side resume validation | Private pending checkpoint |
| `schemaHash` | Existing TanStack interrupt-binding compatibility, including JavaScript number semantics | Public protocol binding |

The public binding format and hashes remain unchanged. A protocol-compatible
hash is not proof that two Dart schemas are identical. Server-owned approval
checks do not rely on it.

Contracts contain full schemas and native configuration. They stay out of
public events and `chatHydration`, like other private continuation data. Custom
stores must round-trip the complete opaque checkpoint without dropping fields
or converting native integers to doubles.

JavaScript clients still have JavaScript's numeric limits. This change does not
make cross-language JSON integers above the safe JavaScript range exact; use
strings for identifiers that must survive such clients without rounding.

## Recovery and migration

Changed, missing, malformed or unsupported contracts fail with `INVALID_INPUT`
before side effects. The original pending state and history are preserved.
For a changed configuration, retrying with the original complete contract can
resume the original approval.

Checkpoints written before exact contracts were introduced cannot prove the
original contract. Their old hashes cannot reconstruct it. The SDK rejects
those approvals rather than inventing a snapshot from the current tool.
Start a new conversation; retain the old one for history. This is a pending
checkpoint migration, not a database-table migration. Do not automatically
replay an old call or copy its unfinished tool state into a new conversation.

Both `run()` error events and `AgentRunException.message` provide a safe recovery
instruction. Future callers can display `message` and inspect `code`.
`cause` and `causeStackTrace` remain backend diagnostics and must not be returned
to a client. Provider exception text is not used as the public message.

## Reproduce the checks

```sh
dart run examples/review_cases/approval_contract.dart
dart test packages/agent_weave/test/approval_contract_test.dart
dart run tool/check.dart
```

The independent consumer tests input/output schema collisions, native
definitions, client/server execution changes, whole-batch validation, owner
isolation, equivalent schema ordering, original-contract retry and legacy
recovery. PostgreSQL tests recreate agents and verify exact integer persistence
and rejection before model or executor invocation. Ordinary client approval
flows continue through the existing JavaScript and Dart interoperability suite.
