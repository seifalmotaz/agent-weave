# AgentWeave acceptance roadmap

The target is a Dart-first AI SDK for Serverpod developers, with useful APIs for
other Dart backends and Flutter with hosted or local models. TanStack client
interoperability must remain available; it must not dictate the native Dart API.
A passing fixture suite is not evidence of production maturity or a 10/10 SDK.

## Acceptance requirements still open

- Independent developer agents must write and run consumer applications across
  multiple scenarios and score discoverability, clarity, type safety, debugging,
  and testing. Record failures and rerun after fixes. Use GPT-6.1 Terra with low
  or medium reasoning. The latest general offline review is 8.5/10. The native Anthropic transport path scored
  8.4/10 and its computer-tool path scored 7.8/10. The targeted Dart Frog and Ollama
  paths scored 8.0/10 and 7.8/10. Neither is an acceptance pass.
- Complete native provider coverage for OpenAI, Anthropic, OpenRouter, Together,
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
  shell/custom/patch and live provider
  behavior remain open. Compatible endpoints do not inherit these claims.
- Anthropic hosted blocks, container replay and counted paused turns now have
  local fixture and consumer coverage. Live search/code/container behavior,
  browser/MCP tools, live citation quality and full nested semantics remain
  open. Constructor coverage is not workflow certification.
- OpenRouter Chat now handles selected completed text/image output, with private
  replay across approvals; its dedicated Image API, streamed Chat image extensions
  and audio remain open. Native Cloudflare text now streams documented response
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
