# AgentWeave acceptance roadmap

The target is a Dart-first AI SDK for Serverpod developers, with useful APIs for
other Dart backends and Flutter with hosted or local models. TanStack client
interoperability must remain available; it must not dictate the native Dart API.
A passing fixture suite is not evidence of production maturity or a 10/10 SDK.

## Acceptance requirements still open

- Independent developer agents must write and run consumer applications across
  multiple scenarios and score discoverability, clarity, type safety, debugging,
  and testing. Record failures and rerun after fixes. Use GPT-6.1 Terra with low
  or medium reasoning. The latest review is 7.7/10, not an acceptance pass.
- Complete native provider coverage for OpenAI, Anthropic, OpenRouter, Together,
  Vercel AI Gateway, and Cloudflare, with a documented custom-provider contract.
  Track each endpoint, nested parameter, tool/event union, query, header, cache
  option, and continuation behavior against a dated authoritative specification.
  An OpenAI-compatible URL or SDK export does not establish native parity.
- OpenAI computer use and other non-function tool continuations require explicit
  event types, policy-controlled execution, complete input/output round trips,
  approval/safety handling, and fixtures before any support claim.
- Preserve provider options and metadata without letting configuration silently
  replace server-owned history, schemas, tools, or execution bounds. Unsupported
  response modes must fail explicitly or use a clearly separate native API.
- Provide runnable Serverpod examples for streamed chat, persisted approvals,
  typed output, tools, cancellation/reconnect, media and authentication. Verify
  recreation/restart behavior and failure recovery with PostgreSQL.
- Provide equivalent framework-independent recipes and adapters for Dart Frog
  and other HTTP servers; verify Flutter device/local-provider behavior.
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
immutable run results and usage; typed approval resolutions; scripted test
providers; atomic final event/checkpoint/release; safer observer handling;
separate caller/model/output/tool/step-limit errors; guarded provider request
configuration; canonical reasoning replay includes; actual provider model usage.

Tests now exercise the same storage contract against memory and PostgreSQL,
recreated PostgreSQL approval flows, local loopback HTTP, both existing clients,
and the new native Dart API. Consult validation results for the exact checks.
These improvements do not complete the requirements above.
