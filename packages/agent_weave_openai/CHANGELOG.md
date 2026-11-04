# Unreleased

- Add native Responses MCP configuration, per-request credentials, multiple servers, private replay, approval/denial continuation and correlated approval echoes.
- Preserve MCP raw options independently of the pinned SDK and require stable credential authority bindings.

- Publish typed Responses references and buffered Chat URL annotations while keeping provider metadata private.
- Use raw native Chat events and reject unknown/inconsistent finish reasons before tools; compatible-provider adapters retain their own contracts.

- Add native Responses options and selected hosted search, code, server tool-search and complete image output with private replay.
- Validate terminal calls before releasing application tools; preserve raw response metadata separately.
- Reject unregistered Chat/compatible Responses tools and exact large-number mutations in runtime-owned schemas.
- ResponsesProtocolModel transport/configure fields are now internal and its typed constructor is non-const; constructor callback names remain unchanged.

- Add app-executed OpenAI Responses computer calls with approval and screenshot continuation.
- Preserve original Responses SSE items before typed decoding and reject unknown computer action fields before execution.

- Preserve raw Responses reasoning/tool output input fields and snapshot configuration guards before callbacks.
- Protect absent history fields, alternate Chat token bounds and stream options.

- Allow compatible Responses transports to omit OpenAI encrypted-reasoning includes.

- Extract reusable typed Chat/Responses protocol models and isolate provider replay.
- Fix assistant text and tool-call history serialization for Chat continuation.
- Reject unsupported choices/audio and require a Responses terminal event.

- Add URL, inline-data, and provider-scoped document inputs to Responses.

- Fail explicitly on native tool continuations that the function-tool loop cannot execute.

- Add per-request headers, generic JSON and raw response access, repeated-query downloads, and PUT/HEAD transport.

- Preserve canonical requests and encrypted replay state when configuring provider options.

## 0.1.0-dev.1

Initial development version. See the workspace compatibility and validation
documents for implemented contracts, tests, and remaining work.
