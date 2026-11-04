# OpenRouter OpenAPI snapshot

`openapi.json` is the document downloaded from <https://openrouter.ai/openapi.json> on 2026-11-04, with credential-shaped example values redacted. Original-source SHA-256: `07b8b1ac91ba9e522540417420cd74004db5246d5341e5c86d68443e4438af82`. The document identifies its license as MIT; see `LICENSE`. Attribution: OpenRouter API, OpenRouter.

A separately published OpenAPI YAML is at [OpenRouter docs revision 4811fb090502bf3ed7e908a370dac1eeef011e9c](https://github.com/OpenRouterTeam/docs/blob/4811fb090502bf3ed7e908a370dac1eeef011e9c/openapi/openapi.yaml). It has not been verified byte-for-byte against this JSON. The separately published OpenRouter TypeScript SDK has its own Apache-2.0 license; that license is not the attribution for this snapshot.


The snapshot is serialized deterministically after replacing credential-shaped
example strings with `[OPENROUTER_API_KEY_REDACTED]`. Schema fields and constraints
are retained. The generated inventory records the separate snapshot hash. The
upstream checker verifies both the original source hash and deterministic
redaction; raw credential examples are never committed.
