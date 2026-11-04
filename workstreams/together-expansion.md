# Together provider completion

Status: post-base-release tracking draft. No unchecked implementation is complete.

## Scope

Native Together workflows beyond the currently integrated Chat subset.

## Existing evidence

Native Chat, typed options, request-field inventory and offline continuation fixtures exist.

## Remaining work

- [ ] Refresh official operation/nested-field inventory and record exact current handling.
- [ ] Complete remaining media, embeddings, generation and other prioritized native endpoints with typed request/result contracts.
- [ ] Verify multi-choice, legacy tool modes, streaming fragments, metadata and cancellation without changing existing runtime ownership guards.
- [ ] Run independent consumers and update capability tables; keep live model acceptance and billing separate from fixture results.

## Resume rules

Wait for the base-framework milestone in PRs #1–#4. Revalidate source, upstream versions and CI before implementation. Use an independent developer consumer each round and report scoped evidence. Preserve existing behavior and credentials on the backend. Do not reset the paid-test ledger or exceed the existing $5 cumulative ceiling. Publication and paid external actions need their applicable authorization.
