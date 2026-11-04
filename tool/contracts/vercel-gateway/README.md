# Gateway option source

Unmodified Apache-2.0 reference source from the full Vercel AI SDK commit in
`source.json`. Retain its license. This SDK type is an option discovery source,
not a public HTTP endpoint specification or a live-service verification.

After reviewing a source update, record a full commit, fetch the unmodified file
at that revision, classify every named option in `coverage.json`, update the Dart
API and executable fixture, and regenerate:

```sh
node tool/interop/gateway-inventory.mjs --write
dart run tool/gateway_contract.dart
node tool/interop/gateway-inventory.mjs --check
```

`--upstream` compares the pinned source file with upstream main. A changed
comment can also require review. Unknown service-owned fields use controlled
`GatewayOptions.extra`; credentials use the resolver and client-only image
options are not HTTP parameters. Conditional Decisions fallback and batch/media
orchestration remain separate work. This inventory never marks them complete.
