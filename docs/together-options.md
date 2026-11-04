# Together chat request fields

Generated from the reviewed [contract inventory](together-chat-inventory.json) at
Together SDK commit `488006d90b67d589034d8323a11cfab9b588abca`. Do not edit this table by hand;
review the source pin and run `node tool/interop/inventory.mjs --write`.

The agent adapter owns conversation history, tools, schema and execution bounds.
Use the native JSON client where indicated. A field disposition does not prove
nested semantics, model acceptance, or coverage of other endpoints. See the
[Together guide](together.md) for complete setup, errors and known limits.

| Wire field | Dart entry point or runtime behavior | Disposition |
| --- | --- | --- |
| messages | ModelRequest.messages and instructions | runtime-owned |
| model | TogetherChatModel.model | runtime-owned |
| chat_template_kwargs | TogetherChatOptions.chatTemplateKwargs | typed-option |
| compliance | TogetherChatOptions.compliance | typed-option |
| context_length_exceeded_behavior | TogetherChatOptions.contextLengthExceededBehavior | typed-option |
| echo | TogetherChatOptions.echo | typed-option |
| frequency_penalty | TogetherChatOptions.frequencyPenalty | typed-option |
| function_call | TogetherClient.createChat/streamChat | native-only |
| logit_bias | TogetherChatOptions.logitBias | typed-option |
| logprobs | TogetherChatOptions.logprobs | typed-option |
| max_tokens | ModelRequest.maxOutputTokens | runtime-owned |
| min_p | TogetherChatOptions.minP | typed-option |
| n | fixed to one completion in the agent adapter | runtime-owned |
| presence_penalty | TogetherChatOptions.presencePenalty | typed-option |
| reasoning | TogetherChatOptions.reasoningEnabled | typed-option |
| reasoning_effort | TogetherChatOptions.reasoningEffort | typed-option |
| repetition_penalty | TogetherChatOptions.repetitionPenalty | typed-option |
| response_format | ModelRequest.outputSchema | runtime-owned |
| safety_model | TogetherChatOptions.safetyModel | typed-option |
| seed | TogetherChatOptions.seed | typed-option |
| stop | TogetherChatOptions.stop | typed-option |
| stream | fixed to true in the agent adapter | runtime-owned |
| temperature | TogetherChatOptions.temperature | typed-option |
| tool_choice | TogetherChatOptions.toolChoice | typed-option |
| tools | registered ModelTool definitions | runtime-owned |
| top_k | TogetherChatOptions.topK | typed-option |
| top_p | TogetherChatOptions.topP | typed-option |

The native client accepts arbitrary JSON fields; it does not statically validate
the whole provider API. Typed options cover common agent requests. Native response
metadata is available from raw methods; not all fields are normalized by the agent.
