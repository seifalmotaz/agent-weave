## Unreleased

- Negotiate JSON or SSE from a single POST without resubmitting generation.
- Cancel late response bodies after header-wait cancellation and retain status/request IDs on malformed buffered responses and SSE UTF-8 without exposing decoder source bytes.

## 0.1.0-dev.1

- Share cancellable JSON POST and SSE transport across native provider adapters.
- Add GET and byte request methods for provider discovery and binary payloads.
- Include preparation in request deadlines and retain per-request response metadata.
- Add native NDJSON with fragmented UTF-8, independent cancellation and deadlines.
