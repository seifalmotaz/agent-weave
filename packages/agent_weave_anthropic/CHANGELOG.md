# Unreleased

- Replace the interim MCP guard with owned server/toolset configuration for legacy, 2025 and 2026 beta modes, private call/result/listing replay, deferred local-tool continuation and indeterminate-send protection; continue rejecting raw configuration injection.
- Bind model continuations to immutable provider authority, betas, managed tools and request options. Managed tools require `authorityBindingId`; use `options`, `toolChoice`, `functionToolOptions`, `container`, `messageDecorations` and `systemCacheControl` instead of `configure`. Model constructors copy collections and are no longer const.

- Enable document citations and publish typed citation spans while preserving private replay.

- Use shared lossless typed JSON patches and exact numeric ownership/replay comparisons.

- Add typed/native hosted tools, opaque result replay, bounded paused turns, container reuse and programmatic caller checks.

- Add typed 17-member computer toolsets, read-only approvals, ordered and halted batches, validated text/image results, and environment binding.
- Accept scoped file-ID documents through native normalization; explain unsupported typed SDK configuration clearly.

- Add native JSON and SSE client access, request-scoped cancellation and a raw-protocol agent model. Preserve supported content blocks and unknown fields for continuation.
- Preserve private citation deltas and final cumulative cache and thinking usage. Reject deltas that do not match their block.
- Retain the SDK-backed model and apply typed configure changes without discarding unchanged unknown fields.
- Add document URLs, inline PDF, and inline plain-text inputs; reject unsupported file handles and formats before transport.

## 0.1.0-dev.1

- Add Anthropic Messages streaming model.
