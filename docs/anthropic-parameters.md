# Anthropic Messages request fields

Generated from the [contract inventory](anthropic-api-inventory.json), pinned to official TypeScript SDK commit `ea8d7de0e47614ae71044fbf7bf12041318ba37e`. Run `node tool/interop/anthropic-inventory.mjs --write` after reviewing changes.

These dispositions describe top-level access only. Arbitrary native JSON does not validate nested unions or establish agent orchestration, model acceptance, or live behavior. The SDK adapter owns messages, execution bounds, system instructions and tools; its output schema is protected when supplied by the runtime.

| Field | Disposition | Access and limits |
| --- | --- | --- |
| max_tokens | runtime-owned | Built and protected by the agent adapter; native JSON accepts caller input. |
| messages | runtime-owned | Runtime-owned history, source and title; native document context/cache/citations decorations are supported. Five pinned citation variants have typed output and private replay with offline fixtures. Custom-content documents, search-result inputs and live behavior remain unverified. |
| system | runtime-owned | Built and protected by the agent adapter; native JSON accepts caller input. |
| tools | runtime-owned | Runtime local tools and owned hosted/MCP declarations are protected. Managed models use frozen function options and provider authority. The separate beta MCP inventory covers server/toolsets and native use/result/listing replay; live and full nested semantics remain unverified. |
| model | runtime-owned | Immutable adapter model constructor; configure cannot replace it. Explicit raw-native JSON remains caller-owned. |
| output_config | mixed | SDK configure; runtime output schema is protected when requested. Native JSON accepts caller input. |
| stream | runtime-owned | Agent uses SDK streaming; native client controls the request mode. |
| user_profile_id | mixed | The adapter exposes a userProfileId header; native JSON accepts this body field separately. |
| cache_control | mixed | Immutable agent options, or typed/native configure for models without managed tools; explicit raw JSON also accepts the field. Forwarding does not prove full nested or live semantics. |
| container | mixed | Explicit immutable initial container ID/object, including skills. Returned IDs are retained privately, take precedence and remain protected across paused and local-tool continuation. Live expiry/files remain unverified. |
| diagnostics | mixed | Immutable agent options, or typed/native configure for models without managed tools; explicit raw JSON also accepts the field. Forwarding does not prove full nested or live semantics. |
| inference_geo | mixed | Immutable agent options, or typed/native configure for models without managed tools; explicit raw JSON also accepts the field. Forwarding does not prove full nested or live semantics. |
| metadata | mixed | Immutable agent options, or typed/native configure for models without managed tools; explicit raw JSON also accepts the field. Forwarding does not prove full nested or live semantics. |
| service_tier | mixed | Immutable agent options, or typed/native configure for models without managed tools; explicit raw JSON also accepts the field. Forwarding does not prove full nested or live semantics. |
| speed | mixed | Immutable agent options, or typed/native configure for models without managed tools; explicit raw JSON also accepts the field. Forwarding does not prove full nested or live semantics. |
| stop_sequences | mixed | Immutable agent options, or typed/native configure for models without managed tools; explicit raw JSON also accepts the field. Forwarding does not prove full nested or live semantics. |
| thinking | mixed | Immutable agent options, or typed/native configure for models without managed tools; explicit raw JSON also accepts the field. Forwarding does not prove full nested or live semantics. |
| tool_choice | mixed | Immutable agent options, or typed/native configure for models without managed tools; explicit raw JSON also accepts the field. Forwarding does not prove full nested or live semantics. |
| workspace_id | native-json | Native JSON accepts this field; SDK configure support depends on the Dart SDK version. Agent semantics are not established. |

The inventory follows selected local type references for Messages requests, responses and stream events. Imported declarations and unrelated endpoints are outside its scope. Review protocol behavior and provider documentation separately.
