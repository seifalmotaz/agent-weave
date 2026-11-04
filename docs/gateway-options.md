# Gateway option reference

Generated from Vercel's SDK commit `6adf8c797d5e2bf056c077f946aa12dabb3cb268`. This is an
option inventory, not a certificate of public endpoint behavior. Read the
[Gateway guide](vercel-gateway.md) for setup and limits.

| Wire option | Dart entry point | Disposition |
| --- | --- | --- |
| byok | GatewayCredentials.byok via credentialResolver | request-credentials |
| caching | GatewayOptions.caching | typed-option |
| experimental_streamingImageDecoding | Not sent; image decoding is outside Chat/Responses | sdk-client-only |
| disallowPromptTraining | GatewayOptions.disallowPromptTraining | typed-option |
| has | GatewayOptions.has | typed-option |
| idempotencyKey | GatewayOptions.extra; no batch lifecycle implementation | native-extension |
| models | GatewayOptions.models; string fallbacks only | typed-option |
| only | GatewayOptions.only | typed-option |
| order | GatewayOptions.order | typed-option |
| providerTimeouts | GatewayOptions.byokProviderTimeouts | typed-option |
| quotaEntityId | GatewayOptions.quotaEntityId | typed-option |
| serviceTier | GatewayOptions.serviceTier | typed-option |
| sort | GatewayOptions.sort | typed-option |
| tags | GatewayOptions.tags | typed-option |
| user | GatewayOptions.user | typed-option |
| zeroDataRetention | GatewayOptions.zeroDataRetention | typed-option |

The public Chat and Responses extension uses `providerOptions.gateway`.
BYOK credentials are resolved per request and are excluded from ordinary option
serialization. Unknown service-owned options can use `GatewayOptions.extra`;
that does not prove their endpoint applicability. Conditional decision fallbacks
and the SDK's image decoder are outside these adapters.

See the [machine-readable inventory](gateway-options-inventory.json). Do not
edit this generated page by hand; review the pin and run
`node tool/interop/gateway-inventory.mjs --write`.
