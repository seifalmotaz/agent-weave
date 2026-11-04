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
