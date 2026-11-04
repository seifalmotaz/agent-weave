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

The latest hosted-tools and provider-guard increment was checked on Dart 3.12.2. The prior
147-test baseline was also checked on Dart 3.13.3.

- 427 Dart unit and regression tests: tool validation, approvals, client tools,
  lineage, cancellation, partial-response retention, safe failure history,
  generation, storage, protocol parsing, and provider fixtures.
- 17 Serverpod integration tests with a real isolated PostgreSQL database:
  authenticated endpoints, a generated-client WebSocket, HTTP/SSE, history,
  replay, owner isolation, event persistence, and reservation contention.
  The HTTP test also runs the official JavaScript client against real Serverpod
  chat and generation routes, including a second turn and persisted history.
- 20 standalone official JavaScript client scenarios against a Dart HTTP server:
  text, server tools, approvals, client tools, reasoning, structured output,
  generation, two provider-continuation cases, and eight media/history cases, including ordered output images. The media cases include document
  URL, inline bytes, scoped and unscoped file handles, image/video URLs, and
  inline audio; returned parts pass the official AG-UI schemas.
- 4 additional official JavaScript scenarios use actual Dart Frog handlers and a
  local fake Ollama NDJSON service: text, schema, approval/resume and authenticated
  typed generation, including owner isolation, privacy and safe errors.
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

## Cloudflare and cancellation increment

Sixteen Cloudflare fixtures cover distinct native, Gateway and compatible wire
contracts, model-schema GET queries, embedding shape/pooling, binary and JSON
audio, binary images and decoded Flux image JSON, request snapshots, credential
rotation/redaction, approval and the documented single-call native continuation.
Raw streaming cancellation is checked after headers and a data event. Client
Gateway defaults and explicit request overrides preserve authentication.

The independent consumer exercises both compatible protocols through two-turn
tool continuation, typed media results, stored native approval, cancellation
during credential resolution and after sending, and Gateway header inheritance.
Its after-headers streaming fixture also passes over actual loopback HTTP. The
complete guide entry program was compiled unchanged, without invoking Cloudflare.
The targeted review improved from 7/10 to 8/10; it is not SDK-wide acceptance.

Twelve shared HTTP tests now include GET/HEAD with repeated queries, binary PATCH
bytes and immutable snapshots, MIME/byte validation and body/method rejection
before dispatch. Shared stream binding isolates sibling calls while synchronously
propagating parent cancellation. The full suite caught and now prevents an extra
buffered text chunk entering cancelled history. Core, provider and generation
regressions verify cleanup and independent shared-parent calls.

The Cloudflare extractor has five tests for reference closure, escaped and
recursive schema references, nested unions/constraints, and explicit operation
status. It records all 82 operations across 50 AI/Gateway paths in the pinned
OpenAPI, four selected integrations, and six public model schemas with hashes.
The explicit upstream comparison matched current official sources. Compatible
Chat/Responses endpoints are documentation-only contracts outside that OpenAPI
revision; their separate fixtures do not certify all fields or models.

The documentation build and two routing/search tests pass. The Cloudflare package
publication dry-run has zero warnings. No package was published, no model license
was accepted, and no paid Cloudflare or other provider calls were made. Live
model availability, Gateway routing/cache hits, binary audio Content-Type
acceptance, billing, management operations and exhaustive provider parity remain
unverified or unimplemented as listed in the inventory.

## Native OpenRouter and lossless Responses replay

Fourteen OpenRouter fixtures cover native typed options and guarded JSON
extensions, ordered Chat reasoning, stateless Responses replay, raw metadata,
per-request credentials, malformed SSE, resolver errors, cancellation and client
ownership. The shared Responses codec now uses immutable raw input snapshots,
retaining reasoning and valid tool-output fields the typed input decoder could
reject or omit. Forty Chat/Responses codec tests include unknown fields,
actual SDK encrypted-reasoning replay, pre-callback canonical snapshots, missing
instructions, alternate token bounds and stream-option protections. Usage
model identity comes only from reported response data, including earlier stream
frames; it is not guessed from a requested alias. Together has the same rule.

The independent native consumer tests schema generation through both protocols,
persisted approval and resumed tools, recreated agents, opaque ordered reasoning,
IDs/statuses and matching tool outputs, no private replay in UI hydration,
actual model/provider/cost metadata, absence of usage, credential rotation,
redaction, network cancellation and borrowed-client ownership. The guide's first
program was compiled unchanged without paid execution. Its five qualitative
ratings average 7.6/10 after the guide and fixture changes. This is a targeted
review, not SDK-wide acceptance or live service evidence.

The OpenRouter source inventory accounts for 146 operations across 108 paths
and records reusable component fields without expanding recursive references
at every use. Six new extractor tests and the five Cloudflare extractor tests
pass; the refactored shared helper produces the unchanged Cloudflare inventory.
The explicit upstream OpenRouter comparison matched the pinned document hash.
Only Chat and Responses have selected integrations; other operations remain
not integrated. Source forwarding does not implement every response union or
background job.

No new paid requests or package publications were made. Live OpenRouter routing,
cache hits, cost/billing, model-specific reasoning fragments, management APIs,
hosted tools and output media remain unverified or unfinished.

OpenRouter credential-shaped source examples are deterministically redacted
before storage and generation. Original-source and retained-snapshot hashes
are verified separately. The local credential scan also checks OpenRouter key
formats and includes the full source snapshots.

## Native computer increment

Seven core tests cover native definitions and call snapshots, provider/kind
matching, mandatory approval, atomic answer validation, definition/environment
binding, denial and closed continuation. Fourteen OpenAI computer tests cover
GA and preview tools, all nine action types and their parameters, five preview
environments, screenshot forms, exact safety acknowledgements, terminal status,
immutability and rejection of unknown action fields before execution. Three
provider guard tests reject foreign native definitions and history before HTTP.
All 85 OpenAI package tests pass with the raw Responses SSE transport, including
SDK cancellation and shared-client ownership regressions.

The PostgreSQL test persists and reloads a pending native approval, rejects
changed targets, resumes once and rejects a duplicate decision. It uses the real
store and a scripted model, not a paid provider or computer driver. Two new
standalone official JavaScript client cases exercise native approval and denial
through generic interrupts, history hydration and privacy.

The independent computer consumer runs 15 loopback scenarios through the actual
SDK client with an application-owned fake executor. It verifies ordered actions,
approval/continuation with a recreated agent, exact IDs, private raw replay,
UI privacy, malformed/truncated responses, cancellation and unknown action/drag
fields. The complete driver guide analyzes and compiles unchanged. The targeted
qualitative DX score is 7.8/10; see [the review](dx-review.md).

Four source-contract tests plus an executable Dart fixture check selected pinned
official Node declarations, nested action fields, preview environments and
controlled acknowledgements. The explicit upstream comparison matched the
selected projection. These checks do not certify the full Responses API.

No real operating system, browser, driver or provider computer session was run.
GA nonempty safety acknowledgements, screenshot image contents, actual driver
idempotency and crash recovery remain unverified. No paid requests or package
publications were made in this increment.

## Native Anthropic transport and lossless normalization

The 37 Anthropic tests include 15 new native transport fixtures and nine new
protocol/configuration regressions. They verify request/response JSON snapshots,
version and attribution headers, repeated queries, create/count/GET access,
credential rotation and redaction, malformed/error/EOF handling, request deadlines,
pre-cancellation and cancellation during credentials, headers and stalled bodies.
Actual local HTTP tests verify independent sibling calls and borrowed-client use.

The raw normalizer preserves original fields on supported content blocks, private
citations, signed thinking, message metadata and final cumulative cache and
thinking-token usage. Typed SDK configuration changes are applied to the raw
request without erasing unchanged unknown fields. Tests reject canonical-history
mutation, absent-field injection, output-schema replacement and mismatched deltas.

The independent native consumer runs text/schema, stored approval and recreated
agent continuation, private replay and UI hydration, cache options, final usage,
citations, rotation, diagnostics, cancellation, ownership and malformed frames.
Its targeted score is 8.4/10. The guide's first program matches the example,
analyzes and compiles on Dart 3.12.2 without executing a paid request.

Four AST tests verify request field dispositions and selected nested declaration
and union drift. The inventory records 19 top-level fields and 251 locally
referenced declarations from the pinned official SDK. The current upstream
comparison matched the projection. Imported types, unrelated endpoints and
complete nested runtime semantics remain outside this evidence.

[Upstream SDK PR #432](https://github.com/davidmigloz/ai_clients_dart/pull/432)
fixes stalled-request cancellation separately. All 1,796 Anthropic SDK unit tests
passed locally with three environment-dependent skips, and package analysis was
clean. These used the locally available workspace package configuration; a clean
repository bootstrap and live tests were not run. The PR is submitted, not merged
or released, and AgentWeave's native client does not depend on it.

No live Anthropic requests or cache hits were tested, and no paid requests or
package publications were made. Hosted/browser tools, pause-turn and complete
endpoint/nested-option parity remain unfinished. Selected computer and native
file-ID integration are verified in the increment below. Provider error details retain private content after credential
scrubbing and must not be exposed directly to UI or logs.

## Anthropic computer toolset and scoped files

Six core tests cover sequential native result policies, stopping mixed-turn
executors after failure, resetting policy for the next model turn, forced and
configured whole-turn approvals, and binding the result policy across resumes.
Six typed-helper tests cover all 17 input field sets, named coordinate records,
scroll enums, direct callers, configs, selected limits, safe call snapshots and
text/image/error results. Successful screenshots and zoom require an image;
cursor position requires nonempty text. Decoded image contents remain unchecked.
Protocol regressions also verify block-index order and native file-ID documents,
including a clear failure for unsupported typed SDK configuration.

The independent consumer passes 13 loopback modes, including all actions,
approval and recreation, mixed failure stopping, disabled/unknown actions,
malformed calls, truncation, cancellation and hydration privacy. Its targeted
score is recorded in [the review](dx-review.md). The complete guide matches its
example and was checked without invoking a live provider or driver. The new
pinned official JavaScript client case resolves all three mixed-turn approvals,
rejects editable native arguments, verifies ordered results and no later effects
after the computer error, and hides private provider/environment state.

A real PostgreSQL test uses the native client's loopback HTTP transport. It
persists both approvals, rejects a changed environment, recreates the agent and
store, executes the first action once, skips the second after error, verifies
full private replay and matching result IDs/toolset names on the next HTTP
request, excludes private state from UI hydration and rejects duplicate resume.
This is recreated-instance persistence, not a computer-specific process-crash test.

Two AST mutation tests and an executable Dart fixture compare 68 selected
computer/caller/result/image declarations, actual helper/config serialization,
all input fields and requiredness, scroll values and result payloads with the
pinned official SDK. The current upstream projection matched. Documentation-only
overrides, including direct callers, are explicit. PostgreSQL suites run one file
at a time to bound test database disk use; contention tests still issue concurrent
requests. A first parallel local run exhausted disk and was discarded before the
clean rerun.

No real desktop effects, image capture, live model support or provider permissions
were verified, and no paid requests or package publication occurred. Browser and
other native toolsets remain unfinished. SDK PR #431 is still needed for its
published typed decoder to represent file-ID sources; native normalization does
not require that unreleased change.

## Ollama and Dart Frog increment

Thirty-three Ollama tests cover native JSON and NDJSON, rotating optional
credentials, queries, immutable snapshots, errors and completion/EOF, independent
cancellation, stalled requests and borrowed clients. Agent fixtures check typed
options, runtime-owned request guards, schema output, thinking/native ID/index
replay, private raw frames, truncated/conflicting tool calls, inline images and
immutable embedding vectors with validated metadata. A root guard rejects foreign
native tools and history before sending. No Ollama daemon or model was available,
and no model was downloaded.

Six shared HTTP tests add fragmented UTF-8 and CRLF NDJSON, valid final lines,
malformed/non-object data, cancellation and deadlines across preparation, headers
and body, sibling isolation, pause/resume and borrowed-client reuse.

Two Dart Frog test groups exercise actual HTTP chat, approval/resume, owner-scoped
history and replay, authentication-bound context in typed generation and invalid
requests. Independent consumers additionally test disconnect cancellation. The
pinned official JavaScript client passes four scenarios through the real handler
and native Ollama client against a local fixture. These do not prove proxy
behavior, production authentication or durable restart for this adapter.

The Ollama source inventory covers four selected operations, nested OpenAPI
schemas and reviewed Go-only additions. Three extractor tests and the explicit
upstream byte comparison pass. First guide programs match their runnable examples
and analyze on Dart 3.12.2. The Ollama program also compiles without execution;
the offline Dart Frog server ran and returned a completed SSE response.

The independent scores are 8.0/10 for Dart Frog and 7.8/10 for the exercised
Ollama path. A separate selective provider review remains 6/10 and reproduced
a Cloudflare bug: request cache overrides wrongly discarded an inherited Gateway
ID during validation. The fix and consumer regression preserve default/override
precedence and response request/cache metadata. These judgments are scoped, not
an SDK-wide acceptance pass. No paid requests or package publications were made.

## Anthropic hosted tools and provider continuations

Ten hosted-tool test groups verify typed SDK snapshots and native extension
fields, all six pinned hosted result families, fragmented server input, preserved
containers and tools, duplicate/mismatched IDs, local-name collisions, caller-version aliases, missing containers, complete
client-result batches and explicitly opted-in programmatic callers. Hosted calls
never emit local executor events. A public-boundary contract script accepts all
15 official server-tool type spellings from the existing pinned inventory and
rejects known client tools. This is not exhaustive nested option validation.

Six core tests cover counted provider continuations, usage, checkpoints, step
limits, new-user rejection and explicit recovery, final schema validation,
structured message serialization/hydration, legacy data and contradictory
local-tool continuation. The PostgreSQL fixture reloads a paused native
Anthropic code-execution turn through a recreated agent/store, preserves the
container and tools, isolates owners, resumes with no new user message and
hydrates the final structured answer. This is not a process-crash test.

Two new official JavaScript scenarios exercise text and structured pauses. The
stricter structured fixture exposed an errored intermediate placeholder despite
a successful final answer. The runtime now sends a sanitized message snapshot
for intermediate structured progress and persists completed structured data.
Both the JavaScript client and a separately written Dart ChatClient consumer
verify two runs and restored hydration without spurious structured errors.

The independent Anthropic consumer passes eight loopback scenarios, including
typed SDK hosted configuration, opaque search/citation replay, delta containers,
programmatic app-tool approval, ordinary mixed approval with recreated agents,
step-limit recovery and no extra dispatch on malformed/EOF/cancellation. Its
scoped score is 8/10. The guide's complete first Dart program matches its
executable example and was analyzed and compiled without paid execution.

No live search, fetch, code execution, tool search, container, files or billing
was exercised. Browser/MCP tools, public citation rendering and full nested
semantics remain unfinished. No paid calls or package publications were made.


## OpenAI hosted tools and provider guards increment

Selected hosted Responses tool definitions preserve native and unknown options
before SDK decoding. Completed image results retain text-image-text ordering in
Dart results, both clients and recreated PostgreSQL history. Private replay and
metadata stay out of public history. Fixtures verify no application tool runs
before a complete, consistent terminal response, including EOF, incomplete,
mismatched and cancelled streams.

The native Dart consumer passes 12 loopback cases and scores the selected path
8.2/10. Its separate SSE/hydration case and the real PostgreSQL recreation test
pass. The first PostgreSQL fixture incorrectly selected a text-only follow-up
model; declaring its image capability corrected that fixture. The Gateway and Cloudflare
consumers previously emitted a done function call missing from its terminal
output; correcting those inconsistent fixtures restores their tool flows.

Twenty independent regressions exercise runtime-owned tool/schema guards through
actual OpenRouter, Vercel Gateway and Cloudflare wrappers, plus OpenAI, Anthropic
and Ollama. They include adjacent integers above 2^53 and rounded doubles.
Native guards now use exact JSON equality; protocol hashing keeps its deliberate
JavaScript numeric semantics. The selected hosted declaration check matches the
pinned official Node source and current upstream projection at review time.

The related `openai_dart` image-option correction is submitted as
[upstream PR #436](https://github.com/davidmigloz/ai_clients_dart/pull/436).
Its isolated Dart 3.13.3 unit suite passed 25,239 tests with 3 environment skips;
strict library/new-test analysis passed. It used an explicitly remapped existing
workspace dependency configuration, not a fresh full-monorepo bootstrap. The
AgentWeave SDK pin remains 11.0.1; native JSON avoids the incorrect image types.

No paid calls were made for this increment. Live hosted tools, search quality,
containers, complete native provider semantics and device image rendering remain
unverified. Public citations, hosted progress and partial images are not
normalized. Packages remain unpublished.
