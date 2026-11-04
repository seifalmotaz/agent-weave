# Native Dart API and base release readiness

Status: tracking draft. This file is an implementation checklist, not completed implementation.

Goal: make the base SDK idiomatic, understandable and reviewable for Dart developers and coding agents.

Already present: sealed native AgentUpdate streams, final results from one execution, safe public errors with backend diagnostics, provider extension contracts and searchable GitHub Pages/LLM guides. Protocol journals and TanStack dependencies still live in core.

Remaining:
- [ ] Audit public examples for native Dart streaming/results first, and fix any guide that unnecessarily requires wire maps.
- [ ] Evaluate TanStack protocol/dependency boundaries; propose extraction only when it removes demonstrated coupling. Preserve both existing clients and their compatibility tests.
- [ ] Review public API naming, ownership, cancellation/error contracts and setup with independent runnable consumers.
- [ ] Audit package dependency and dry-run publish readiness. The workspace uses an unpublished tanstack_ai_dart Git pin; do not claim all packages publishable until this is resolved.
- [ ] Verify docs/search/LLM source freshness on deployed Pages, minimum/stable CI and release/migration notes.
- [ ] Record remaining limitations and obtain publication authorization before any pub.dev release.

Do not publish packages, reset the paid-test ledger, delete unrelated artifacts or report a fixture score as full SDK acceptance. Other providers, exhaustive provider APIs and specialized hosted/computer/MCP features are later work.
