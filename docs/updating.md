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

## Cloudflare contracts

Review the [Cloudflare API reference](cloudflare-api-reference.md) and its
machine-readable inventory when provider schemas or documented contracts
change. Update the relevant implementation, fixtures, and dispositions
together. Verify model-specific schemas separately; an inventory entry does not
prove live model acceptance.

```sh
python3 tool/cloudflare_contract.py --upstream --check
python3 tool/cloudflare_contract.py --check
```

The manual upstream workflow compares the selected Cloudflare OpenAPI paths and
six public model schemas with the reviewed snapshots. It fails on drift and
never rewrites the pin. See `tool/contracts/cloudflare/README.md` for refreshing
the revision, retained licenses and operation dispositions.

## OpenRouter contracts

The OpenRouter source is a SHA-256-pinned official OpenAPI document
with a stated MIT license. Credential-shaped example values are redacted in the
retained snapshot, which has a separate hash. The updater verifies both hashes
and the deterministic transformation. Its inventory retains references and records component
fields once, avoiding repeated expansion of recursive schemas. All operations
receive an explicit status; only selected Chat/Responses behavior is integrated.

```sh
python3 tool/openrouter_contract.py --upstream --check
python3 tool/test_openrouter_contract.py
python3 tool/openrouter_contract.py --check
```

Review source drift, the field statuses, implementation and fixture behavior
together before changing the hash. New and removed request fields both require
a disposition update; stale classifications fail the check. New fields forwarded through native JSON
still need a disposition and tests for any claimed orchestration. See
`tool/contracts/openrouter/README.md` for provenance and retained license.

## OpenAI computer contract

`tool/contracts/openai-computer/source.json` pins the official `openai-node`
Responses declarations, with its Apache-2.0 license retained beside the source.
The inventory checks selected computer declarations and reviewed field types,
not the entire Responses API. After installing the interop tool dependencies:

```sh
dart run tool/computer_contract.dart
node --test tool/interop/computer-inventory.test.mjs
node tool/interop/computer-inventory.mjs --check
node tool/interop/computer-inventory.mjs --upstream
```

The last command compares upstream main with the pinned projection; review drift and official
provider documentation before changing the revision or regenerating the inventory.
Update the reviewed types, Dart behavior and fixtures together. These offline
checks do not establish live provider or model support.

## Anthropic Messages contract

The official TypeScript source is pinned in `tool/contracts/anthropic/source.json`.
The inventory follows request, response and stream declarations plus their local
type references. Imported types and unrelated endpoints are outside this scope.
Top-level dispositions describe access, not full nested or model semantics.

```sh
node --test tool/interop/anthropic-inventory.test.mjs
node tool/interop/anthropic-inventory.mjs --check
node tool/interop/anthropic-inventory.mjs --upstream
```

Review field and union drift before changing the pin. Update the native client,
normalizer, SDK patch preservation, request fixtures and disposition together.
New raw JSON fields do not imply the agent supports their continuation protocol.

## Anthropic computer toolset

The selected computer projection uses the existing Anthropic source pin. Its
Dart fixture serializes the actual helper, typed configs, all action parameters,
scroll enum values and result payloads. The check runs `dart` from PATH; CI uses
the selected minimum or stable SDK. The upstream-only check does not require Dart.

```sh
node --test tool/interop/anthropic-computer-inventory.test.mjs
node tool/interop/anthropic-computer-inventory.mjs --check
node tool/interop/anthropic-computer-inventory.mjs --upstream
```

Review documentation-only constraints separately, including direct callers,
numeric limits and stopping a batch after failure. The official SDK declaration
currently omits the documented `allowed_callers` field. Parameter forwarding is
not evidence of real desktop operation or complete provider support.

## Ollama native contracts

`tool/contracts/ollama` retains the official OpenAPI and Go API declarations at
the revision recorded in its README. Review both sources: the OpenAPI omits
some fields already present in the Go server types. The selected operation and
field inventory distinguishes raw access from normalized runtime behavior.

```sh
python3 tool/test_ollama_contract.py
python3 tool/ollama_contract.py --check
python3 tool/ollama_contract.py --upstream --check
```

After reviewing a new pin, update source hashes, the parsed OpenAPI snapshot,
Go-only field dispositions and runtime fixtures together. Re-run native NDJSON
transport, private replay, tool-ID/index, cancellation, embedding and independent
consumer checks. The manual upstream workflow compares official source bytes.
Do not infer model acceptance or a universal tool-fragment merge rule from the
source inventory; record actual model/version evidence separately.

## Anthropic hosted lifecycle

Run `dart run tool/anthropic_hosted_contract.dart` after regenerating the existing
Messages inventory. It exercises all pinned server-tool type spellings through
the public constructor and excludes client tools. Review content/result unions,
container metadata, allowed callers and mixed client/server continuation against
the provider docs separately. Update the hosted fixtures, core continuation
tests, PostgreSQL scenario, official-client pause cases and consumer review
together; constructor coverage is not full orchestration or live evidence.

The `code_execution_20260521` caller option alias is documented outside the
response union: the provider returns the `code_execution_20260120` caller tag.
Keep the [programmatic-calling guide](https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling)
and both positive/negative caller fixtures in the review; a request-field pin
alone cannot prove that behavior.


## OpenAI hosted Responses tools

The selected hosted declarations share the OpenAI computer source pin and license.
`tool/contracts/openai-hosted/reviewed-declarations.json` records the reviewed
projection. A field or union change fails the check until it is reviewed.

```sh
dart run tool/openai_hosted_contract.dart
node --test tool/interop/openai-hosted-inventory.test.mjs
node tool/interop/openai-hosted-inventory.mjs --check
node tool/interop/openai-hosted-inventory.mjs --upstream
```

Review native definition fields, output unions and continuation rules together.
Update the reviewed projection, Dart serialization and parser tests before
regenerating the published inventory with `--write`. A private replay field is
not a public UI feature. Keep hosted execution distinct from registered local
functions and explicitly reject lifecycles without a handler.
