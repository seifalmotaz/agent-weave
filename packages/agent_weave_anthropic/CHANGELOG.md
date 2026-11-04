# Unreleased

- Add native JSON and SSE client access, request-scoped cancellation and a raw-protocol agent model. Preserve supported content blocks and unknown fields for continuation.
- Preserve private citation deltas and final cumulative cache and thinking usage. Reject deltas that do not match their block.
- Retain the SDK-backed model and apply typed configure changes without discarding unchanged unknown fields.
- Add document URLs, inline PDF, and inline plain-text inputs; reject unsupported file handles and formats before transport.

## 0.1.0-dev.1

- Add Anthropic Messages streaming model.
