# OpenAI custom-tool contract

`responses.ts` is shared with `../openai-computer/` at the commit in `source.json`.
`shared.ts` is the unmodified official source at that same revision. Both are
Apache-2.0; `source.json` records their SHA-256 hashes.

After reviewing any selected declaration change, update the pin and hashes,
review the projected changes in `reviewed-declarations.json`, then run
`node tool/interop/openai-custom-inventory.mjs --write` and commit its generated
artifacts. `--check` verifies the pin, review, Dart fixture and generated docs;
`--upstream` compares selected declarations with upstream main without changing
the pin. These checks cover selected declarations, not the complete Responses
API, model availability, live provider acceptance, or workflow certification.
