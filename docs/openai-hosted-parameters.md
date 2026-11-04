# OpenAI hosted tool inventory

Generated from the pinned [official Node SDK declarations](openai-hosted-inventory.json). See [the usage guide](openai-hosted.md).

Selected hosted Responses declarations and executable request fields only; not a claim of nested semantics, live model behavior, or endpoint parity. Only completed image result bytes become public ImagePart content; other image metadata stays private. Partial images, public citations, hosted progress and downloaded container files are not normalized. External type references are retained, not expanded. Other tools, local executors, and unselected declarations are excluded.

## FileSearchTool

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| type | `'file_search'` |
| vector_store_ids | `Array<string>` |
| filters? | `Shared.ComparisonFilter \| Shared.CompoundFilter \| null` |
| max_num_results? | `number` |
| ranking_options? | `FileSearchTool.RankingOptions` |

## FileSearchTool.RankingOptions

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| hybrid_search? | `RankingOptions.HybridSearch` |
| ranker? | `'auto' \| 'default-2024-11-15'` |
| score_threshold? | `number` |

## FileSearchTool.RankingOptions.HybridSearch

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| embedding_weight | `number` |
| text_weight | `number` |

## ResponseCodeInterpreterToolCall

Disposition: private-replay

| Field | Source type |
| --- | --- |
| id | `string` |
| code | `string \| null` |
| container_id | `string` |
| outputs | `Array<ResponseCodeInterpreterToolCall.Logs \| ResponseCodeInterpreterToolCall.Image> \| null` |
| status | `'in_progress' \| 'completed' \| 'incomplete' \| 'interpreting' \| 'failed'` |
| type | `'code_interpreter_call'` |

## ResponseCodeInterpreterToolCall.Logs

Disposition: private-replay

| Field | Source type |
| --- | --- |
| logs | `string` |
| type | `'logs'` |

## ResponseCodeInterpreterToolCall.Image

Disposition: private-replay

| Field | Source type |
| --- | --- |
| type | `'image'` |
| url | `string` |

## ResponseFileSearchToolCall

Disposition: private-replay

| Field | Source type |
| --- | --- |
| id | `string` |
| queries | `Array<string>` |
| status | `'in_progress' \| 'searching' \| 'completed' \| 'incomplete' \| 'failed'` |
| type | `'file_search_call'` |
| results? | `Array<ResponseFileSearchToolCall.Result> \| null` |

## ResponseFileSearchToolCall.Result

Disposition: private-replay

| Field | Source type |
| --- | --- |
| attributes? | `{
    [key: string]: string \| number \| boolean;
} \| null` |
| file_id? | `string` |
| filename? | `string` |
| score? | `number` |
| text? | `string` |

## ResponseFunctionWebSearch

Disposition: private-replay

| Field | Source type |
| --- | --- |
| id | `string` |
| action | `ResponseFunctionWebSearch.Search \| ResponseFunctionWebSearch.OpenPage \| ResponseFunctionWebSearch.Find` |
| status | `'in_progress' \| 'searching' \| 'completed' \| 'failed' \| 'incomplete'` |
| type | `'web_search_call'` |

## ResponseFunctionWebSearch.Search

Disposition: private-replay

| Field | Source type |
| --- | --- |
| type | `'search'` |
| queries? | `Array<string>` |
| query? | `string` |
| sources? | `Array<Search.Source>` |

## ResponseFunctionWebSearch.Search.Source

Disposition: private-replay

| Field | Source type |
| --- | --- |
| type | `'url'` |
| url | `string` |

## ResponseFunctionWebSearch.OpenPage

Disposition: private-replay

| Field | Source type |
| --- | --- |
| type | `'open_page'` |
| url? | `string \| null` |

## ResponseFunctionWebSearch.Find

Disposition: private-replay

| Field | Source type |
| --- | --- |
| pattern | `string` |
| type | `'find_in_page'` |
| url | `string` |

## ResponseOutputItem.ImageGenerationCall

Disposition: private-replay

| Field | Source type |
| --- | --- |
| id | `string` |
| result | `string \| null` |
| status | `'in_progress' \| 'completed' \| 'generating' \| 'failed'` |
| type | `'image_generation_call'` |
| action? | `'generate' \| 'edit' \| 'auto' \| null` |
| background? | `'transparent' \| 'opaque' \| 'auto' \| null` |
| error? | `ImageGenerationCall.Error` |
| output_format? | `'png' \| 'webp' \| 'jpeg' \| null` |
| quality? | `'low' \| 'medium' \| 'high' \| 'xhigh' \| 'max' \| 'auto' \| null` |
| revised_prompt? | `string \| null` |
| size? | `(string & {}) \| '1024x1024' \| '1024x1536' \| '1536x1024' \| null` |

## ResponseOutputItem.ImageGenerationCall.Error

Disposition: private-replay

| Field | Source type |
| --- | --- |
| code | `string \| null` |
| message | `string` |
| param | `string \| null` |
| type | `string` |
| moderation_details? | `Error.ModerationDetails` |

## ResponseOutputItem.ImageGenerationCall.Error.ModerationDetails

Disposition: private-replay

| Field | Source type |
| --- | --- |
| categories | `Array<string>` |
| moderation_stage | `'input' \| 'output' \| 'unknown'` |

## ResponseToolSearchCall

Disposition: private-replay

| Field | Source type |
| --- | --- |
| id | `string` |
| arguments | `unknown` |
| call_id | `string \| null` |
| execution | `'server' \| 'client'` |
| status | `'in_progress' \| 'completed' \| 'incomplete'` |
| type | `'tool_search_call'` |
| created_by? | `string` |

## ResponseToolSearchOutputItem

Disposition: private-replay

| Field | Source type |
| --- | --- |
| id | `string` |
| call_id | `string \| null` |
| execution | `'server' \| 'client'` |
| status | `'in_progress' \| 'completed' \| 'incomplete'` |
| tools | `Array<Tool>` |
| type | `'tool_search_output'` |
| created_by? | `string` |

## Tool.CodeInterpreter

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| container | `string \| CodeInterpreter.CodeInterpreterToolAuto` |
| type | `'code_interpreter'` |
| allowed_callers? | `Array<'direct' \| 'programmatic'> \| null` |

## Tool.CodeInterpreter.CodeInterpreterToolAuto

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| type | `'auto'` |
| file_ids? | `Array<string>` |
| memory_limit? | `'1g' \| '4g' \| '16g' \| '64g' \| null` |
| network_policy? | `ResponsesAPI.ContainerNetworkPolicyDisabled \| ResponsesAPI.ContainerNetworkPolicyAllowlist` |

## Tool.ImageGeneration

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| type | `'image_generation'` |
| action? | `'generate' \| 'edit' \| 'auto'` |
| background? | `'transparent' \| 'opaque' \| 'auto'` |
| input_fidelity? | `'high' \| 'low' \| null` |
| input_image_mask? | `ImageGeneration.InputImageMask` |
| model? | `(string & {}) \| 'gpt-image-1' \| 'gpt-image-1-mini' \| 'gpt-image-2' \| 'gpt-image-2-2026-04-21' \| 'gpt-image-2.5-sunburst' \| 'gpt-image-2.5-sunburst-2026-09-08' \| 'gpt-image-2.5-flare' \| 'gpt-image-2.5-flare-2026-09-08' \| 'gpt-image-1.5' \| 'chatgpt-image-latest'` |
| moderation? | `'auto' \| 'low'` |
| output_compression? | `number` |
| output_format? | `'png' \| 'webp' \| 'jpeg'` |
| partial_images? | `number` |
| quality? | `'low' \| 'medium' \| 'high' \| 'xhigh' \| 'max' \| 'auto'` |
| size? | `(string & {}) \| '1024x1024' \| '1024x1536' \| '1536x1024' \| 'auto'` |

## Tool.ImageGeneration.InputImageMask

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| file_id? | `string` |
| image_url? | `string` |

## ToolSearchTool

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| type | `'tool_search'` |
| description? | `string \| null` |
| execution? | `'server' \| 'client'` |
| parameters? | `unknown \| null` |

## WebSearchPreviewTool

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| type | `'web_search_preview' \| 'web_search_preview_2025_03_11'` |
| search_content_types? | `Array<'text' \| 'image'>` |
| search_context_size? | `'low' \| 'medium' \| 'high'` |
| user_location? | `WebSearchPreviewTool.UserLocation \| null` |

## WebSearchPreviewTool.UserLocation

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| type | `'approximate'` |
| city? | `string \| null` |
| country? | `string \| null` |
| region? | `string \| null` |
| timezone? | `string \| null` |

## WebSearchTool

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| type | `'web_search' \| 'web_search_2025_08_26'` |
| external_web_access? | `boolean` |
| filters? | `WebSearchTool.Filters \| null` |
| search_context_size? | `'low' \| 'medium' \| 'high'` |
| user_location? | `WebSearchTool.UserLocation \| null` |

## WebSearchTool.Filters

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| allowed_domains? | `Array<string> \| null` |

## WebSearchTool.UserLocation

Disposition: raw-native-options

| Field | Source type |
| --- | --- |
| city? | `string \| null` |
| country? | `string \| null` |
| region? | `string \| null` |
| timezone? | `string \| null` |
| type? | `'approximate'` |
