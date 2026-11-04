# Cloudflare source contracts

`openapi-ai.json` is an extracted subset of Cloudflare's official API schema,
including all `/accounts/{account_id}/ai/` and `/ai-gateway/` paths and their
local component references. The original schema is at
https://github.com/cloudflare/api-schemas/blob/193e683baba9c46b675d91c959c3b9a726b2d184/openapi.json.
Cloudflare copyright 2022, BSD-3-Clause; see `LICENSE`. The extraction changes
only the included paths and components. It retains their content.

The six `bge-*`, `whisper-*` and `flux-*` JSON files are unmodified public
Cloudflare documentation model schemas, downloaded on 2026-11-04. Exact URLs
and SHA-256 hashes are recorded in `docs/cloudflare-api-inventory.json`.
Cloudflare documentation is licensed under CC BY 4.0; see `DOCS-LICENSE` and
https://github.com/cloudflare/cloudflare-docs/blob/production/LICENSE.
Generated field inventories reorganize the schemas and attribute Cloudflare.
Neither source grants official Cloudflare endorsement of AgentWeave.

Run `python3 tool/cloudflare_contract.py --check` offline. The explicit
`--upstream` flag reads current official sources and fails on relevant drift;
it never updates files. For a reviewed update, change the revision in the tool,
download the official schema and public model schemas, then regenerate using
`--extract /path/to/openapi.json`. Review the implementation and tests together.
New operation entries default to `not-integrated`.
