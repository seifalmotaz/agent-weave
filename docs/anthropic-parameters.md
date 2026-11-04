# Anthropic Messages request fields

Generated from the [contract inventory](anthropic-api-inventory.json), pinned to official TypeScript SDK commit `ea8d7de0e47614ae71044fbf7bf12041318ba37e`. Run `node tool/interop/anthropic-inventory.mjs --write` after reviewing changes.

These dispositions describe top-level access only. Arbitrary native JSON does not validate nested unions or establish agent orchestration, model acceptance, or live behavior. The SDK adapter owns messages, execution bounds, system instructions and tools; its output schema is protected when supplied by the runtime.

| Field | Disposition | Access and limits |
| --- | --- | --- |
| max_tokens | runtime-owned | Built and protected by the agent adapter; native JSON accepts caller input. |
| messages | runtime-owned | Built and protected by the agent adapter; native JSON accepts caller input. |
| system | runtime-owned | Built and protected by the agent adapter; native JSON accepts caller input. |
| tools | runtime-owned | Runtime application tools and provider-model hostedTools are built and protected by the adapter. Selected pinned hosted blocks, approvals and paused continuation have offline fixtures; full nested semantics and live behavior remain unverified. |
| model | mixed | Adapter model constructor and SDK configure; native JSON accepts caller input. |
| output_config | mixed | SDK configure; runtime output schema is protected when requested. Native JSON accepts caller input. |
| stream | runtime-owned | Agent uses SDK streaming; native client controls the request mode. |
| user_profile_id | mixed | The adapter exposes a userProfileId header; native JSON accepts this body field separately. |
| cache_control | sdk-configure | Dart SDK 9.0.1 request configure; native JSON also accepts this field. Nested agent semantics are not established. |
| container | mixed | Initial configuration uses SDK/native JSON. Returned container IDs from message-start/delta are retained privately and reused across paused and local-tool continuations; inherited IDs are protected. Live expiry and files are unverified. |
| diagnostics | sdk-configure | Dart SDK 9.0.1 request configure; native JSON also accepts this field. Nested agent semantics are not established. |
| inference_geo | sdk-configure | Dart SDK 9.0.1 request configure; native JSON also accepts this field. Nested agent semantics are not established. |
| metadata | sdk-configure | Dart SDK 9.0.1 request configure; native JSON also accepts this field. Nested agent semantics are not established. |
| service_tier | sdk-configure | Dart SDK 9.0.1 request configure; native JSON also accepts this field. Nested agent semantics are not established. |
| speed | sdk-configure | Dart SDK 9.0.1 request configure; native JSON also accepts this field. Nested agent semantics are not established. |
| stop_sequences | sdk-configure | Dart SDK 9.0.1 request configure; native JSON also accepts this field. Nested agent semantics are not established. |
| thinking | sdk-configure | Dart SDK 9.0.1 request configure; native JSON also accepts this field. Nested agent semantics are not established. |
| tool_choice | sdk-configure | Dart SDK 9.0.1 request configure; native JSON also accepts this field. Nested agent semantics are not established. |
| workspace_id | native-json | Native JSON accepts this field; SDK configure support depends on the Dart SDK version. Agent semantics are not established. |

The inventory follows selected local type references for Messages requests, responses and stream events. Imported declarations and unrelated endpoints are outside its scope. Review protocol behavior and provider documentation separately.
