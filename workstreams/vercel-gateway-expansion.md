# Vercel AI Gateway provider completion

Status: post-base-release tracking draft. No unchecked implementation is complete.

## Scope

Public Vercel AI Gateway APIs and model/provider-specific lifecycle semantics.

## Existing evidence

Public Chat/Responses adapters, typed routing options, raw envelopes and offline fixtures exist.

## Remaining work

- [ ] Refresh dated official API/option inventory, including nested provider routing, BYOK, cache and request settings.
- [ ] Implement missing public endpoint workflows and normalize supported events without inferring provider identity.
- [ ] Exercise errors, deadlines, credential rotation, streaming, tools and usage through actual loopback HTTP.
- [ ] Document distinction between public Gateway APIs and the internal AI SDK wire protocol; verify authorized live routing separately.

## Resume rules

Wait for the base-framework milestone in PRs #1–#4. Revalidate source, upstream versions and CI before implementation. Use an independent developer consumer each round and report scoped evidence. Preserve existing behavior and credentials on the backend. Do not reset the paid-test ledger or exceed the existing $5 cumulative ceiling. Publication and paid external actions need their applicable authorization.
