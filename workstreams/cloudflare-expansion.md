# Cloudflare Workers AI and Gateway completion

Status: post-base-release tracking draft. No unchecked implementation is complete.

## Scope

Native Workers AI and AI Gateway contracts, including model-specific schemas.

## Existing evidence

Selected native run/discovery/media and compatible Chat/Responses adapters exist, with native text streaming fixtures.

## Remaining work

- [ ] Refresh native operation and model-specific schema inventories; classify unsupported or unknown capabilities explicitly.
- [ ] Complete binary/audio transport, caching/query/header options and remaining prioritized native workflows.
- [ ] Expand native tool continuation beyond the documented Hermes single-call contract only with authoritative source evidence.
- [ ] Verify streaming, auth, cancellation, owner isolation and metadata in independent consumers; test live availability and billing separately.

## Resume rules

Wait for the base-framework milestone in PRs #1–#4. Revalidate source, upstream versions and CI before implementation. Use an independent developer consumer each round and report scoped evidence. Preserve existing behavior and credentials on the backend. Do not reset the paid-test ledger or exceed the existing $5 cumulative ceiling. Publication and paid external actions need their applicable authorization.
