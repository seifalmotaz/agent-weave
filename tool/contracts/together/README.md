# Together contract source

These are unmodified declaration snapshots from Together's official TypeScript
SDK at the full commit in `source.json`. The upstream files are licensed under
Apache-2.0; retain the accompanying `LICENSE`. They are reference fixtures, not
Dart library implementation files.

`node tool/interop/inventory.mjs --write` generates
`docs/together-chat-inventory.json` using the pinned TypeScript 6 compiler API.
It retains interfaces, inheritance, nested namespaces and type aliases from both
source files. TypeScript 7 currently exposes a different unstable compiler API.

From the workspace root, after `dart pub get` and
`npm ci --prefix tool/interop --ignore-scripts`, reproduce the offline check:

```sh
dart run tool/together_contract.dart
node --test tool/interop/inventory.test.mjs
node tool/interop/inventory.mjs --check
```

The Dart fixture serializes every typed chat option. The checker compares its
actual field set with the pinned declarations and `coverage.json`. Each
upstream top-level request field must be classified as a typed option,
runtime-owned value or raw-native-only field. These checks do not prove nested
parameter semantics, response normalization, model acceptance or live behavior.

`node tool/interop/inventory.mjs --upstream` fetches the same two files from
upstream `main` and fails when either source changes. This runs only through the
manual upstream-review workflow. A source change can include documentation;
review the diff before changing the pin. To update, select and record a full
commit, fetch both files at that revision, review all changed declarations and
stream handling, adjust the Dart API/fixtures/coverage, then regenerate the
inventory with `--write` and rerun `dart run tool/check.dart`. Preserve the license.
