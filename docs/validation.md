# Validation

This is development version `0.1.0-dev.1`. A passing test verifies its named
scenario. It does not certify every provider endpoint or production deployment.

## Reproduce the offline checks

Requires Git, Dart 3.12.2 or later, Node.js 22 or later, npm, and Python 3.
The first run downloads dependencies and Serverpod's embedded PostgreSQL binary.
No API key is needed. Ordinary tests force the offline provider even if a key
exists in the environment.

```sh
dart pub get --enforce-lockfile
dart run tool/check.dart
```

The check includes formatting, strict static analysis, generated LLM-document
freshness, credential-pattern scanning, unit tests, PostgreSQL/network tests,
and interoperability with the pinned official JavaScript client.

## Verified locally

On Dart 3.12.2 and 3.13.3:

- 83 Dart unit and regression tests: tool validation, approvals, client tools,
  lineage, cancellation, partial-response retention, safe failure history,
  generation, storage, protocol parsing, and provider fixtures.
- 6 Serverpod integration tests with a real isolated PostgreSQL database:
  authenticated endpoints, a generated-client WebSocket, HTTP/SSE, history,
  replay, owner isolation, event persistence, and reservation contention.
  The HTTP test also runs the official JavaScript client against real Serverpod
  chat and generation routes, including a second turn and persisted history.
- 7 standalone official JavaScript client scenarios against a Dart HTTP server:
  text, server tools, approvals, client tools, reasoning, structured output,
  and generation.
- 2 offline checks for the upstream operation-index parser.
- The offline chat example executes successfully.

Provider fixtures cover Responses and Chat Completions streams, schema output,
usage, opaque reasoning replay, cancellation, image/audio/embedding/Decisions/
video requests, binary and multipart transport, and the raw API helper. Realtime
uses an actual local WebSocket; it does not contact OpenAI.

CI is configured to repeat the offline checks on Dart 3.12.2 and stable on
Linux. Check the repository's current Actions run before treating that matrix
as verified.

## Live OpenAI evidence

Eight explicitly authorized requests passed on November 3–4, 2026 UTC:

| Check | Provider model | Evidence |
| --- | --- | --- |
| Responses text | `gpt-5.4-nano` | Stream completed; usage returned |
| Chat Completions text | `gpt-5.4-nano` | Stream completed; usage returned |
| Structured output | `gpt-5.4-nano` | Schema-validated JSON |
| Server tool round trip | `gpt-5.4-nano` | Two invocations; tool executed and answer completed |
| Embedding | `text-embedding-3-small` | Requested vector dimensions returned |
| Image | `gpt-image-2` | One low-quality 1024×1024 image; 725,797 PNG bytes |
| Speech | `gpt-4o-mini-tts` | Short speech request; 36,044 WAV bytes |

Chat invocations reported 212 input and 51 output tokens in total. The image
reported 16 input text tokens and 196 output image tokens. Provider billing is
authoritative; these observations are not an invoice.

`tool/live_smoke.dart` and `tool/live_media_smoke.dart` are opt-in. They share
`.dart_tool/live-budget.json` and never run in CI. The ledger conservatively
reserved $2.75 across the eight requests, within the user's $5 maximum. The
current guard refuses requests beyond $4 in cumulative reservations. Actual
usage cost is much lower than those reservations. Do not reset that ledger to
bypass the cap. The guard is a bounded test allowlist, not a general billing
system. Keep keys in environment variables only.

## Package validation

All six package publication dry-runs passed with zero warnings from a clean
checkout. Core and OpenAI API documentation generated with zero warnings or
errors. Serverpod code generation was rerun without changing the checked-in
outputs. The native client reports
an override hint because its `tanstack_ai_dart 0.4.0` dependency is Git-pinned
in this workspace and was not published to pub.dev at validation time. Resolve
that dependency before publishing the native client. A local dry-run does not
prove that pub.dev can resolve the entire unpublished package family.

## Not verified live

No paid video jobs, realtime sessions, transcription, Decisions, administration,
storage jobs, or other delegated resources were invoked. Their local fixtures
and typed SDK access do not substitute for account-specific live tests.

Flutter device rendering, microphone permissions, audio playback, WebRTC,
production authentication, production deployment, and pub.dev publication have
not been tested or performed. See [compatibility](compatibility.md) for remaining
implementation limits.
