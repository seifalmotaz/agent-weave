# Serverpod base framework reliability and acceptance

Status: tracking draft. This file is an implementation checklist, not completed implementation.

Goal: finish the primary Serverpod developer journey using the existing runtime and storage module.

Already present: authenticated endpoints, owner-scoped PostgreSQL store, native WebSocket/HTTP fixtures, graceful process-restart approval test and client restoration recipes. The new offline onboarding consumer uses memory and in-process callbacks, not PostgreSQL or WebSockets.

Remaining:
- [ ] Audit the main Serverpod journey against actual integration tests: streaming, typed output, tools, approval restoration, cancellation, reconnect and owner isolation.
- [ ] Publish a compact evidence matrix linking each claimed journey to its executable test and known limits.
- [ ] Verify current reconnect/cancellation failure recovery with the generated client and real PostgreSQL; add missing regression cases only where evidence is absent.
- [ ] Verify old unfinished-profile migration guidance and preservation of completed history.
- [ ] Have an independent developer run the guide; fix concrete setup/debugging friction.

Start with examples/serverpod/README.md and test/integration, then packages/agent_weave_serverpod and storage_server. Run PostgreSQL suites serially. Graceful restart is not proof of arbitrary crash recovery or exactly-once external effects. Keep owner identity server-controlled and external effects idempotent.
