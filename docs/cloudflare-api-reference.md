# Cloudflare API inventory

Source: [Cloudflare OpenAPI](https://raw.githubusercontent.com/cloudflare/api-schemas/193e683baba9c46b675d91c959c3b9a726b2d184/openapi.json), revision `193e683baba9c46b675d91c959c3b9a726b2d184`, reviewed 2026-11-04.

The pinned schema contains 82 operations across 50 Workers AI and AI Gateway paths. Four operations have selected AgentWeave integrations. The rest remain explicitly unimplemented.

Download the [machine-readable inventory](cloudflare-api-inventory.json) for nested request and response fields, unions, required flags, defaults, enum values and parameter constraints. These are specification entries, not claims that AgentWeave executes every option.

Model documentation schemas are attributed to Cloudflare under CC BY 4.0, with unmodified snapshots and generated field inventories. The OpenAPI source is BSD-3-Clause. See the retained licenses and attribution in `tool/contracts/cloudflare/README.md`.

The complete selected source schemas and BSD license are retained in `tool/contracts/cloudflare/`. Run `python3 tool/cloudflare_contract.py --check` offline. Refresh with `--extract /path/to/official/openapi.json` only after reviewing the revision and upstream changes. New operations receive `not-integrated` status automatically.

See [Cloudflare usage](cloudflare.md) for auth, native model inputs, compatible protocols, cancellation and known limits.

## OpenAPI operations

| Method | Path | AgentWeave status |
| --- | --- | --- |
| GET | `/accounts/{account_id}/ai-gateway/billing/credit-balance` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/billing/invoice-history` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/billing/invoice-preview` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/billing/spending-limit` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/billing/spending-limit` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/billing/spending-limit` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/billing/topup` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/billing/topup/config` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/billing/topup/config` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/billing/topup/config` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/billing/topup/eligibility` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/billing/topup/limits` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/billing/topup/status` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/billing/usage-history` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/custom-providers` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/custom-providers` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/custom-providers/costs` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/custom-providers/costs` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/custom-providers/costs/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/custom-providers/costs/{id}` | not-integrated |
| PATCH | `/accounts/{account_id}/ai-gateway/custom-providers/costs/{id}` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/custom-providers/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/custom-providers/{id}` | not-integrated |
| PATCH | `/accounts/{account_id}/ai-gateway/custom-providers/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/evaluation-types` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/gateways` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/custom-domains` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/custom-domains` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/custom-domains/{hostname}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/custom-domains/{hostname}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/datasets` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/datasets` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/datasets/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/datasets/{id}` | not-integrated |
| PUT | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/datasets/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/evaluations` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/evaluations` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/evaluations/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/evaluations/{id}` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/logs` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/logs` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/logs/{id}` | not-integrated |
| PATCH | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/logs/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/logs/{id}/request` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/logs/{id}/response` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/provider_configs` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/provider_configs` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/provider_configs/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/provider_configs/{id}` | not-integrated |
| PUT | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/provider_configs/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/routes` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/routes` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/routes/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/routes/{id}` | not-integrated |
| PATCH | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/routes/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/routes/{id}/deployments` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/routes/{id}/deployments` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/routes/{id}/versions` | not-integrated |
| POST | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/routes/{id}/versions` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/routes/{id}/versions/{version_id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{gateway_id}/url/{provider}` | not-integrated |
| DELETE | `/accounts/{account_id}/ai-gateway/gateways/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/gateways/{id}` | not-integrated |
| PUT | `/accounts/{account_id}/ai-gateway/gateways/{id}` | not-integrated |
| GET | `/accounts/{account_id}/ai-gateway/logging-state` | not-integrated |
| PATCH | `/accounts/{account_id}/ai-gateway/logging-state` | not-integrated |
| GET | `/accounts/{account_id}/ai/authors/search` | not-integrated |
| GET | `/accounts/{account_id}/ai/finetunes` | not-integrated |
| POST | `/accounts/{account_id}/ai/finetunes` | not-integrated |
| GET | `/accounts/{account_id}/ai/finetunes/public` | not-integrated |
| DELETE | `/accounts/{account_id}/ai/finetunes/{finetune_id}` | not-integrated |
| POST | `/accounts/{account_id}/ai/finetunes/{finetune_id}/finetune-assets` | not-integrated |
| GET | `/accounts/{account_id}/ai/finetunes/{finetune_id}/finetune-assets/{file_name}` | not-integrated |
| GET | `/accounts/{account_id}/ai/models/schema` | integrated-selected-behavior |
| GET | `/accounts/{account_id}/ai/models/search` | integrated-selected-behavior |
| POST | `/accounts/{account_id}/ai/run` | integrated-selected-behavior |
| POST | `/accounts/{account_id}/ai/run/{model_name}` | integrated-selected-behavior |
| GET | `/accounts/{account_id}/ai/tasks/search` | not-integrated |
| POST | `/accounts/{account_id}/ai/tomarkdown` | not-integrated |
| GET | `/accounts/{account_id}/ai/tomarkdown/supported` | not-integrated |
| POST | `/accounts/{account_id}/ai/websearch` | not-integrated |

## Compatible endpoints outside this specification

The public [Gateway REST guide](https://developers.cloudflare.com/ai-gateway/usage/rest-api/) documents the following endpoints. Their request/response types are not in the pinned OpenAPI. Chat and Responses have separate offline continuation fixtures; Messages is not implemented. Model-specific feature availability still applies.

| Method | Path | AgentWeave status |
| --- | --- | --- |
| POST | `/accounts/{account_id}/ai/v1/chat/completions` | integrated-selected-behavior |
| POST | `/accounts/{account_id}/ai/v1/responses` | integrated-selected-behavior |
| POST | `/accounts/{account_id}/ai/v1/messages` | not-integrated |

## Selected public model schemas

The inventory retains the full input/output JSON schema for BGE base English, Whisper and Flux Schnell. Public documentation URLs are unversioned. Each downloaded snapshot has a SHA-256 hash; they are not attributed to the OpenAPI Git revision.

| Snapshot | Official source | SHA-256 |
| --- | --- | --- |
| `bge-input.json` | [Schema](https://developers.cloudflare.com/workers-ai/models/bge-base-en-v1.5/sync-input.json) | `0291aab34abe8e4657ead038aba73f37098ab8f94888e7d99e4791a4adfcb353` |
| `bge-output.json` | [Schema](https://developers.cloudflare.com/workers-ai/models/bge-base-en-v1.5/sync-output.json) | `4f25a95d82f8b25fb9f386fc35b1ee244fa7437a7fc75db7506aa66daa6d9541` |
| `whisper-input.json` | [Schema](https://developers.cloudflare.com/workers-ai/models/whisper/schema-input.json) | `e82ea39d3b7aef1058accc4e5a5c27c5817b30f16cd9c04a6cb6eded41edb944` |
| `whisper-output.json` | [Schema](https://developers.cloudflare.com/workers-ai/models/whisper/schema-output.json) | `d6f939cc1591e5f6176e1e0a7d64ac8b976d0c55d9fdba9b435d260c1710a2da` |
| `flux-input.json` | [Schema](https://developers.cloudflare.com/workers-ai/models/flux-1-schnell/schema-input.json) | `d17b781a278e8f00233de3c93b1ac73ed07ba609204674338749c1df38c16b17` |
| `flux-output.json` | [Schema](https://developers.cloudflare.com/workers-ai/models/flux-1-schnell/schema-output.json) | `5528a6a3b29dec4480fd67a9d695300ad5616c54372afb51988ee660c87a32c6` |

Whisper declares a binary-string input variant, but this schema does not establish an accepted REST Content-Type. The typed binary path has serialization tests only. Native `/run` model schemas vary; forwarding raw fields does not certify those models.

Model schemas, Gateway request headers, Workers bindings, asynchronous batch APIs and compatible endpoints require separate reviews when the OpenAPI omits them. No live Cloudflare calls were made for this inventory.
