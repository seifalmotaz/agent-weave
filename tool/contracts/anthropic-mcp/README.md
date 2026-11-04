# Anthropic Messages MCP contract

`messages.ts` is the unmodified beta Messages declaration source at the immutable commit in `source.json`; its Apache-2.0 license is retained here. `reviewed-declarations.json` records both the exact source SHA-256 and the reviewed recursive projection. The tool follows local references, retains external types without expansion, and fails when an MCP declaration appears or disappears without classification.

After installing the interop dependencies, run from the workspace root with Dart on PATH:

```sh
dart run tool/anthropic_mcp_contract.dart
node --test tool/interop/anthropic-mcp-inventory.test.mjs
node tool/interop/anthropic-mcp-inventory.mjs --check
node tool/interop/anthropic-mcp-inventory.mjs --upstream
```

`--upstream` compares the selected projection against upstream main and never mutates the pin or files. Review source, official guide, beta versions, field and union changes, implementation and fixtures before changing the full commit, source bytes or reviewed JSON. After review, run `node tool/interop/anthropic-mcp-inventory.mjs --write` and `--check`. `--write` does not approve declaration changes. The Dart fixture verifies request configuration and credential isolation, not SSE normalization or live behavior; check protocol tests independently. The 2025-04-04 legacy mode is deprecated and provider availability is not established.
