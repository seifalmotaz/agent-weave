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

The latest local verification used Dart 3.12.2. GitHub CI checks both the minimum
SDK and the stable channel; inspect the run for the commit you use.

- 694 Dart unit and regression tests: tool validation, approvals, client tools,
  lineage, cancellation, partial-response retention, safe failure history,
  generation, storage, protocol parsing, and provider fixtures.
- 38 Serverpod integration tests with a real isolated PostgreSQL database:
  authenticated endpoints, a generated-client WebSocket, HTTP/SSE, history,
  replay, owner isolation, event persistence, and reservation contention.
  The HTTP test also runs the official JavaScript client against real Serverpod
  chat and generation routes, including a second turn and persisted history.
- 28 standalone official JavaScript client scenarios against a Dart HTTP server:
  text, server tools, approvals, client tools, reasoning, structured output,
  generation, provider-owned MCP approval/denial, two local-reference edited-approval cases, two provider-continuation cases, typed citations with stored-event
  replay, and eight media/history cases, including ordered output images. The media cases include document
  URL, inline bytes, scoped and unscoped file handles, image/video URLs, and
  inline audio; returned parts pass the official AG-UI schemas.
- 4 additional official JavaScript scenarios use actual Dart Frog handlers and a
  local fake Ollama NDJSON service: text, schema, approval/resume and authenticated
  typed generation, including owner isolation, privacy and safe errors.
- 2 offline checks for the upstream operation-index parser.
- The offline chat, support approval, in-flight cancellation, and schema-diagnostic examples execute successfully. Independent support and diagnostic consumer applications also pass.

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

A final byte-level check caught and replaced the original corrupt 1x1 PNG
fixture. The new offline check verifies complete PNG chunks, CRCs, dimensions
and decompressed pixel data across the provider, client and storage fixtures.
This verifies the fixture bytes, not device rendering.

No paid calls were made for this increment. Live hosted tools, search quality,
containers, complete native provider semantics and device image rendering remain
unverified. Public citations, hosted progress and partial images are not
normalized. Packages remain unpublished.

## OpenRouter images and Cloudflare streaming increment

With Dart 3.12.2, the full local check passes 437 unit/regression tests, 18 real
PostgreSQL/Serverpod tests, the official JavaScript client scenarios, all native
Dart consumers and provider contract checks. Three documentation checks and a
strict site build pass. Image fixture integrity checks now include the new
OpenRouter consumer and PostgreSQL fixture.

OpenRouter Chat image output uses its pinned completed assistant-message schema,
with a buffered request. Tests cover remote/data URLs, ordered content arrays,
multiple images, opaque replay, supplied-schema/tool guards, filtered/error
finishes, invalid output, redacted JSON error envelopes with request IDs and
cancellation while waiting for headers. A real PostgreSQL test recreates the
agent at approval, verifies no early tool effect, and replays the original image
array alongside the selected function call/result. Public history omits private
signatures. Streamed Chat image deltas are rejected; the separate Image API is
not implemented by this adapter.

Cloudflare native text tests verify incremental response chunks before upstream
completion, `[DONE]`, cancellation and a surviving sibling, Gateway headers,
option snapshots, schema/tool buffered fallback, explicit opt-out, malformed
streams and premature EOF. Repeated complete usage frames are treated as
cumulative snapshots and emitted once at completion; this behavior is bounded
and has not been live-verified across model variants.

An independent developer wrote and ran both loopback programs and scores each
selected path 8/10. The OpenRouter guide byte-matches its example, which analyzes
and compiles without execution. `result.images` includes images produced during
current-run tool steps and excludes prior runs. No paid calls were made; live
provider/model acceptance, billing and device rendering remain unverified.

## Exact approval contracts and checkpoint recovery

With Dart 3.12.2, the full local check passes 445 unit/regression tests and 20
real PostgreSQL/Serverpod tests, plus the official JavaScript client scenarios,
provider contract checks and native Dart consumers.

Private pending approvals now bind exact versioned snapshots of the declared
tool configuration. Regressions cover adjacent large-integer input/output
schemas and native definitions, execution-kind and policy changes, equivalent
numeric values and key ordering, all-before-effects batch validation, owner
isolation, public-state privacy and original-contract retry. Real PostgreSQL
checks preserve the exact integers through agent recreation and reject changed
input/output schemas before model or executor invocation. The initial database
test expected a raw exception; correcting it to the public `AgentRunException`
contract made the intended assertions pass.

Legacy, malformed and unsupported pending contracts fail closed while retaining
the original history. Older pending approvals require a new conversation; they
are not reconstructed from current tools or lossy client hashes. Public protocol
hashes retain JavaScript number semantics. This does not remove JavaScript's
numeric limits or bind application closures and live permissions.

A separately reproduced malformed native-continuation checkpoint previously
stranded the thread reservation. The regression now verifies sanitized decode
failure, unchanged stored state, an unused model and a successfully reacquired
reservation. Future-based run errors expose the same safe recovery message as
streamed errors while retaining private diagnostic causes.

The independent developer reran the approval consumer and checkpoint regression
and scores this scoped path 9/10. No paid calls were made. This is not evidence
of complete native provider coverage or arbitrary-crash recovery.

## Typed Anthropic citations increment

The complete Dart 3.12.2 check passes 460 unit/regression tests and 21 real
PostgreSQL/Serverpod tests, all consumers, provider contracts and both client
suites. Three documentation tests and the strict site build also pass.

Core fixtures validate typed source references, JSON round trips, immutable
message annotations, UTF-16 ranges, malformed input, continuation, memory
approval recreation, retained partial text and cancellation. A split-surrogate
regression rejects an unstable citation boundary before its public event.
Provider fixtures cover all five pinned citation types, initial and streamed
citation lists, complete-block answer spans, source coordinates, guarded document
configuration, SDK streaming, structured-output incompatibility and malformed or
unfinished responses before tool execution.

A real PostgreSQL test recreates an approved-tool agent, verifies saved citations
and event logs, isolates owners and restores native replay. Raw response
citations retain private fields; continuation inputs omit response-only file IDs.
The official JavaScript client and the Dart client preserve citation metadata in
live snapshots and restored history. The first emoji transport fixture used
Latin-1 output; setting its explicit UTF-8 charset corrected the fixture.
Serverpod already encodes its event bytes as UTF-8.

The independent developer consumer runs all five source kinds through loopback
HTTP, then recreates an approval and checks native replay and privacy. Its scoped
score is 8/10. The guide sample byte-matches the runnable example, analyzes and
compiles without execution. No live provider or paid calls were made. Citation
quality, custom-content document inputs, other providers' citation adapters and
Flutter rendering remain open. URL validation does not establish a general
public-data policy.


The first full citation check rejected an older native consumer's incomplete
citation fixture. It omitted required source fields and treated a document title
as private metadata. The corrected fixture supplies a citable document and all
required fields, and uses an unknown native field for its private-marker check.
Public titles remain public, while unknown fields remain private.

Citation events include a stable per-message `citationIndex`. The official
JavaScript fixture reads the actual stored log through the adapter's GET
`joinRun` path and feeds it through the official client processor. Upserting by
message and index retains two identical citations after replay without creating
four. This is completed-log replay evidence, not automatic reconnection during
a live provider call.

## Upstream SDK citation file IDs

The isolated upstream correction in
[PR #441](https://github.com/davidmigloz/ai_clients_dart/pull/441) retains nullable
file IDs in the three document citation response DTOs and leaves request types
unchanged. Dart 3.13.3 checks passed 1,851 package unit tests with three
environment-key skips and strict analysis. An independent actual SDK loopback
consumer covers stored-message reload, cache equality, clear/copy, streaming and
`toInputMessage()` request projection; its scoped score is 9/10.
The sparse checkout used a cached remapped package configuration, not a fresh
monorepo bootstrap. This contribution does not update AgentWeave's SDK pin or
publish a package.

## Native OpenAI output references

The full Dart 3.12.2 check passes 484 unit/regression tests and 22 real
PostgreSQL/Serverpod tests, both clients, all consumers and contract checks. Three
documentation tests and a strict site build pass.

Core fixtures exercise native range, insertion and file-list position types,
empty enclosing parts, JSON snapshots, immutable collections, invalid spans,
provider mismatches, partial failure and cancellation. The existing citation
suite continues to pass. OpenAI fixtures cover all four Responses annotations,
initial and streamed echoes, null placeholders, exact text reconciliation,
unknown/conflicting data, EOF and cancellation before tool effects. Buffered
Chat fixtures cover native nested URL annotations, typed options/schema guards,
private audit data, cancellation isolation and malformed output. Native Chat
streaming rejects unknown/inconsistent finishes and late choices before tools.

Independent native SDK loopback consumers score the selected Responses and
buffered Chat flows 8/10 each. A PostgreSQL test recreates an approval and verifies
all four typed reference forms, event order, private replay, owner isolation and
intentional public scoped file IDs. Its initial assertion incorrectly expected
only an assistant in `responseMessages`; filtering out the tool result corrected
that fixture. Both clients retain references alongside citations through snapshots,
history restoration and completed-log replay; replay upserts retain legitimate
duplicates. Guide examples byte-match their runnable sources and compile without
running the billable demos.

No paid calls were made. Native Unicode offset interpretation, live model
acceptance, actual authenticated file download, production rendering and other
providers' reference normalization remain unverified. These checks preserve
reported positions; they do not establish precise inline highlighting.

## Schema diagnostics and offline onboarding

Dart 3.12.2 passes 491 unit/regression tests and 22 real PostgreSQL/Serverpod
integration tests through `tool/check.dart`, including both client suites and
all pre-existing provider inventories and consumers. The two newly tracked
independent consumer applications also execute and pass fatal-infos analysis.
The check now includes those consumers and four offline sample invocations.
Three documentation tests and a strict site build pass. Core Dartdoc reports
zero warnings and errors.

New regressions cover validator instance/schema paths and immutable issue
snapshots; structured output, tool input and tool output errors; sanitized
Future/stream errors and hydration; nested edited-approval diagnostics, batch
validation before effects and retry; and directly validated local references.
The public approval schema and hashes are unchanged. The pinned validator's
embedded local-reference limitation is not a verified defect in either client.

An independent developer reran support chat, usage, typed escalation, recreated
in-memory approval, structured output, schema failures, cancellation and a
synthetic reference. The scoped offline score improved from 8/10 to 8.5/10.
The complete support guide byte-matches the executable source and is present
in the rendered site and search index. These samples use shared memory within
one process; existing PostgreSQL tests separately cover durable behavior.

No paid calls were made. Live provider acceptance, Flutter rendering, actual
file retrieval and client-side local-reference approvals were not newly tested.
Issue details may contain private schema/input data; original conversation
content is intentionally retained rather than redacted.

## Local-reference edited approvals through real clients

The Dart client suite passes six tests, including two new local `$defs`/`$ref`
scenarios. The standalone official JavaScript suite passes 23 reported scenarios,
including the corresponding valid and invalid edits. Both clients bind typed
approvals and cause no effect before approval; valid edited arguments complete
with one effect, while invalid edits return sanitized `INVALID_INPUT` before
execution. Dart also verifies matching schema and approval hashes.

The independent initial loopback probes additionally check model step consumption
and the invalid Dart edit's second HTTP request. They do not prove client-side
raw-schema validation. The narrower pinned-validator failure when directly
validating an embedded approval union does not reproduce as an actual application
failure for these tested schemas. The initial JS error was a probe API mistake,
corrected from a Dart-shaped payload to `resolveInterrupt(true, {editedArgs: ...})`.
The independent scoped score remains 8.5/10.

The new cases reuse existing fixture harnesses and add no runtime API changes.
They do not cover other reference shapes, retry after an invalid submission,
new durable scenarios, live providers or rendering. No paid calls were made.

## Native OpenAI Responses MCP approvals

The MCP increment adds provider-owned approval events and decision history,
multiple configured servers, native discovery/call/approval/echo normalization,
per-request credentials, exact configuration guards and indeterminate-execution
checkpoints. It does not run a local executor for a remote MCP decision.

The initial full offline check passed 532 unit tests and 25 real
PostgreSQL/Serverpod tests. Subsequent review added third-turn echo deduplication,
whole-configuration binding and cross-provider rejection regressions. The final
unit total is 536, including cancellation at the pre-dispatch checkpoint. Client tests cover generic approval and denial in both pinned
clients; the standalone official JavaScript suite now reports 25 scenarios.

Durable MCP tests recreate agents against PostgreSQL, verify approval and denial,
owner isolation, changed-configuration rejection and private journal/hydration
boundaries, and preserve an indeterminate initial execution across recreation.
The first fixture failed because its changed-configuration request omitted the
required parent run ID; supplying the parent corrected the fixture. This is
agent recreation against a durable store, not a new OS process-restart test.

Core and adapter regressions cover mixed batches before effects, reasons,
invalid answers and retry, cancellation, initial effects without prior approvals,
orphan/duplicate/private IDs, exact terminal reconciliation and credential
projection. A default-config SDK 503 fixture confirms one streaming HTTP attempt
and no automatic resend on a recreated thread. Approval echoes are correlated
with saved decisions and removed from subsequent input duplication while
retained in private audit. Chat/Anthropic reject foreign approval state before
transport. The expanded inventory reviews selected pinned MCP declarations and
executable nonsecret request fields; it does not establish all nested semantics.

The independent MCP score improved from 2/10 unsupported to 7.5/10 for the
executed offline journeys. No paid call, OAuth flow, live MCP server, actual
remote effect, tunnel/connector availability or mobile rendering was tested.
Indeterminate threads require external reconciliation and a new conversation;
no exactly-once remote execution claim is made.

## Upstream merge status checked on 2026-11-04

The citation file-ID fix in [PR #441](https://github.com/davidmigloz/ai_clients_dart/pull/441)
and stalled-stream cancellation fix in [PR #432](https://github.com/davidmigloz/ai_clients_dart/pull/432)
are approved and merged upstream. The live pub.dev API still reported
`anthropic_sdk_dart 9.0.1`, published before these fixes, at this check.
AgentWeave keeps that published dependency pin; a merged PR does not establish
a published SDK release or an upgraded consumer dependency.

## Typed provider approvals and client restoration

The full Dart 3.12.2 check passes 543 unit/regression tests, 25 real
PostgreSQL/Serverpod integration tests, both existing client suites and all
contract inventories. The client package contributes six typed-helper tests
and a reconnect/multiple-round test. Its focused suite passes 34 tests, including
nine client interop tests. The official standalone JavaScript suite reports 26
scenarios, including restored MCP approvals and two human decision rounds.

Helper tests verify nested argument snapshots, nonprovider interrupts, malformed
metadata without payload echo, generic approve/reject reasons, unresolvable
snapshots and callback failure propagation. The real client tests recreate and
attach the client before resolving approvals, preserve display metadata, submit
the native decisions with reasons and assert the completed answer. The helper
Future stages a resolution; it does not represent completion of the provider run.

Independent review scores this offline path 8.5/10, improved from 8/10 before
typed access. That reviewer did not run PostgreSQL, live MCP, backend process
restart or mobile UI. The named fixture's request count does not prove that a
live remote effect executes exactly once.

## Upstream MCP output contribution

[PR #443](https://github.com/davidmigloz/ai_clients_dart/pull/443), merged upstream on
2026-11-04, fixes native MCP
output decoding in `openai_dart`. The installed 11.0.1 and freshly checked
upstream base `35e2d435` failed four native output examples through both public
parsers; calls required an undocumented `call_id`, and discovery/approval items
were unrecognized. The submitted patch adds typed output variants, native error
and status unions, immutable parsed snapshots and resource-level HTTP tests.
Its API changes are explicitly marked breaking.

Dart 3.12.2 package analysis and 25,313 offline SDK unit tests pass, with three
environment-key skips. Nine focused tests include serde, optional clearing,
equality/hash, mutation, subtype equality and a mocked approval continuation.
The independent public-client loopback consumer also sends the actual approval
response using the existing `ResponseInput.fromOutputItems` factory. Generic
`CreateResponseRequest.fromJson` still rejects that MCP input; typed input and
conversation-resource models are separate known gaps, not covered by this output
fix. AgentWeave's SDK dependency remains pinned to published 11.0.1. The recorded
SDK validation describes the submitted patch; the upstream merge is separate
from adopting or publishing an SDK release. No live or paid call was made.

## Anthropic MCP execution guard

Historical round-25 boundary. The native MCP section below describes its replacement with owned configuration and replay.

A separate consumer review found that native `configure` could send legacy
`mcp_servers` despite unsupported MCP output normalization. Its local synthetic
provider recorded two simulated effects across two explicitly initiated runs;
this did not establish live legacy beta acceptance or real remote execution.
The implemented interim guard now rejects nonempty or malformed MCP server
configuration before transport. Modern unsupported toolsets remain blocked.

Five new tests verify repeated attempts with zero transport invocations,
null/empty lists, unrelated options, modern toolset rejection, typed SDK field
loss and preserved explicit raw-native API access. The full Anthropic package
suite passes 70 tests with Dart 3.12.2. This does not implement the native MCP
connector lifecycle or claim higher functional coverage for that provider.
The broader goal still includes owned configuration, beta/credential handling,
private MCP replay and model contracts checked before resumed local effects.

## Provider profiles across unfinished turns

The runtime persists an adapter's versioned private model continuation profile
and validates it before resumed local effects, staged calls and subsequent
provider invocations. Native OpenAI Responses binds immutable options, tool
choice, the full ordered managed-tool set and a stable application-owned
provider/account authority. Both its typed and native wrappers copy inputs;
managed tools reject dynamic configuration callbacks at construction.

Core fixtures cover changed profiles, unbound-to-bound replacement, legacy and
malformed snapshots, an orphan call checkpoint, provider pause at the step
limit, original-profile recovery and terminal clearing. Missing-profile legacy
unfinished statuses fail closed; completed legacy history permits a new turn. OpenAI fixtures check
nested snapshot ownership, native request and function-option preservation, runtime-owned field
rejection, typed transport field-loss detection and authority drift before
local execution. PostgreSQL recreation checks changes to server, allowlist,
MCP credential binding, model, hosted tools, provider authority, options and
tool choice before any local effect or resumed dispatch. Original configuration
with a refreshed token completes; rejected attempts preserve the saved state.

The independent consumer separately exercised the public SDK with `MockClient`
and a protocol transport fixture, scoring the tested path 8/10. Its scripted
provider pause is not a native OpenAI pause. These checks do not establish live
remote execution, automatic authority discovery, identity-provider behavior or
exactly-once external effects. Undeclared custom adapters do not receive an
identity guarantee; other built-in providers need their own profile support.
No paid provider call was made for this increment.

## Native Anthropic MCP and credential cancellation

Owned Messages MCP configuration supports explicit legacy, 2025 and 2026 beta
modes. Configuration fixtures and the selected official beta declaration
inventory cover server options, credentials, defaults/per-tool filters, cache
control and pinned tool descriptors. The normalizer privately retains native
use/result/listing blocks and unknown fields. Tests cover duplicate/orphan IDs,
non-object JSON input, truncated/refused pending calls, explicit and recorded
listing integrity, current-call allow/deny policy, mixed local approval and counted paused turns.

Five new PostgreSQL tests use an actual loopback HTTP provider fixture. Each
beta mode recreates a mixed local/MCP turn, rejects changed server, remote
credential binding, provider authority, options, model and beta before any
local effect or resumed request, and completes with refreshed credentials under
the original binding. Other cases reload a 2026 provider-only pause at the step
limit and verify that an uncertain 503 send blocks a later recreated request.
Native blocks stay private in hydration/journals and credentials stay outside
saved configuration. The provider fixture does not perform remote MCP effects.

Independent public-API consumers exercise multiple servers/toolsets, deferred
results, native and SDK-backed clients, all three beta modes, metadata echo
sanitization, one-send 503 behavior and cancellation boundaries. The tracked
recipe is `examples/review_cases/anthropic_mcp.dart`. The scoped score is 8/10
with the new guide, not overall SDK acceptance.

A separate stalled-OAuth probe reproduced and then verified the fix in both
Anthropic and OpenAI MCP. Cancellation now releases the in-memory reservation
before the resolver returns, without sending or setting an indeterminate
marker; late failures are consumed. Core tests also cover pre-cancellation,
success/failure propagation and listener isolation. The underlying application
Future is not cancelled. SDK 9.0.1's pending-response-header abort limitation
still applies after dispatch; native transport remains the recommended path.

No paid provider call, actual OAuth server, external MCP effect, cloud-platform
acceptance or mobile UI was tested. Private provider-generated content can
contain sensitive data; preserving opaque replay is distinct from sanitizing
owned credentials in configuration, metadata and errors. This is not complete
Anthropic API, inline tool-change or Managed Agents coverage.

MCP transport diagnostics retain HTTP status and a redacted native request ID,
without provider body/headers. The pinned SDK's streaming path loses the server
request ID; a public MockClient reproduction confirms this on published 9.0.1
and freshly fetched upstream main `eed64e89576f9d977fb0cf7728d766cf898f079a`,
including the merged cancellation fix. This is an upstream metadata gap, not a
claim about actual remote effects. Local correlation IDs are not substituted.

The streaming-error correction was approved and merged on 2026-11-04 as
[upstream PR #445](https://github.com/davidmigloz/ai_clients_dart/pull/445),
commit `1396797bbd70ddfd0b40c975e9929128c279144e`.
The additive `ApiException.requestId` reads server response metadata for typed
Messages, raw POST/GET and default JSONL errors; it never substitutes a local
correlation ID. Streaming metadata excludes body excerpts and unrelated headers,
while existing exception messages/details can still contain provider content.
Invalid or oversized numeric retry headers return an ordinary rate-limit
exception. RFC 1123 date parsing and custom JSONL error factories are outside
this fix. With credentials unset, 1,872 SDK unit tests pass with three skipped,
and package analysis is clean. Independent public-client and adversarial
retry-header probes pass. This PR is not a published dependency update.

## Dedicated OpenRouter Image API

The typed native capability covers all 17 pinned request fields, provider
preferences, generated bytes, nullable MIME, reported usage/cost, model discovery,
endpoint pricing and enum/range/boolean capabilities. Unknown capability variants
and fields retain native JSON. The inventory classifies raw usage details
separately from typed projections. The executable
`tool/openrouter_image_contract.dart` asserts actual requests and both direct
and wrapped event envelopes; constructor coverage alone is not certification.

Transport fixtures check Content-Type negotiation from one POST, JSON fallback,
fragmented UTF-8 SSE, completion sentinels, malformed responses, no resend after
503 and cancellation before/after dispatch. A late-header response-body leak was
reproduced before the shared transport fix. Buffered format errors now preserve
HTTP status and request IDs without copying response bodies into messages.
Provider adapters still own credential redaction and native completion policy.
Native SSE errors are typed events; application tasks must turn them into failure.

The Serverpod integration uses actual PostgreSQL and loopback provider/backend
HTTP. It persists exact buffered JSON, both native completed events in order,
failed generation and one-request fallback. The official JavaScript generic
`GenerationClient` receives the native fallback result. The documented route
factory uses real authentication, server-owned model/count policy and an
owner-scoped durable result. Unauthenticated calls send no provider request;
client-supplied model, count, routing and owner do not replace server policy.

The upstream-review workflow detected a changed official source. After reviewing
the transitive selected schemas and operation differences, the source pin now
accounts for 144 operations across 106 paths. Two removed private-endpoint PUT
operations were never integrated. New regressions verify Parallel options on the
actual request wire, all nine newly nullable Responses result fields through the
public text API and fractional image capability ranges. This updates the prior
146-operation snapshot; it does not claim full OpenRouter API coverage.

The independent consumer scored the selected offline journeys 8/10. The live
example and documented Serverpod factory are source-matched in documentation
checks. No paid provider call, actual reference download, image rendering,
provider cancellation/billing, model option acceptance or device UI was tested.
Applications still own quotas, source authorization, SVG handling, storage and
retention; the adapter does not cap image response size or infer missing MIME.

Verification for this increment: `dart run tool/check.dart` passed with 636 unit
and regression tests, 32 PostgreSQL/network cases, the standalone official
JavaScript client and Dart Frog suites, executable contracts and offline
consumers. After the final decoder fix, all 636 unit/regression tests were run
again and passed. A malformed SSE UTF-8 probe had exposed decoder source bytes;
the shared transport now returns safe HTTP metadata, and an independent public
image-stream probe verifies redaction. Package analysis is clean, all three docs
checks pass, strict MkDocs build succeeds, and OpenRouter Dartdoc reports zero
warnings/errors. The current upstream hash check passes after the reviewed pin
update. No paid call was added to the cumulative testing ledger.

Upstream image-option PR #436 was also verified merged on 2026-11-04.
The pub.dev API still reports `openai_dart 11.0.1` and
`anthropic_sdk_dart 9.0.1`; no dependency upgrade is implied by these merges.

## Typed native streaming

`AiAgent.stream` and `streamText` expose sealed native updates and a typed final
result from the same execution. Tests exercise text/reasoning, media, typed
citations/references, usage, private replay retention, tool proposals/results,
approval/resume, structured success/failure and committed final results. Existing
wire clients continue using `AiAgent.run`; native values come from runtime types,
not a parse of wire JSON. The runtime still stores its existing wire journal.

A subscription-cancellation test initially timed out because an async-generator
projection waited for the provider before forwarding cancellation. Standard Dart
stream transforms now forward cancellation/pause to the existing scoped stream.
Tests cover early `.first`, shared-parent sibling isolation, caller cancellation,
pre-cancellation, pause/resume, reservation release and failed terminal checkpoints
without a successful final update. Storage/setup exceptions retain their original
semantics; classified run failures carry a typed partial backend snapshot.

The actual PostgreSQL test recreates the agent and store across a typed approval,
executes one effect, checks two model invocations and retains owner isolation.
Its provider is a deterministic fixture. The independent developer's scoped score
rose from 4/10 to 8.5/10 after writing and running native consumers; these results
are not production or package-wide acceptance.

A further public tool probe reproduced mutable nested generic Dart maps in a
snapshot. The shared JSON freezer now copies maps with string keys regardless of
their generic declaration. Direct/runtime regression tests verify nested ownership,
large Dart integers and invalid key rejection. The original independent probe
passes after the fix. The guide's code block is checked against its runnable
source. No paid model call, external tool effect or Flutter device was tested.

A storage-time ownership probe also mutated a tool's source map during journal
append. The stored tool message and wire event retained the original value,
but the new native event initially copied the later mutation. The runtime now
snapshots the outcome before the first storage await and reuses that value for
history, the journal and the native update. The original regression passes.

OpenRouter adapter fixtures additionally run the native stream through actual
HTTP request serialization and SSE normalization. They verify reported usage,
private cost/provider/reasoning metadata and a typed approval with two requests,
one effect and exact assistant/tool replay. These are mocked HTTP responses,
not live OpenRouter execution or billing evidence.

Final increment verification: `dart run tool/check.dart` passes 653 unit/regression
tests, 33 actual PostgreSQL/Serverpod integration tests, both existing client
interop suites, all contract checks and offline recipes. All three documentation
checks and strict MkDocs build pass. Core Dartdoc reports zero warnings/errors.
The earlier OpenRouter increment's GitHub minimum/stable CI and Pages deployment
also finished successfully. No paid test was added for native streaming.

## OpenAI custom text tools

The selected direct custom-tool integration has offline fixtures for text and
regex/Lark declarations, raw input, native output content and cache fields,
namespace dispatch, strict stream correlation, exact private replay, selector
validation and completed-history registration changes. DTO tests reject
asynchronous and programmatic modes. Native fallbacks have tests for approval
denial/cancellation, schema validation, mixed computer batches, unexpected errors
and complete registry changes before any resumed effect. Legacy unfinished
model-only profiles fail closed while retaining their original snapshots.

Five new actual PostgreSQL integration cases use recreated agents and SDK
loopback HTTP. They cover approved text/content results, denial, approval
cancellation, and changed unrelated custom grammar/binding before an approved
ordinary function. Three Dart-client restoration cases use a synthetic transport.
Two official JavaScript-client cases use SDK loopback HTTP and verify native
approval/denial, exact provider output, history privacy and effect counts.

The custom contract projection records 21 roots and 31 declarations, with explicit
unsupported or inventory-only dispositions. The 15 parser tests, frozen source
check, executable Dart fixture and selected upstream projection check pass. These
counts do not establish complete Responses support. The independent consumer
scored the tested offline workflow 8/10. No paid call or real external effect was
made, and the live CLI example was compiled only.

The missing SDK custom-tool selector was reproduced on published 11.0.1 and
upstream main `6e1e5313ae5bb24b5f61443acc8f69ce19f051e7`. The narrow correction
is [upstream PR #451](https://github.com/davidmigloz/ai_clients_dart/pull/451).
Independent review found no blocking issue. The patched SDK's full offline unit
suite passes 25,898 tests with three skipped, with provider credentials unset.
Tests used an isolated sparse checkout and a previously resolved package
configuration; normal-workspace CI remains a separate check. Adding a sealed
choice variant requires downstream exhaustive switches to handle it. AgentWeave
still uses the published SDK and rejects this selector in typed mode with a
message recommending its native transport.

Final round 30 coordinating verification: `dart run tool/check.dart` passes all
694 unit/regression tests, 38 PostgreSQL/Serverpod tests, 28 standalone official
JavaScript-client scenarios, four Dart Frog scenarios, all contract checks and
offline recipes. The live CLI examples compile without execution. The three
documentation checks and strict MkDocs build pass; core and OpenAI Dartdoc dry
runs report zero warnings/errors. Compile checks reuse one temporary output and
clean it in `finally`; this run used an external-volume `TMPDIR` after the main
disk ran out of space. No new paid provider request was made. Upstream PR #451's
GitHub run currently requires maintainer action and has no executed jobs; the
local SDK tests are separate evidence.
