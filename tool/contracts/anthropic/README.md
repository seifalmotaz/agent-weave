# Anthropic Messages contract snapshot

`messages.ts` is the unmodified official Apache-2.0 TypeScript SDK source at
the full revision in `source.json`; the upstream license is retained in
`LICENSE`. The source is reference material, not executable application code.
It was retrieved from the pinned raw GitHub URL. The source and inventory include
no credentials.

`node tool/interop/anthropic-inventory.mjs --check` checks deterministic
artifacts and field dispositions. `--upstream` also compares the selected
request, response and stream declarations and their locally declared type
references with current upstream main. Imports, documentation-only changes and
unrelated endpoints are outside this projection. Review drift before changing
the pin; upstream checks never update it. After review update the snapshot,
revision, coverage and behavior together, then run `--write` and the checks.
The inventory is not evidence of nested implementation or live compatibility.
