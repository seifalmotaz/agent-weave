# OpenRouter OpenAPI snapshot

`openapi.json` is the document downloaded from <https://openrouter.ai/openapi.json> on 2026-11-04, with credential-shaped example values redacted. Original-source SHA-256: `08855d8f74f3f44be3b3007576d79aee13faa6ecf6fd5cd790fcd78b51e6a4fb`. The document identifies its license as MIT; see `LICENSE`. Attribution: OpenRouter API, OpenRouter.

A separately published OpenAPI YAML is at [OpenRouter docs revision 4811fb090502bf3ed7e908a370dac1eeef011e9c](https://github.com/OpenRouterTeam/docs/blob/4811fb090502bf3ed7e908a370dac1eeef011e9c/openapi/openapi.yaml). It has not been verified byte-for-byte against this JSON. The separately published OpenRouter TypeScript SDK has its own Apache-2.0 license; that license is not the attribution for this snapshot.


The snapshot is serialized deterministically after replacing credential-shaped
example strings with `[OPENROUTER_API_KEY_REDACTED]`. Schema fields and constraints
are retained. The generated inventory records the separate snapshot hash. The
upstream checker verifies both the original source hash and deterministic
redaction; raw credential examples are never committed.

## Reviewed update on 2026-11-04

The current pin has 144 operations across 106 paths. Compared with the previous
snapshot, it removes the unintegrated PUT operations
`/private-endpoints/{id}/parameters` and `/private-endpoints/{id}/pricing`.
The five selected Chat, Responses and Image API operation definitions are
unchanged. Reachable schemas add the Parallel provider/options object, nullable
Responses result fields and double format hints on image capability ranges.
`current_contract_test.dart` verifies those selected changes through the public
Dart API. No native image generation request or event member changed.

Other reviewed changes affect unintegrated private endpoints, provider enum
values, generation API types, nullable model defaults, offset metadata and SDK
naming. Recording their source does not implement those operations. Raw source
bytes were checked before redaction; example credentials remain redacted in the
committed snapshot. Live provider acceptance is unverified.
