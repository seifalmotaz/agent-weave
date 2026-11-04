# Ollama and Flutter local-model validation

Status: post-base-release tracking draft. No unchecked implementation is complete.

## Scope

Native local models and the actual Flutter/device developer journey.

## Existing evidence

Native JSON/NDJSON chat/generate, thinking/tool replay, typed options and embedding fixtures exist; no real daemon/model/device certification exists.

## Remaining work

- [ ] Audit remaining native endpoints and model-dependent options against official sources.
- [ ] Run a real local daemon with a documented model/version and test chat, structured output, tools, thinking and embeddings.
- [ ] Verify unsubscribe/backpressure, server interruption, reconnect and legacy/remote fragment handling.
- [ ] Build and run a minimal Flutter device/emulator consumer and record platform networking, permissions, lifecycle and cancellation behavior.

## Resume rules

Wait for the base-framework milestone in PRs #1–#4. Revalidate source, upstream versions and CI before implementation. Use an independent developer consumer each round and report scoped evidence. Preserve existing behavior and credentials on the backend. Do not reset the paid-test ledger or exceed the existing $5 cumulative ceiling. Publication and paid external actions need their applicable authorization.
