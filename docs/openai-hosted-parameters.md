# OpenAI hosted tool inventory

Generated from the pinned [official Node SDK declarations](openai-hosted-inventory.json). See [the usage guide](openai-hosted.md) and [output references](output-references.md).

Selected hosted Responses, MCP and output-reference declarations, with executable hosted request fields; MCP uses provider-owned approval continuation and private replay. Credentials resolve separately at request time and require a stable binding identity; credential fields are excluded from executable configuration snapshots. Provider approval response echoes must match a trusted decision and do not create a new approval. This does not establish complete MCP protocol, model or live parity; not a claim of complete nested semantics, live behavior or endpoint parity. Four annotation forms have typed public reference projections. Native positions remain opaque, distinct from enclosing UTF-16 text segments. Scoped file handles are deliberately public references; unknown fields and native replay stay private. Completed image bytes become public ImagePart content. Partial images, precise native-coordinate highlights, hosted progress and downloaded container files remain open. External type references are retained, not expanded. Other tools, local executors and unselected declarations are excluded.

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

## McpToolCallError

Disposition: validated-private-mcp-replay

`McpToolCallError.McpProtocolError | McpToolCallError.McpToolExecutionError | McpToolCallError.HTTPError`

## McpToolCallError.McpProtocolError

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| code | `number` |
| message | `string` |
| type | `'mcp_protocol_error'` |

## McpToolCallError.McpToolExecutionError

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| content | `unknown` |
| type | `'mcp_tool_execution_error'` |

## McpToolCallError.HTTPError

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| code | `number` |
| message | `string` |
| type | `'http_error'` |

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

## ResponseContentPartAddedEvent

Disposition: private-replay

| Field | Source type |
| --- | --- |
| content_index | `number` |
| item_id | `string` |
| output_index | `number` |
| part | `ResponseOutputText \| ResponseOutputRefusal \| ResponseContentPartAddedEvent.ReasoningText` |
| sequence_number | `number` |
| type | `'response.content_part.added'` |

## ResponseContentPartAddedEvent.ReasoningText

Disposition: private-replay

| Field | Source type |
| --- | --- |
| text | `string` |
| type | `'reasoning_text'` |

## ResponseContentPartDoneEvent

Disposition: private-replay

| Field | Source type |
| --- | --- |
| content_index | `number` |
| item_id | `string` |
| output_index | `number` |
| part | `ResponseOutputText \| ResponseOutputRefusal \| ResponseContentPartDoneEvent.ReasoningText` |
| sequence_number | `number` |
| type | `'response.content_part.done'` |

## ResponseContentPartDoneEvent.ReasoningText

Disposition: private-replay

| Field | Source type |
| --- | --- |
| text | `string` |
| type | `'reasoning_text'` |

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

## ResponseInputItem.McpApprovalResponse

Disposition: integrated-private-approval-decision

| Field | Source type |
| --- | --- |
| approval_request_id | `string` |
| approve | `boolean` |
| type | `'mcp_approval_response'` |
| id? | `string \| null` |
| reason? | `string \| null` |

## ResponseMcpCallArgumentsDeltaEvent

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| delta | `string` |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.mcp_call_arguments.delta'` |

## ResponseMcpCallArgumentsDoneEvent

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| arguments | `string` |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.mcp_call_arguments.done'` |

## ResponseMcpCallCompletedEvent

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.mcp_call.completed'` |

## ResponseMcpCallFailedEvent

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.mcp_call.failed'` |

## ResponseMcpCallInProgressEvent

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.mcp_call.in_progress'` |

## ResponseMcpListToolsCompletedEvent

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.mcp_list_tools.completed'` |

## ResponseMcpListToolsFailedEvent

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.mcp_list_tools.failed'` |

## ResponseMcpListToolsInProgressEvent

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.mcp_list_tools.in_progress'` |

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

## ResponseOutputItem.McpCall

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| id | `string` |
| arguments | `string` |
| name | `string` |
| server_label | `string` |
| type | `'mcp_call'` |
| approval_request_id? | `string \| null` |
| error? | `ResponsesAPI.McpToolCallError \| null` |
| output? | `string \| null` |
| status? | `'in_progress' \| 'completed' \| 'incomplete' \| 'calling' \| 'failed'` |

## ResponseOutputItem.McpListTools

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| id | `string` |
| server_label | `string` |
| tools | `Array<McpListTools.Tool>` |
| type | `'mcp_list_tools'` |
| error? | `string \| null` |

## ResponseOutputItem.McpListTools.Tool

Disposition: validated-private-mcp-replay

| Field | Source type |
| --- | --- |
| input_schema | `unknown` |
| name | `string` |
| annotations? | `unknown \| null` |
| description? | `string \| null` |

## ResponseOutputItem.McpApprovalRequest

Disposition: integrated-provider-approval

| Field | Source type |
| --- | --- |
| id | `string` |
| arguments | `string` |
| name | `string` |
| server_label | `string` |
| type | `'mcp_approval_request'` |

## ResponseOutputItem.McpApprovalResponse

Disposition: validated-private-approval-echo

| Field | Source type |
| --- | --- |
| id | `string` |
| approval_request_id | `string` |
| approve | `boolean` |
| type | `'mcp_approval_response'` |
| reason? | `string \| null` |

## ResponseOutputMessage

Disposition: private-replay

| Field | Source type |
| --- | --- |
| id | `string` |
| content | `Array<ResponseOutputText \| ResponseOutputRefusal>` |
| role | `'assistant'` |
| status | `'in_progress' \| 'completed' \| 'incomplete'` |
| type | `'message'` |
| phase? | `'commentary' \| 'final_answer' \| null` |

## ResponseOutputText

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| annotations | `Array<ResponseOutputText.FileCitation \| ResponseOutputText.URLCitation \| ResponseOutputText.ContainerFileCitation \| ResponseOutputText.FilePath>` |
| text | `string` |
| type | `'output_text'` |
| logprobs? | `Array<ResponseOutputText.Logprob>` |

## ResponseOutputText.FileCitation

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| file_id | `string` |
| filename | `string` |
| index | `number` |
| type | `'file_citation'` |

## ResponseOutputText.URLCitation

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| end_index | `number` |
| start_index | `number` |
| title | `string` |
| type | `'url_citation'` |
| url | `string` |

## ResponseOutputText.ContainerFileCitation

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| container_id | `string` |
| end_index | `number` |
| file_id | `string` |
| filename | `string` |
| start_index | `number` |
| type | `'container_file_citation'` |

## ResponseOutputText.FilePath

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| file_id | `string` |
| index | `number` |
| type | `'file_path'` |

## ResponseOutputText.Logprob

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| token | `string` |
| bytes | `Array<number>` |
| logprob | `number` |
| top_logprobs | `Array<Logprob.TopLogprob>` |

## ResponseOutputText.Logprob.TopLogprob

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| token | `string` |
| bytes | `Array<number>` |
| logprob | `number` |

## ResponseOutputTextAnnotationAddedEvent

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| annotation | `ResponseOutputTextAnnotationAddedEvent.FileCitation \| ResponseOutputTextAnnotationAddedEvent.URLCitation \| ResponseOutputTextAnnotationAddedEvent.ContainerFileCitation \| ResponseOutputTextAnnotationAddedEvent.FilePath \| null` |
| annotation_index | `number` |
| content_index | `number` |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.output_text.annotation.added'` |

## ResponseOutputTextAnnotationAddedEvent.FileCitation

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| file_id | `string` |
| filename | `string` |
| index | `number` |
| type | `'file_citation'` |

## ResponseOutputTextAnnotationAddedEvent.URLCitation

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| end_index | `number` |
| start_index | `number` |
| title | `string` |
| type | `'url_citation'` |
| url | `string` |

## ResponseOutputTextAnnotationAddedEvent.ContainerFileCitation

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| container_id | `string` |
| end_index | `number` |
| file_id | `string` |
| filename | `string` |
| start_index | `number` |
| type | `'container_file_citation'` |

## ResponseOutputTextAnnotationAddedEvent.FilePath

Disposition: reviewed-reference-output

| Field | Source type |
| --- | --- |
| file_id | `string` |
| index | `number` |
| type | `'file_path'` |

## ResponseStreamEvent

Disposition: reviewed-stream-union

`ResponseAudioDeltaEvent | ResponseAudioDoneEvent | ResponseAudioTranscriptDeltaEvent | ResponseAudioTranscriptDoneEvent | ResponseCodeInterpreterCallCodeDeltaEvent | ResponseCodeInterpreterCallCodeDoneEvent | ResponseCodeInterpreterCallCompletedEvent | ResponseCodeInterpreterCallInProgressEvent | ResponseCodeInterpreterCallInterpretingEvent | ResponseCompactionCompactingEvent | ResponseCompletedEvent | ResponseContentPartAddedEvent | ResponseContentPartDoneEvent | ResponseCreatedEvent | ResponseErrorEvent | ResponseFileSearchCallCompletedEvent | ResponseFileSearchCallInProgressEvent | ResponseFileSearchCallSearchingEvent | ResponseFunctionCallArgumentsDeltaEvent | ResponseFunctionCallArgumentsDoneEvent | ResponseShellCallCommandAddedEvent | ResponseShellCallCommandDeltaEvent | ResponseShellCallCommandDoneEvent | ResponseShellCallOutputContentDeltaEvent | ResponseShellCallOutputContentDoneEvent | ResponseInProgressEvent | ResponseFailedEvent | ResponseIncompleteEvent | ResponseOutputItemAddedEvent | ResponseOutputItemDoneEvent | ResponseReasoningSummaryPartAddedEvent | ResponseReasoningSummaryPartDoneEvent | ResponseReasoningSummaryTextDeltaEvent | ResponseReasoningSummaryTextDoneEvent | ResponseReasoningTextDeltaEvent | ResponseReasoningTextDoneEvent | ResponseRefusalDeltaEvent | ResponseRefusalDoneEvent | ResponseTextDeltaEvent | ResponseTextDoneEvent | ResponseWebSearchCallCompletedEvent | ResponseWebSearchCallInProgressEvent | ResponseWebSearchCallSearchingEvent | ResponseImageGenCallCompletedEvent | ResponseImageGenCallGeneratingEvent | ResponseImageGenCallInProgressEvent | ResponseImageGenCallPartialImageEvent | ResponseMcpCallArgumentsDeltaEvent | ResponseMcpCallArgumentsDoneEvent | ResponseMcpCallCompletedEvent | ResponseMcpCallFailedEvent | ResponseMcpCallInProgressEvent | ResponseMcpListToolsCompletedEvent | ResponseMcpListToolsFailedEvent | ResponseMcpListToolsInProgressEvent | ResponseOutputTextAnnotationAddedEvent | ResponseQueuedEvent | ResponseCustomToolCallInputDeltaEvent | ResponseCustomToolCallInputDoneEvent`

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

## Tool.Mcp

Disposition: integrated-mcp-configuration

| Field | Source type |
| --- | --- |
| server_label | `string` |
| type | `'mcp'` |
| allowed_callers? | `Array<'direct' \| 'programmatic'> \| null` |
| allowed_tools? | `Array<string> \| Mcp.McpToolFilter \| null` |
| authorization? | `string` |
| connector_id? | `'connector_dropbox' \| 'connector_gmail' \| 'connector_googlecalendar' \| 'connector_googledrive' \| 'connector_microsoftteams' \| 'connector_outlookcalendar' \| 'connector_outlookemail' \| 'connector_sharepoint'` |
| defer_loading? | `boolean` |
| headers? | `{
    [key: string]: string;
} \| null` |
| require_approval? | `Mcp.McpToolApprovalFilter \| 'always' \| 'never' \| null` |
| server_description? | `string` |
| server_url? | `string` |
| tunnel_id? | `string` |

## Tool.Mcp.McpToolFilter

Disposition: integrated-mcp-configuration

| Field | Source type |
| --- | --- |
| read_only? | `boolean` |
| tool_names? | `Array<string>` |

## Tool.Mcp.McpToolApprovalFilter

Disposition: integrated-mcp-configuration

| Field | Source type |
| --- | --- |
| always? | `McpToolApprovalFilter.Always` |
| never? | `McpToolApprovalFilter.Never` |

## Tool.Mcp.McpToolApprovalFilter.Always

Disposition: integrated-mcp-configuration

| Field | Source type |
| --- | --- |
| read_only? | `boolean` |
| tool_names? | `Array<string>` |

## Tool.Mcp.McpToolApprovalFilter.Never

Disposition: integrated-mcp-configuration

| Field | Source type |
| --- | --- |
| read_only? | `boolean` |
| tool_names? | `Array<string>` |

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

## ChatCompletionMessage

Disposition: private-buffered-response

| Field | Source type |
| --- | --- |
| content | `string \| null` |
| refusal | `string \| null` |
| role | `'assistant'` |
| annotations? | `Array<ChatCompletionMessage.Annotation>` |
| audio? | `ChatCompletionAudio \| null` |
| function_call? | `ChatCompletionMessage.FunctionCall \| null` |
| tool_calls? | `Array<ChatCompletionMessageToolCall>` |

## ChatCompletionMessage.Annotation

Disposition: buffered-reference-output

| Field | Source type |
| --- | --- |
| type | `'url_citation'` |
| url_citation | `Annotation.URLCitation` |

## ChatCompletionMessage.Annotation.URLCitation

Disposition: buffered-reference-output

| Field | Source type |
| --- | --- |
| end_index | `number` |
| start_index | `number` |
| title | `string` |
| url | `string` |

## ChatCompletionMessage.FunctionCall

Disposition: private-buffered-response

| Field | Source type |
| --- | --- |
| arguments | `string` |
| name | `string` |
