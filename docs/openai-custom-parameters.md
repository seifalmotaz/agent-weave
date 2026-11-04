# OpenAI custom tool contract

Generated from the [pinned inventory](openai-custom-inventory.json). See the [official guide](https://developers.openai.com/api/docs/guides/function-calling).

Selected custom-tool declarations, four shallow union signatures and output-item event envelopes only; this is not full Responses union coverage or live workflow certification. Direct synchronous custom calls, text and grammar formats, custom-only namespaces and typed string/content results are implemented; namespaced function tools, asynchronous and programmatic calls are not integrated. Grammar syntax is provider-enforced; application callbacks validate their own input.

## responses.CustomTool

| Field | Type |
| --- | --- |
| name | `string` |
| type | `'custom'` |
| allowed_callers? | `Array<'direct' \| 'programmatic'> \| null` |
| async? | `boolean` |
| defer_loading? | `boolean` |
| description? | `string` |
| format? | `Shared.CustomToolInputFormat` |

## responses.ImageDetail

```ts
'low' | 'high' | 'auto' | 'original'
```

## responses.NamespaceTool

| Field | Type |
| --- | --- |
| description | `string` |
| name | `string` |
| tools | `Array<NamespaceTool.Function \| CustomTool>` |
| type | `'namespace'` |

## responses.NamespaceTool.Function

| Field | Type |
| --- | --- |
| name | `string` |
| type | `'function'` |
| allowed_callers? | `Array<'direct' \| 'programmatic'> \| null` |
| async? | `boolean` |
| defer_loading? | `boolean` |
| description? | `string \| null` |
| output_schema? | `{ [key: string]: unknown; } \| null` |
| parameters? | `unknown \| null` |
| strict? | `boolean \| null` |

## responses.ResponseCustomToolCall

| Field | Type |
| --- | --- |
| call_id | `string` |
| input | `string` |
| name | `string` |
| type | `'custom_tool_call'` |
| id? | `string` |
| async? | `boolean` |
| caller? | `ResponseCustomToolCall.Direct \| ResponseCustomToolCall.Program \| null` |
| namespace? | `string` |

## responses.ResponseCustomToolCall.Direct

| Field | Type |
| --- | --- |
| type | `'direct'` |

## responses.ResponseCustomToolCall.Program

| Field | Type |
| --- | --- |
| caller_id | `string` |
| type | `'program'` |

## responses.ResponseCustomToolCallInputDeltaEvent

| Field | Type |
| --- | --- |
| delta | `string` |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.custom_tool_call_input.delta'` |

## responses.ResponseCustomToolCallInputDoneEvent

| Field | Type |
| --- | --- |
| input | `string` |
| item_id | `string` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.custom_tool_call_input.done'` |

## responses.ResponseCustomToolCallItem

| Field | Type |
| --- | --- |
| id | `string` |
| status | `'in_progress' \| 'completed' \| 'incomplete'` |
| created_by? | `string` |

## responses.ResponseCustomToolCallOutput

| Field | Type |
| --- | --- |
| call_id | `string` |
| output | `string \| Array<ResponseInputText \| ResponseInputImage \| ResponseInputFile>` |
| type | `'custom_tool_call_output'` |
| id? | `string` |
| caller? | `ResponseCustomToolCallOutput.Direct \| ResponseCustomToolCallOutput.Program \| null` |

## responses.ResponseCustomToolCallOutput.Direct

| Field | Type |
| --- | --- |
| type | `'direct'` |

## responses.ResponseCustomToolCallOutput.Program

| Field | Type |
| --- | --- |
| caller_id | `string` |
| type | `'program'` |

## responses.ResponseCustomToolCallOutputItem

| Field | Type |
| --- | --- |
| id | `string` |
| status | `'in_progress' \| 'completed' \| 'incomplete'` |
| created_by? | `string` |

## responses.ResponseInputFile

| Field | Type |
| --- | --- |
| type | `'input_file'` |
| detail? | `'auto' \| 'low' \| 'high'` |
| file_data? | `string` |
| file_id? | `string \| null` |
| file_url? | `string` |
| filename? | `string` |
| prompt_cache_breakpoint? | `ResponseInputFile.PromptCacheBreakpoint` |

## responses.ResponseInputFile.PromptCacheBreakpoint

| Field | Type |
| --- | --- |
| mode | `'explicit'` |
| ttl? | `'30m' \| '12h'` |

## responses.ResponseInputImage

| Field | Type |
| --- | --- |
| detail | `ImageDetail` |
| type | `'input_image'` |
| file_id? | `string \| null` |
| image_url? | `string \| null` |
| prompt_cache_breakpoint? | `ResponseInputImage.PromptCacheBreakpoint` |

## responses.ResponseInputImage.PromptCacheBreakpoint

| Field | Type |
| --- | --- |
| mode | `'explicit'` |
| ttl? | `'30m' \| '12h'` |

## responses.ResponseInputText

| Field | Type |
| --- | --- |
| text | `string` |
| type | `'input_text'` |
| prompt_cache_breakpoint? | `ResponseInputText.PromptCacheBreakpoint` |

## responses.ResponseInputText.PromptCacheBreakpoint

| Field | Type |
| --- | --- |
| mode | `'explicit'` |
| ttl? | `'30m' \| '12h'` |

## responses.ResponseOutputItemAddedEvent

| Field | Type |
| --- | --- |
| item | `ResponseOutputItem` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.output_item.added'` |

## responses.ResponseOutputItemDoneEvent

| Field | Type |
| --- | --- |
| item | `ResponseOutputItem` |
| output_index | `number` |
| sequence_number | `number` |
| type | `'response.output_item.done'` |

## responses.ToolChoiceAllowed

| Field | Type |
| --- | --- |
| mode | `'auto' \| 'required'` |
| tools | `Array<{ [key: string]: unknown; }>` |
| type | `'allowed_tools'` |

## responses.ToolChoiceCustom

| Field | Type |
| --- | --- |
| name | `string` |
| type | `'custom'` |

## responses.Tool

Shallow union signature; variants are not all integrated.

```ts
FunctionTool
  | FileSearchTool
  | ComputerTool
  | ComputerUsePreviewTool
  | WebSearchTool
  | Tool.Mcp
  | Tool.CodeInterpreter
  | Tool.ProgrammaticToolCalling
  | Tool.ImageGeneration
  | Tool.LocalShell
  | FunctionShellTool
  | CustomTool
  | NamespaceTool
  | ToolSearchTool
  | WebSearchPreviewTool
  | ApplyPatchTool
```

## responses.ResponseInputItem

Shallow union signature; variants are not all integrated.

```ts
EasyInputMessage
  | ResponseInputItem.Message
  | ResponseOutputMessage
  | ResponseFileSearchToolCall
  | ResponseComputerToolCall
  | ResponseInputItem.ComputerCallOutput
  | ResponseFunctionWebSearch
  | ResponseFunctionToolCall
  | ResponseInputItem.FunctionCallOutput
  | ResponseInputItem.ToolSearchCall
  | ResponseToolSearchOutputItemParam
  | ResponseInputItem.AdditionalTools
  | ResponseConfigurationUpdateItemParam
  | ResponseReasoningItem
  | ResponseCompactionItemParam
  | ResponseInputItem.ImageGenerationCall
  | ResponseCodeInterpreterToolCall
  | ResponseInputItem.LocalShellCall
  | ResponseInputItem.LocalShellCallOutput
  | ResponseInputItem.ShellCall
  | ResponseInputItem.ShellCallOutput
  | ResponseInputItem.ApplyPatchCall
  | ResponseInputItem.ApplyPatchCallOutput
  | ResponseInputItem.McpListTools
  | ResponseInputItem.McpApprovalRequest
  | ResponseInputItem.McpApprovalResponse
  | ResponseInputItem.McpCall
  | ResponseCustomToolCallOutput
  | ResponseCustomToolCall
  | ResponseInputItem.CompactionTrigger
  | ResponseInputItem.ItemReference
  | ResponseInputItem.Program
  | ResponseInputItem.ProgramOutput
```

## responses.ResponseOutputItem

Shallow union signature; variants are not all integrated.

```ts
ResponseOutputMessage
  | ResponseFileSearchToolCall
  | ResponseFunctionToolCall
  | ResponseFunctionToolCallOutputItem
  | ResponseFunctionWebSearch
  | ResponseComputerToolCall
  | ResponseComputerToolCallOutputItem
  | ResponseReasoningItem
  | ResponseOutputItem.Program
  | ResponseOutputItem.ProgramOutput
  | ResponseToolSearchCall
  | ResponseToolSearchOutputItem
  | ResponseOutputItem.AdditionalTools
  | ResponseCompactionItem
  | ResponseOutputItem.ImageGenerationCall
  | ResponseCodeInterpreterToolCall
  | ResponseOutputItem.LocalShellCall
  | ResponseOutputItem.LocalShellCallOutput
  | ResponseFunctionShellToolCall
  | ResponseFunctionShellToolCallOutput
  | ResponseApplyPatchToolCall
  | ResponseApplyPatchToolCallOutput
  | ResponseOutputItem.McpCall
  | ResponseOutputItem.McpListTools
  | ResponseOutputItem.McpApprovalRequest
  | ResponseOutputItem.McpApprovalResponse
  | ResponseCustomToolCall
  | ResponseCustomToolCallOutputItem
```

## responses.ResponseStreamEvent

Shallow union signature; variants are not all integrated.

```ts
ResponseAudioDeltaEvent
  | ResponseAudioDoneEvent
  | ResponseAudioTranscriptDeltaEvent
  | ResponseAudioTranscriptDoneEvent
  | ResponseCodeInterpreterCallCodeDeltaEvent
  | ResponseCodeInterpreterCallCodeDoneEvent
  | ResponseCodeInterpreterCallCompletedEvent
  | ResponseCodeInterpreterCallInProgressEvent
  | ResponseCodeInterpreterCallInterpretingEvent
  | ResponseCompactionCompactingEvent
  | ResponseCompletedEvent
  | ResponseContentPartAddedEvent
  | ResponseContentPartDoneEvent
  | ResponseCreatedEvent
  | ResponseErrorEvent
  | ResponseFileSearchCallCompletedEvent
  | ResponseFileSearchCallInProgressEvent
  | ResponseFileSearchCallSearchingEvent
  | ResponseFunctionCallArgumentsDeltaEvent
  | ResponseFunctionCallArgumentsDoneEvent
  | ResponseShellCallCommandAddedEvent
  | ResponseShellCallCommandDeltaEvent
  | ResponseShellCallCommandDoneEvent
  | ResponseShellCallOutputContentDeltaEvent
  | ResponseShellCallOutputContentDoneEvent
  | ResponseInProgressEvent
  | ResponseFailedEvent
  | ResponseIncompleteEvent
  | ResponseOutputItemAddedEvent
  | ResponseOutputItemDoneEvent
  | ResponseReasoningSummaryPartAddedEvent
  | ResponseReasoningSummaryPartDoneEvent
  | ResponseReasoningSummaryTextDeltaEvent
  | ResponseReasoningSummaryTextDoneEvent
  | ResponseReasoningTextDeltaEvent
  | ResponseReasoningTextDoneEvent
  | ResponseRefusalDeltaEvent
  | ResponseRefusalDoneEvent
  | ResponseTextDeltaEvent
  | ResponseTextDoneEvent
  | ResponseWebSearchCallCompletedEvent
  | ResponseWebSearchCallInProgressEvent
  | ResponseWebSearchCallSearchingEvent
  | ResponseImageGenCallCompletedEvent
  | ResponseImageGenCallGeneratingEvent
  | ResponseImageGenCallInProgressEvent
  | ResponseImageGenCallPartialImageEvent
  | ResponseMcpCallArgumentsDeltaEvent
  | ResponseMcpCallArgumentsDoneEvent
  | ResponseMcpCallCompletedEvent
  | ResponseMcpCallFailedEvent
  | ResponseMcpCallInProgressEvent
  | ResponseMcpListToolsCompletedEvent
  | ResponseMcpListToolsFailedEvent
  | ResponseMcpListToolsInProgressEvent
  | ResponseOutputTextAnnotationAddedEvent
  | ResponseQueuedEvent
  | ResponseCustomToolCallInputDeltaEvent
  | ResponseCustomToolCallInputDoneEvent
```

## shared.CustomToolInputFormat

```ts
CustomToolInputFormat.Text | CustomToolInputFormat.Grammar
```

## shared.CustomToolInputFormat.Text

| Field | Type |
| --- | --- |
| type | `'text'` |

## shared.CustomToolInputFormat.Grammar

| Field | Type |
| --- | --- |
| definition | `string` |
| syntax | `'lark' \| 'regex'` |
| type | `'grammar'` |
