# OpenAI options audit

Audit scope: `agent_weave_openai` and installed `openai_dart` 11.0.1, compared with the [Responses API](https://platform.openai.com/docs/api-reference/responses/create), [computer-use guide](https://platform.openai.com/docs/guides/tools-computer-use), and [Realtime API](https://platform.openai.com/docs/api-reference/realtime). This is a source review, not an exhaustive certification of all OpenAI endpoints or individual nested SDK fields. No live API calls were made. SDK types or raw HTTP access do not imply AgentWeave orchestration or a working end-to-end feature.

| Area | SDK and adapter coverage | Gap and priority |
|---|---|---|
| Canonical request | `chat_models.dart:90–118,203–275` maps runtime messages, tools, instructions, token limit and output schema; typed `configure` can replace the whole request. | **P0:** replacement can silently erase or alter runtime messages, tool definitions, schema, and Responses encrypted-reasoning include. Define ownership and merge rules, preserve canonical inputs/tools, and test multiple turns and callback conflicts. Changing model also makes emitted usage report the constructor model, not necessarily the actual model. |
| Responses options | SDK `CreateResponseRequest` includes model/input, instructions, tools/tool choice, previous response ID, max output/tool calls, temperature/top-p/penalties, reasoning/text, truncation/context management, parallel calls, service tier, metadata, include/store/background, safety/moderation, cache key/options/retention, top logprobs, multi-agent and access programs. Callback can set SDK-supported fields. | **P1:** options are not first-class runtime semantics; callback can conflict with canonical history and can overwrite required includes. SDK `createStream` forces `stream=true`; adapter never passes `beta=true`, required by SDK for multi-agent. Background and prior-response state need explicit lifecycle and duplicate-history rules. Check server/model constraints. |
| Responses events | `chat_models.dart:124–172` handles text/refusal/reasoning-summary deltas, completed function calls, final output and token usage. Full completed output is saved as provider replay. | **P0:** only `function_call` becomes a runnable `ToolCallReady`; computer, custom, shell, apply-patch and approval continuations are not dispatched. All tool messages become `function_call_output`. Hosted-tool events and results are retained for replay only and are not surfaced as typed progress/results. Refusals lose their distinction, incomplete causes collapse to length, errors lose details, and no terminal event is required before stream EOF. Preserve IDs, statuses, annotations, errors, incremental events and output kinds. |
| Computer use | SDK parses `computer_call` output (`models/responses/items/output_item.dart`); callback can configure SDK tool types. | **P0:** no action executor, screenshot result, safety-check acknowledgement or correct `computer_call_output` continuation in runtime. SDK `items/item.dart` dispatch does not list `computer_call_output`: verify its round trip and contribute a typed input item upstream if missing. Raw JSON sent independently is not an AgentWeave computer loop. Explicit authorization and sandbox controls belong at the execution boundary. |
| Function tools | Runtime tool schemas and JSON-object arguments are mapped; tool calls are dispatched. | **P1:** `strict:false` is fixed, arguments are assumed JSON objects, output is text only, and per-tool provider options are absent. Validate schema/arguments, preserve tool IDs and correctly represent multimodal and non-function results. Hosted tools need not be run locally. |
| Cache and state | SDK supports `prompt_cache_key`, options and retention; adapter reports `cached_tokens` if usage is present. Responses defaults to `store:false`, includes encrypted reasoning, and replays completed output. | **P1:** setting a key is not evidence of a cache hit; no cache hit/miss diagnostics or cache lifetime validation. Changing `include` can drop encrypted reasoning. `store`, `previous_response_id`, conversation state, deletion and retrieval have privacy and replay implications; test exact outgoing payloads and cache usage with an authorized live run. See [prompt caching](https://platform.openai.com/docs/guides/prompt-caching). |
| Query and transport | SDK `responses.retrieve` and input-item `list` accept typed `include[]` and pagination; `platform_api.dart` supports JSON, binary GET, repeated query keys, idempotency and cancellation with client interceptor chain. | **P1:** these are separate SDK/raw operations, not run lifecycle integration. Raw helper now supports GET/POST/PUT/PATCH/DELETE/HEAD, per-request safe headers, arbitrary JSON roots, response status/headers/bytes, and repeated queries for downloads. Multipart upload and arbitrary SSE remain outside this helper. Typed stream exposes abort and beta but adapter exposes only abort. Provide per-request transport options without compromising auth, retry, secret redaction or canonical request ownership. |
| Chat completions | SDK request exposes sampling, penalties, logit bias/logprobs, n, stop, tools, output format, audio/modalities, prediction, search, caching, safety, metadata/store and more through callback. | **P1:** `chat_models.dart:297–318` ignores choices other than index 0; audio output, logprobs and other deltas are not emitted, even when enabled. Either support each requested output or reject unsupported configurations; test `n`, audio and tool streaming. File and video input are explicitly rejected. |
| Images/audio/embeddings/video | `generation_models.dart` forwards SDK request objects for image generation, speech, transcription, embeddings, decision and video. Speech/transcription streaming and image streaming exist. `generation_tasks.dart` normalizes image, speech and transcription results. | **P1:** forwarding only covers fields represented by the pinned SDK; normalized tasks drop provider-specific metadata (including transcription detail) and create local IDs. Image nonstream and video create cannot abort in-flight through these wrappers; cancellation of local video waiting does not cancel a server job. Image edits/variations, translation and job operations remain direct SDK/raw workflows. Audit individual request serialization and response fields before claiming all media options. |
| Realtime | `OpenAIRealtimeModel` passes a typed session config including audio, modalities, tools, reasoning, tracing, truncation and include to SDK connection; caller owns returned session. | **P1:** this is connection access, not runtime event, tool, interruption or voice orchestration. Connection cancellation is checked before and after connect rather than aborting the handshake; session lifetime is caller-owned. WebRTC, SIP, client secrets and raw realtime events require separate SDK/API paths and their own verification. |
| API surface and future fields | Public package exports SDK surfaces; raw helper can address additional JSON endpoints. | **P2:** typed parsing may reject or drop unknown fields, while raw path has transport and response restrictions above. Inventory each endpoint, parameter, nested union and event against a dated official spec; test unknown enum/item handling. Contribute missing fields upstream rather than presenting reexports as complete integration. |

## Verification and proposed sequence

1. Add fixture-based request/stream tests proving canonical messages and tools survive configuration, required includes are merged, usage identifies the actual model, and unsupported combinations fail visibly. Cover cancellation, EOF, incomplete/failure causes, `n > 1`, cache options and repeated query keys.
2. Design typed provider events and continuation items before implementing each client-executed tool loop. Verify call IDs, multiple actions, screenshot content and safety acknowledgements across at least two turns; separately expose hosted-tool results and approvals. Keep side-effectful execution opt-in and constrained by caller policy.
3. Expose response-state and request transport controls with explicit storage, replay and retry semantics. Test retrieve/list query encoding, background lifecycle, and redaction using mock HTTP.
4. Audit every media/realtime SDK request and output union against the official endpoint schema, then add serialization and event round-trip fixtures for each claimed field. Submit reproducible upstream issues or patches for confirmed SDK omissions; preserve compatibility with the pinned version.
5. Only after fixture coverage, run separately authorized, cost-bounded live scenarios for real model/tool capability, cache metrics, media and realtime. Unit fixtures establish serialization and orchestration, not server behavior, model support or actual cache hits.

Existing tests in `packages/agent_weave_openai/test` use fixtures and cover selected text, function-call, generation, transport and cancellation paths. This audit did not run them or establish exhaustive coverage.

## Update: current worktree

The current `chat_models.dart` now guards runtime-owned messages/input and token limits, requires each runtime tool exactly once, and protects an existing runtime output schema; it merges `reasoning.encrypted_content` into Responses `include`. Usage reports the returned response model when present, falling back to the configured model. Fixture tests in `chat_models_test.dart` cover rejected conversation replacement, include merging, cache key/metadata serialization, and Responses returned-model usage. These changes supersede the corresponding earlier P0 request-replacement and P1 include/model findings; they do not establish exhaustive configuration coverage or live behavior. The P0 computer and other non-function tool continuation gaps remain open. The guard only compares runtime fields present in the canonical JSON and permits additional provider tools; audit individual conflicting settings before claiming full option safety.

The current raw transport fixtures verify request-specific safe headers, repeated
queries on binary downloads, raw status/headers/bytes, arbitrary JSON root
values, authenticated PUT requests, pre-cancellation and mutation retry policy.
This does not implement SSE, multipart or computer-use orchestration.

## Computer-use SDK contribution

[Upstream PR #430](https://github.com/davidmigloz/ai_clients_dart/pull/430) adds
typed computer-call input replay and screenshot results, including returned-only
statuses and redacted screenshots. Local upstream validation passed 25,235 unit
tests with 3 skips plus package analysis. The PR is submitted, not merged or
released. AgentWeave still uses its published SDK dependency. Native computer,
shell/custom/patch calls and MCP approval continuations fail explicitly instead
of being silently treated as completed function-tool runs. Runtime execution
and full computer-use orchestration remain unfinished.

## Protocol reuse and Chat continuation

The current SDK facades delegate canonical encoding and normalization to reusable
protocol models. Chat assistant history now uses text or null as required by the
SDK request type; two-turn tool continuation previously failed before dispatch
because assistant content was encoded as a user-style parts list. Protocol and
actual SDK transport regressions now exercise the second request.

Chat explicitly rejects multiple choices and requested audio output instead of
silently dropping unsupported results. Responses requires a terminal event before
EOF. These supersede the corresponding silent-drop/EOF observations above;
remaining event, media and computer-use gaps are still open.
