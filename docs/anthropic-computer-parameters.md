# Anthropic computer toolset contract

Generated from the [inventory](anthropic-computer-inventory.json), pinned to official TypeScript SDK commit `ea8d7de0e47614ae71044fbf7bf12041318ba37e`. Run `node tool/interop/anthropic-computer-inventory.mjs --write` after review. See the [computer use documentation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/computer-use-tool) and [SDK driver guidance](https://platform.claude.com/docs/en/agents-and-tools/tool-use/browser-use-sdk).

The 17 member calls use `toolset_name: computer`, the member name, and member-specific input with no action field. Dispatch by both names. Configs are sparse: each member defaults to enabled with defer_loading false. The toolset accepts cache_control. The documentation additionally permits allowed_callers with only ["direct"]; the pinned SDK declaration omits that field.

Run a batch sequentially. On failure, return an error for that action and for every subsequent unexecuted action, with the exact halt text in the inventory. Return one result for every call with its tool_use_id and toolset_name. Screenshot and zoom return an image; cursor_position returns coordinates as text. Coordinates always refer to the full screenshot, including after zoom.

The driver owns validation, coordinate conversion, image sizing, environment isolation and approval policy. Documentation specifies key repeat 1–100 (default 1), and hold_key and wait duration up to 300 seconds; the official driver guidance leaves these checks to applications. AgentWeave validates selected repeat and duration bounds before invoking the executor. These declarations and offline fixtures do not demonstrate model acceptance, desktop execution, or live behavior.
