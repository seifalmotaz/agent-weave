# Update upstream dependencies

1. Record the current Dart, Serverpod, OpenAI SDK, and TanStack pins.
2. Run `python3 tool/audit_openai.py` to compare the official operation index.
   Review additions and removals before running `--refresh`.
3. Read the changed request schemas and stream-event contracts. An unchanged
   endpoint URL does not prove an unchanged contract.
4. Update provider fixtures and add a regression test for each behavior changed
   in AgentWeave. Use the provider SDK's own tests as additional evidence.
5. Update the official JavaScript client pin in `tool/interop/package.json` and
   its lockfile when changing the interoperability baseline.
6. Update the Dart client pin independently. Verify its published version before
   replacing the workspace Git override.
7. Resolve the lockfile with the minimum supported Dart SDK, then run
   `dart run tool/check.dart` on both the minimum SDK and stable. New transitive
   versions can require a newer SDK even when application constraints do not.
   Keep fixture and live results separate.
8. Update the compatibility matrix, changelogs, examples, and LLM documentation.

## Serverpod models

Use Serverpod CLI 4.1.0 while the packages target that version. Generate the
storage module before the example application:

```sh
serverpod generate --directory packages/agent_weave_serverpod_storage_server
serverpod generate --directory examples/serverpod/agent_weave_demo_server
```

Create a migration inside each affected server/module directory. Never edit
generated model or protocol files. Run real database tests after a schema or
transaction change.

## Releases

Run publication dry-runs for each package. Publish dependency packages before
their dependants. The native client currently depends on an unpublished Dart
client version, which must be resolved before publishing that package.
Create a reviewed tag and release notes that identify the tested upstream pins
and the remaining limits. A Git push is not a pub.dev publication.

## Custom store migration

`RunStore.complete` must atomically append the terminal event, save the final
checkpoint, and release the reservation. Do not implement it as two separately
committed calls. The shared contract in `test/support/run_store_contract.dart`
runs against both memory and PostgreSQL and exercises rollback and stale writers.

## Together contract snapshots

The native Together adapter is checked against a full official TypeScript SDK
commit. `tool/contracts/together/source.json` records the pin and original file
paths; unmodified reference snapshots retain their upstream license.

Run `node tool/interop/inventory.mjs --upstream` after installing the interop
tool dependencies to detect changes in the two upstream source files. This is
also part of the manually invoked upstream-review workflow. It can report
non-semantic documentation changes; review the source diff.

Select a full commit and update the snapshots before changing the pin. Review
changed field types, nested unions, stream semantics and response handling.
Update the Dart implementation, executable option fixture and `coverage.json`
dispositions, then run `node tool/interop/inventory.mjs --write` and the full
check. To reproduce the offline field check separately:

```sh
dart run tool/together_contract.dart
node tool/interop/inventory.mjs --check
```

A classified field is not evidence of model acceptance or exhaustive coverage.
Keep raw-native access, normalized agent behavior and live results distinct.

## Gateway option declarations

`tool/contracts/vercel-gateway/source.json` pins the official SDK option source
and retains its upstream license. The generated reference classifies named
options, credentials, native extensions and SDK-only fields. It is not a public
endpoint specification. Verify new options against current official HTTP docs.

```sh
node tool/interop/gateway-inventory.mjs --upstream
dart run tool/gateway_contract.dart
node tool/interop/gateway-inventory.mjs --check
```

Review any source change before updating the full commit and snapshot. Update
coverage dispositions, Dart options and fixture, then regenerate with `--write`
and run the full check. The manually invoked upstream workflow compares both
Together and Gateway sources; it does not publish packages or mutate pins.
