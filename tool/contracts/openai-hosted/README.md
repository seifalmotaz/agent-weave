# Selected OpenAI hosted-tool contract

The source, full commit pin and Apache-2.0 license are retained in
`../openai-computer/`. This directory contains the reviewed declaration
projection used by `tool/interop/openai-hosted-inventory.mjs`.

Update the source pin only after reviewing official documentation and the
selected field/type/union diff. Update Dart behavior, fixtures and this baseline
together. `--write` regenerates the published inventory, not the review baseline.
External type references remain references; this is not full nested coverage.

```sh
dart run tool/openai_hosted_contract.dart
node --test tool/interop/openai-hosted-inventory.test.mjs
node tool/interop/openai-hosted-inventory.mjs --check
node tool/interop/openai-hosted-inventory.mjs --upstream
```


The projection also reviews four Responses annotation variants, their stream
coordinates and the message/content-part boundaries used for reconciliation.
`chat-source.json` pins the separate completed Chat message declarations;
`chat-completions.ts` is an unmodified official source snapshot, retained with
its Apache-2.0 license. Reviewed projections and tests distinguish insertion
positions from file-list ordinals. Source types do not prove a Unicode unit for
native indices. Run the existing inventory with `--upstream` to compare both
selected projections against current upstream.
