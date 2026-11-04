# AgentWeave acceptance roadmap

The target is a Dart-first AI SDK for Serverpod developers, with useful APIs for
other Dart backends and Flutter with hosted or local models. TanStack client
interoperability must remain available; it must not dictate the native Dart API.
A passing fixture suite is not evidence of production maturity or a 10/10 SDK.

## Current milestone: base framework

Scope changed by the user on 2026-11-04: prioritize the base framework with
OpenAI and Anthropic. Completing the other providers and every provider endpoint
is deferred. Existing integrations remain available with their stated limits.

Acceptance for this milestone:

- Idiomatic native Dart generation, typed streaming and results, structured
  output, tools, approvals, cancellation and safe errors. Preserve existing
  TanStack client compatibility without requiring native callers to parse wire
  event maps.
- OpenAI and Anthropic support for the main application workflows: streamed
  conversations, tool continuation, typed output, private replay, usage and
  request cancellation. Validate supported options against pinned contracts and
  fail explicitly for unsupported modes. Exhaustive API and specialized hosted
  tool coverage are later work.
- Serverpod authentication, owner isolation, PostgreSQL persistence, restored
  approvals, reconnect and restart recipes with actual integration evidence.
  Keep plain Dart and custom-provider extension contracts usable.
- Independent developer consumers must run realistic scenarios, expose setup
  and debugging friction, and verify fixes. Scores are evidence of the tested
  journeys, not a substitute for resolving concrete findings.
- Searchable GitHub Pages guides, runnable examples, coding-agent references,
  migration instructions and honest capability limits. Verify published docs
  against source and run checks on minimum and stable Dart SDKs.
- Check release readiness separately from publication. No publication is implied
  by completing implementation or passing CI.

## Coverage inventory and later work

The following inventory retains earlier requirements and known gaps. Provider
breadth, specialized computer/hosted/MCP workflows, exhaustive field coverage and
Flutter/local-model device certification do not block this base-framework
milestone. Reliability of the workflows claimed by the base still does.


- Independent developer agents must write and run consumer applications across
  multiple scenarios and score discoverability, clarity, type safety, debugging,
  and testing. Record failures and rerun after fixes. Use GPT-6.1 Terra with low
  or medium reasoning. The latest general offline review is 8.5/10. The native Anthropic transport path scored
  8.4/10 and its computer-tool path scored 7.8/10. The targeted Dart Frog and Ollama
  paths scored 8.0/10 and 7.8/10. Neither is an acceptance pass.
- Later: complete native provider coverage for OpenAI, Anthropic, OpenRouter, Together,
  Vercel AI Gateway, and Cloudflare, with a documented custom-provider contract.
  Track each endpoint, nested parameter, tool/event union, query, header, cache
  option, and continuation behavior against a dated authoritative specification.
  An OpenAI-compatible URL or SDK export does not establish native parity.
- Selected OpenAI Responses computer calls now have explicit native events,
  application-controlled execution, approval/safety handling, private replay,
  PostgreSQL and client fixtures. Anthropic computer toolset actions now have
  equivalent native approval, persistence and batch-failure contracts. Real
  driver/model behavior and other native
  tool continuations remain open; this is not complete computer-use parity.
- Selected OpenAI hosted Responses tools now have lossless native options,
  terminal validation, private replay and ordered completed image parts. Hosted
  progress, precise native-coordinate citation highlights, partial images,
  shell/patch and live provider
  behavior remain open. Direct OpenAI custom text tools now have typed execution,
  namespaces, approvals/denial, private replay and durable fixtures. Programmatic
  and asynchronous custom execution remain open. Compatible endpoints do not inherit these claims.
- Anthropic hosted blocks, container replay and counted paused turns now have
  local fixture and consumer coverage. Live search/code/container behavior,
  browser tools, live MCP/citation behavior and full nested semantics remain
  open. Constructor coverage is not workflow certification.
- OpenRouter Chat now handles selected completed text/image output, with private
  replay across approvals. Its dedicated Image API now has typed discovery, native
  SSE, same-request JSON fallback and durable Serverpod generation fixtures.
  Live provider behavior, streamed Chat image extensions and audio remain open.
  Native Cloudflare text now streams documented response
  chunks; schema and traditional tools stay buffered. Model support and live
  behavior remain unverified.
- Anthropic now normalizes all five pinned citation variants into typed text
  annotations, client metadata and private replay across approvals. Other provider
  citations, custom-content document inputs, live quality and device rendering
  remain open.
- Native OpenAI output references now preserve all four Responses annotation
  forms and completed Chat URL references, including empty segments and opaque
  native positions. Other provider references, live indexing conventions,
  authorized download recipes and device rendering remain open.
- Native Anthropic Messages MCP now supports explicit legacy/2025/2026 modes,
  private use/result/listing replay, owner-bound credentials, mixed local
  approvals, immutable provider profiles and uncertain-send protection. Live
  remote execution, OAuth providers, inline tool changes and platform acceptance
  remain open; offline tests are not a complete native API certification.
- Native OpenAI Responses MCP now supports private discovery/call replay, multiple
  server configurations, credential resolution and approval/denial decisions.
  Generic client, loopback and durable fixtures do not establish live remote
  execution, identity-provider integration, tunnel/connector availability or
  exactly-once effects. These remain open.
- Preserve provider options and metadata without letting configuration silently
  replace server-owned history, schemas, tools, or execution bounds. Unsupported
  response modes must fail explicitly or use a clearly separate native API.
- Provide runnable Serverpod examples for streamed chat, persisted approvals,
  typed output, tools, cancellation/reconnect, media and authentication. Verify
  recreation/restart behavior and failure recovery with PostgreSQL.
- Provide equivalent framework-independent recipes and adapters for Dart Frog
  and other HTTP servers; verify Flutter device/local-provider behavior.
  Dart Frog now has local HTTP and official JavaScript client fixtures. Ollama
  has native NDJSON fixtures and a consumer example; neither establishes live
  model, device, proxy or production deployment behavior.
- Evaluate whether protocol events should move into an optional TanStack adapter
  package. Keep existing client compatibility tests throughout any migration.
- Publish searchable, accessible GitHub Pages documentation with executable
  recipes, precise capability tables, API references, migration/update guides,
  and coding-agent instructions. Validate the deployed website separately.
- Establish provider contract suites, schema/parameter inventories and upstream
  update checks. Contribute reproducible missing SDK fields and union cases
  upstream where that is the correct fix; keep PRs narrowly scoped and tested.
- Verify package publication, compatibility across supported Dart SDKs, security,
  performance/backpressure, and operational failure cases before a stable claim.

## Native Dart streaming

`AiAgent.stream` and `streamText` now emit sealed Dart updates with the typed
result from the same execution. Native callers no longer parse TanStack maps or
run the model twice to obtain a result. Existing clients keep `AiAgent.run`.
Cancellation, backpressure, errors, approvals and PostgreSQL recreation have
local checks. Independent native streaming review improved from 4/10 to 8.5/10;
this is a scoped score, not overall acceptance. Protocol journals still live in
core, so optional package extraction and broader operational validation remain
open.

## Current reliability/DX increment

Implemented: typed `generateText`, `generateObject`, and `AiAgent.generate`;
immutable run results and usage; typed approval resolutions; backend-only field-level schema diagnostics; scripted test
providers; atomic final event/checkpoint/release; safer observer handling;
separate caller/model/output/tool/step-limit errors with safe Future messages;
exact versioned pending tool contracts independent of client schema hashes; guarded provider request
configuration; canonical reasoning replay includes; actual provider model usage.

Tests now exercise the same storage contract against memory and PostgreSQL,
recreated PostgreSQL approval flows, local loopback HTTP, both existing clients,
and the new native Dart API. Consult validation results for the exact checks.
These improvements do not complete the requirements above.
