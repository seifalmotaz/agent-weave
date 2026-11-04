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

The latest Gateway/protocol increment was checked on Dart 3.12.2. The prior
147-test baseline was also checked on Dart 3.13.3.

- 222 Dart unit and regression tests: tool validation, approvals, client tools,
  lineage, cancellation, partial-response retention, safe failure history,
  generation, storage, protocol parsing, and provider fixtures.
- 13 Serverpod integration tests with a real isolated PostgreSQL database:
  authenticated endpoints, a generated-client WebSocket, HTTP/SSE, history,
  replay, owner isolation, event persistence, and reservation contention.
  The HTTP test also runs the official JavaScript client against real Serverpod
  chat and generation routes, including a second turn and persisted history.
- 14 standalone official JavaScript client scenarios against a Dart HTTP server:
  text, server tools, approvals, client tools, reasoning, structured output,
  generation, and seven media/history cases. The media cases include document
  URL, inline bytes, scoped and unscoped file handles, image/video URLs, and
  inline audio; returned parts pass the official AG-UI schemas.
- 2 offline checks for the upstream operation-index parser.
- The offline chat example executes successfully.

Provider fixtures cover native Anthropic Messages and OpenAI Responses/Chat
Completions streams, schema output,
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

The initial six-package publication dry-runs passed with zero warnings from a
clean checkout. That evidence predates the Anthropic and OpenRouter packages. The new OpenRouter
package also passed a publication dry-run with zero warnings on Dart 3.12.2. Core and OpenAI API documentation generated with zero warnings or
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

## Native Anthropic increment

Thirteen native Messages fixture tests and a separate consumer over real loopback
HTTP verify selected text, schema, tool, thinking replay, cache configuration,
error and cooperative cancellation contracts. No live Anthropic account, model,
real cache hit or network-abort behavior was tested. The independent review is
8.0/10 for the reviewed general SDK journeys and provisionally 7.8/10 for the
new native provider path; see [the review record](dx-review.md).

## Persisted approval process restart

The isolated PostgreSQL test now starts the actual backend and approval CLI in
separate processes, exits both, starts a fresh backend against the same database
files, and restores/resolves the pending approval from a fresh client. A further
fresh client rejects the already-completed decision. The independent Terra
reviewer reran the test successfully on Dart 3.12.2 and scored this targeted
journey 8.5/10. This is graceful restart evidence, not arbitrary-crash recovery
or proof of exactly-once external effects.

## Documents and OpenRouter increment

Fifteen core document tests cover construction, validation, storage and authorized
history round trips, legacy source aliases, capability rejection, and releasing
reservations without erasing an unreadable snapshot. Provider fixtures verify
Responses URL/data/file-ID mapping and foreign-provider rejection; Anthropic PDF
URL, PDF bytes and UTF-8 text plus unsupported ID/format failures.

Three OpenRouter loopback tests verify selected routing/header options, streamed
tool arguments, actual model usage, inline errors and pre-cancellation. Two
independent consumer programs, `examples/review_cases/documents.dart` and
`examples/review_cases/openrouter.dart`, run in the normal check. The reviewed
journeys scored 8.0/10 and 7.8/10 after documentation fixes. Neither score
certifies complete provider support. No new live API calls were made.

## Native Together increment

Eighteen Together tests run a local HTTP service and cover native numeric
`logprobs`, immutable options, schema/tool serialization, reasoning replay,
fragmented tool arguments with repeated IDs/names, usage after finish, bounded
text output, native metadata, multi-choice EOF, stream/HTTP errors and private
diagnostics. Cancellation is tested before sending, before response headers and
during the body. Cancelling the native stream subscription also aborts a
pending request without closing the shared client; a stalled response tests
per-request timeout. These are real
local HTTP tests, not live Together calls.

The independent consumer program exercises schema output, a stored tool approval
and continuation, reasoning/tool replay, partial output and error diagnostics.
Its targeted offline DX score remains 8/10; it does not certify production
behavior or all native fields.

The offline AST tool has three parser/coverage tests. It extracts the pinned
official SDK declarations and checks all 27 top-level chat request fields have
reviewed dispositions. An executable Dart fixture serializes every typed option.
`--upstream` was also run against current official source and found no difference
in the pinned files. No new paid requests were made.

The Together package publication dry-run passed with zero warnings on Dart
3.12.2. This is packaging evidence, not a pub.dev publication.

## Gateway, protocol and shared transport increment

Seven Gateway fixtures cover separate public Chat/Responses requests, routing
serialization, concurrent rotating bearer/BYOK credentials, private redacted
HTTP and SSE diagnostics, request cancellation and controlled native extensions.
Nine shared HTTP tests cover fragmented UTF-8/CRLF/multiline SSE with event IDs
and headers, credential-wait cancellation/deadlines, late-dispatch prevention,
pending-header cancellation, custom clients with stalled bodies, malformed frames,
request validation and borrowed-client ownership. Together's existing 18 tests
pass against the shared transport.

The 28 OpenAI chat/protocol tests now include protocol and actual SDK two-turn
Chat tool continuation, assistant text/null encoding, provider replay/file-handle
isolation, explicit unsupported choices/audio, Responses EOF, and independent
subscription cancellation with a concurrent request. Three core tests cover
sticky cancellation events and disposable listeners.

The independent Gateway consumer tests both protocols through schema generation,
stored approval/resume, request credential rotation, serialized UI hydration,
wrong-provider replay exclusion and native response metadata. Both public guide
examples compile unchanged. Its documented targeted score progressed from 5.8
to 6.4 and then 7.6/10 after fixes. These are local fixtures, not a live Gateway
account, Flutter UI, secret manager, route selection, cache hit or billing test.

The five AST/coverage parser tests and executable Dart fixtures verify reviewed
Together fields and 16 named Gateway SDK options. The Gateway source type permits
unknown service options; classifying its fields does not prove a complete public
HTTP contract. No new paid provider calls were made.

Both new HTTP and Gateway package publication dry-runs passed with zero warnings
on Dart 3.12.2. Neither package has been published to pub.dev.
