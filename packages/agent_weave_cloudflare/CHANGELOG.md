## Unreleased

- Stream native text SSE by default with `streamText` opt-out. Keep schema and traditional tool requests buffered and count reported usage once at completion.

# 0.1.0-dev.1

Initial development version with distinct Workers AI native, Gateway run and
compatible Chat/Responses clients, selected typed media results, and offline
contract tests. Native traditional tools support the documented single-call
Hermes replay only. Live model support and exhaustive API parity are unverified.
- Preserve inherited Gateway IDs when a request overrides cache headers.
