# Dart Frog and Flutter ecosystem expansion

Status: post-base-release tracking draft. No unchecked implementation is complete.

## Scope

Framework integration and end-user developer experience after the Serverpod-first base release.

## Existing evidence

Dart Frog handlers and official-client loopback fixtures exist. Framework-independent APIs exist; broad device/proxy/production deployment validation remains open.

## Remaining work

- [ ] Create runnable Flutter UI and Dart Frog application recipes for text, typed output, approvals, reconnect and cancellation.
- [ ] Verify reverse-proxy streaming, disconnects, authentication and deployment behavior on actual target environments.
- [ ] Use independent developer consumers to justify integration helpers before introducing them.
- [ ] Evaluate optional TanStack adapter packaging with PR #4; preserve existing clients while keeping native Dart APIs primary.

## Resume rules

Wait for the base-framework milestone in PRs #1–#4. Revalidate source, upstream versions and CI before implementation. Use an independent developer consumer each round and report scoped evidence. Preserve existing behavior and credentials on the backend. Do not reset the paid-test ledger or exceed the existing $5 cumulative ceiling. Publication and paid external actions need their applicable authorization.
