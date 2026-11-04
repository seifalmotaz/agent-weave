# Compatibility

The interoperability baseline is `@tanstack/ai-client 1.0.1` and
`tanstack_ai_dart 0.4.0` at commit
`819ff289e6dabc5f424208b07ea9ac6f399cdccc`.

The root workspace pins the Dart client through a Git dependency override
because 0.4.0 was not on pub.dev when this workspace was created. Remove the
override only after checking the published package and rerunning interop tests.

## Implemented contracts

- Text streaming, standard reasoning events, and structured-output events.
- Native OpenAI Responses output references and buffered Chat URL references; see
  [output references](output-references.md).
- Typed Anthropic text citations, CUSTOM events, snapshots and hydration; see
  [citations](citations.md).
- Ordered completed media parts in assistant history, client snapshots and hydration.
- Selected OpenAI Responses hosted search, code, image and server tool-search
  output with private replay; see [hosted tools](openai-hosted.md).
- Anthropic Messages MCP servers, private use/result/listing replay and mixed local-tool continuation; see [MCP](anthropic-mcp.md).
- OpenAI Responses remote MCP configuration, private discovery/replay and provider-owned approval/denial through generic client interrupts; see [MCP approvals](openai-mcp.md).
- Configured server tools, client-tool pauses, and default tool approvals.
- Selected OpenAI Responses native computer calls with application-owned
  execution, safety approvals, screenshots, and continuation; see
  [computer use](computer-use.md).
- Approval, rejection, edited arguments, and continuation lineage.
- Server-owned conversation history and owner isolation.
- HTTP/SSE chat, history paging, and stored-event replay.
- Native Serverpod streaming through the existing Dart AI client.
- Generic generation progress and results, plus image/speech/transcription
  normalization helpers.

The official JavaScript test verifies text, reasoning, structured output, server tools,
default approvals, client tools, generation, and supported media input/history
round trips against a Dart HTTP server. The Dart tests exercise the client against
the runtime and a generated Serverpod endpoint over a real WebSocket. This is
not a claim of full TanStack AI core parity.

## Declared provider identity across resumes

Native OpenAI Responses and Anthropic Messages bind unfinished local approvals
and provider pauses to
its declared model, frozen options, complete managed-tool set and stable provider
account/transport authority. Managed tools require `authorityBindingId` and
immutable `options`/`toolChoice` in place of arbitrary configuration callbacks.
Old pending checkpoints without their original model profile fail closed.
See [approval contracts](approval-contracts.md#model-continuation-contracts).
This is an adapter capability, not a blanket identity guarantee for all providers
or undeclared custom models. Actual credentials, permissions and external effect
reconciliation remain application responsibilities.

## Pending checkpoint migration

Approvals now require a private exact tool contract. Pending records written by
older revisions without that snapshot cannot resume; start a new conversation
and retain the old history. Public client bindings remain unchanged. See
[approval contracts](approval-contracts.md) for the migration and diagnostics.

## Current limits

- Selected native computer use is implemented for OpenAI Responses and the
  Anthropic computer toolset. The application provides the actual driver. Native
  client-executed tools and other native tool kinds are unsupported; native
  approval arguments cannot be edited.
- Custom approval payload schemas, application-defined generic interrupts, subagents, client-owned MCP discovery,
  and general provider-hosted progress are not implemented. Citation normalization
  covers the five pinned Anthropic variants. OpenAI references retain opaque
  provider coordinates; precise OpenAI highlights and other providers remain open.
- Server tools execute sequentially. Applications can perform concurrency
  inside a tool, with their own cancellation and idempotency policy.
- Disconnecting a direct run cancels its provider request. Replaying a stored
  run does not restart it or recover execution after a server crash.
- Replay observers are bounded to 20 seconds per request. A timed-out observer
  must reconnect; the observation timeout does not cancel the original run.
- PostgreSQL is the supported persistent store. The raw SQL store does not
  claim SQLite compatibility.
- Binary artifact hosting is not implemented. Completed inline media parts are
  retained in stored assistant history and hydration; provider URLs may expire.
  Applications own media storage budgets and rendering.
- OpenAI resource coverage combines typed SDK delegation and an explicit raw
  JSON helper. Complete typed endpoint parity and exhaustive endpoint tests
  remain unfinished.
- Document support varies by adapter. Responses accepts URLs, inline data, and
  OpenAI file IDs. Anthropic accepts URLs, inline PDF, and inline plain text;
  native file IDs use `provider: 'anthropic'`; typed SDK configuration still
  cannot decode those handles. Gateway Responses accepts URLs and
  inline data but blocks file IDs. OpenRouter Responses also accepts URL/inline
  documents and rejects foreign file IDs. OpenRouter Chat, OpenAI Chat
  Completions, and Together reject document parts. See [documents](documents.md) for storage
  implications.
- OpenRouter has separate native Chat and stateless Responses adapters. Selected
  routing, plugin and cache options, ordered private reasoning replay and compact
  provider/cost metadata have offline fixtures. Selected Chat image output uses
  completed messages with private replay across approvals. Complete management,
  background, hosted tools and other media remain unfinished. The dedicated Image
  API has separate typed requests, discovery, native SSE and same-request JSON
  fallback; see [dedicated images](openrouter-image-api.md). These are offline
  fixtures, not live model or billing certification. See [OpenRouter](openrouter.md).
- Anthropic native JSON/SSE access preserves arbitrary JSON, while normalized
  chat handles selected block/delta types and the 17-member computer toolset.
  Pinned hosted blocks, bounded paused turns and container reuse are integrated
  with offline fixtures. MCP adds three explicit beta modes and private listing
  replay; browser tools, live hosted behavior and complete
  nested field semantics remain unfinished. The
  SDK-backed facade retains its pinned SDK transport cancellation limits.
  See [Anthropic](anthropic.md).
- Together Chat has typed options and native JSON methods. Its agent adapter
  supports one choice; model acceptance of tools, schema, and media remains
  unverified. See [Together](together.md).
- Vercel AI Gateway supports selected Chat and Responses contracts with offline
  fixtures; provider selection, model acceptance, and billing are unverified.
  See [Vercel AI Gateway](vercel-gateway.md).
- Cloudflare supports selected native Workers AI, Gateway run, and compatible
  Chat and Responses contracts with offline fixtures. Model availability,
  acceptance and live gateway behavior are unverified. Native traditional tool
  continuation is limited to the documented Hermes single-call format. See
  [Cloudflare](cloudflare.md).
- Ollama native chat uses NDJSON with private thinking, native call ID and metadata
  replay. Typed options and embeddings are available; a real daemon, model and
  Flutter device remain untested. External image URLs are not fetched, only inline
  base64 images are accepted. Conflicting repeated tool indexes fail explicitly.
  See [Ollama](ollama.md).
- Dart Frog handlers support authenticated chat, history, replay and typed
  generation over actual local HTTP. Production authentication, reverse-proxy
  disconnects and durable restart require application-level verification. See
  [Dart Frog](dart-frog.md).
- Microphone capture, playback, WebRTC device behavior, and all provider account
  permissions require application/device testing.

These limits are release work, not hidden fallbacks. See `docs/validation.md`
and `docs/updating.md` before extending a compatibility claim.

## Native Dart streaming

`streamText` and `AiAgent.stream` expose sealed `AgentUpdate` values, including a
typed result from the same execution, without parsing client protocol maps.
Existing clients continue using `AiAgent.run`. The native stream is a backend or
local-model API: interim updates are provisional and final results can contain
private provider continuation. Use hydration projections for UI history.
Protocol journals remain in core; optional adapter-package extraction is not
complete. See [native streaming](native-streaming.md).
