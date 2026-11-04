# Compatibility

The interoperability baseline is `@tanstack/ai-client 1.0.1` and
`tanstack_ai_dart 0.4.0` at commit
`819ff289e6dabc5f424208b07ea9ac6f399cdccc`.

The root workspace pins the Dart client through a Git dependency override
because 0.4.0 was not on pub.dev when this workspace was created. Remove the
override only after checking the published package and rerunning interop tests.

## Implemented contracts

- Text streaming, standard reasoning events, and structured-output events.
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

## Current limits

- Native computer use is limited to the OpenAI Responses adapter. Native
  client-executed tools and other native tool kinds are unsupported. Approval
  does not allow edited native arguments.
- Custom approval payload schemas, application-defined generic interrupts, subagents, MCP discovery,
  and provider-hosted tool event normalization are not implemented.
- Server tools execute sequentially. Applications can perform concurrency
  inside a tool, with their own cancellation and idempotency policy.
- Disconnecting a direct run cancels its provider request. Replaying a stored
  run does not restart it or recover execution after a server crash.
- Replay observers are bounded to 20 seconds per request. A timed-out observer
  must reconnect; the observation timeout does not cancel the original run.
- PostgreSQL is the supported persistent store. The raw SQL store does not
  claim SQLite compatibility.
- Binary artifact hosting and automatic media reconstruction after a client
  reload are not implemented. Inline results can be retained by application
  storage; provider URLs may expire.
- OpenAI resource coverage combines typed SDK delegation and an explicit raw
  JSON helper. Complete typed endpoint parity and exhaustive endpoint tests
  remain unfinished.
- Document support varies by adapter. Responses accepts URLs, inline data, and
  OpenAI file IDs. Anthropic accepts URLs, inline PDF, and inline plain text;
  file IDs are blocked by the pinned SDK. Gateway Responses accepts URLs and
  inline data but blocks file IDs. OpenRouter Responses also accepts URL/inline
  documents and rejects foreign file IDs. OpenRouter Chat, OpenAI Chat
  Completions, and Together reject document parts. See [documents](documents.md) for storage
  implications.
- OpenRouter has separate native Chat and stateless Responses adapters. Selected
  routing, plugin and cache options, ordered private reasoning replay and compact
  provider/cost metadata have offline fixtures. Complete management, background,
  hosted-tool and output-media integrations remain unfinished. See [OpenRouter](openrouter.md).
- Anthropic native JSON/SSE access preserves arbitrary JSON, while normalized
  chat handles selected block and delta types. Hosted tools, native computer
  use, pause-turn and complete nested field semantics remain unfinished. The
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
- Microphone capture, playback, WebRTC device behavior, and all provider account
  permissions require application/device testing.

These limits are release work, not hidden fallbacks. See `docs/validation.md`
and `docs/updating.md` before extending a compatibility claim.
