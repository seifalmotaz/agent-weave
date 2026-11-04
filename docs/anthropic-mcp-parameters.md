# Anthropic MCP Messages contract

Generated from the [pinned inventory](anthropic-mcp-inventory.json). See the [official connector guide](https://platform.claude.com/docs/en/agents-and-tools/mcp-connector).

Selected MCP Messages declarations and recursively referenced local types. The Dart fixture exercises owned configuration and credential separation, not SSE normalization, provider acceptance or live execution. MCP result content in this pinned contract is string or an array of text blocks; private replay and continuation are tested separately.

- `mcp-client-2025-04-04`: Deprecated legacy server tool_configuration; provider availability is not established.
- `mcp-client-2025-11-20`: Modern matching server and toolset; supported cloud platforms vary.
- `mcp-client-2026-09-15`: Claude API listing and pinned tool descriptors; replay listings with this beta.

## BetaCacheControlEphemeral

| Field | Source type |
| --- | --- |
| type | `'ephemeral'` |
| ttl? | `'5m' \| '1h'` |

## BetaCitationCharLocation

| Field | Source type |
| --- | --- |
| cited_text | `string` |
| document_index | `number` |
| document_title | `string \| null` |
| end_char_index | `number` |
| file_id | `string \| null` |
| start_char_index | `number` |
| type | `'char_location'` |

## BetaCitationCharLocationParam

| Field | Source type |
| --- | --- |
| cited_text | `string` |
| document_index | `number` |
| document_title | `string \| null` |
| end_char_index | `number` |
| start_char_index | `number` |
| type | `'char_location'` |

## BetaCitationContentBlockLocation

| Field | Source type |
| --- | --- |
| cited_text | `string` |
| document_index | `number` |
| document_title | `string \| null` |
| end_block_index | `number` |
| file_id | `string \| null` |
| start_block_index | `number` |
| type | `'content_block_location'` |

## BetaCitationContentBlockLocationParam

| Field | Source type |
| --- | --- |
| cited_text | `string` |
| document_index | `number` |
| document_title | `string \| null` |
| end_block_index | `number` |
| start_block_index | `number` |
| type | `'content_block_location'` |

## BetaCitationPageLocation

| Field | Source type |
| --- | --- |
| cited_text | `string` |
| document_index | `number` |
| document_title | `string \| null` |
| end_page_number | `number` |
| file_id | `string \| null` |
| start_page_number | `number` |
| type | `'page_location'` |

## BetaCitationPageLocationParam

| Field | Source type |
| --- | --- |
| cited_text | `string` |
| document_index | `number` |
| document_title | `string \| null` |
| end_page_number | `number` |
| start_page_number | `number` |
| type | `'page_location'` |

## BetaCitationSearchResultLocation

| Field | Source type |
| --- | --- |
| cited_text | `string` |
| end_block_index | `number` |
| search_result_index | `number` |
| source | `string` |
| start_block_index | `number` |
| title | `string \| null` |
| type | `'search_result_location'` |

## BetaCitationSearchResultLocationParam

| Field | Source type |
| --- | --- |
| cited_text | `string` |
| end_block_index | `number` |
| search_result_index | `number` |
| source | `string` |
| start_block_index | `number` |
| title | `string \| null` |
| type | `'search_result_location'` |

## BetaCitationsWebSearchResultLocation

| Field | Source type |
| --- | --- |
| cited_text | `string` |
| encrypted_index | `string` |
| title | `string \| null` |
| type | `'web_search_result_location'` |
| url | `string` |

## BetaCitationWebSearchResultLocationParam

| Field | Source type |
| --- | --- |
| cited_text | `string` |
| encrypted_index | `string` |
| title | `string \| null` |
| type | `'web_search_result_location'` |
| url | `string` |

## BetaMCPTool

| Field | Source type |
| --- | --- |
| input_schema | `{
    [key: string]: unknown;
}` |
| name | `string` |
| description? | `string` |

## BetaMCPToolConfig

| Field | Source type |
| --- | --- |
| defer_loading? | `boolean` |
| enabled? | `boolean` |

## BetaMCPToolDefaultConfig

| Field | Source type |
| --- | --- |
| defer_loading? | `boolean` |
| enabled? | `boolean` |

## BetaMCPToolListingBlock

| Field | Source type |
| --- | --- |
| mcp_server_name | `string` |
| tools | `Array<BetaMCPTool>` |
| type | `'mcp_tool_listing'` |

## BetaMCPToolListingBlockParam

| Field | Source type |
| --- | --- |
| mcp_server_name | `string` |
| tools | `Array<BetaMCPToolParam>` |
| type | `'mcp_tool_listing'` |

## BetaMCPToolParam

| Field | Source type |
| --- | --- |
| input_schema | `{
    [key: string]: unknown;
}` |
| name | `string` |
| description? | `string \| null` |

## BetaMCPToolResultBlock

| Field | Source type |
| --- | --- |
| content | `string \| Array<BetaTextBlock>` |
| is_error | `boolean` |
| tool_use_id | `string` |
| type | `'mcp_tool_result'` |

## BetaMCPToolset

| Field | Source type |
| --- | --- |
| mcp_server_name | `string` |
| type | `'mcp_toolset'` |
| cache_control? | `BetaCacheControlEphemeral \| null` |
| configs? | `{
    [key: string]: BetaMCPToolConfig;
} \| null` |
| default_config? | `BetaMCPToolDefaultConfig` |
| tools? | `Array<BetaMCPToolParam> \| null` |

## BetaMCPToolUseBlock

| Field | Source type |
| --- | --- |
| id | `string` |
| input | `unknown` |
| name | `string` |
| server_name | `string` |
| type | `'mcp_tool_use'` |

## BetaMCPToolUseBlockParam

| Field | Source type |
| --- | --- |
| id | `string` |
| input | `unknown` |
| name | `string` |
| server_name | `string` |
| type | `'mcp_tool_use'` |
| cache_control? | `BetaCacheControlEphemeral \| null` |

## BetaRequestMCPServerToolConfiguration

| Field | Source type |
| --- | --- |
| allowed_tools? | `Array<string> \| null` |
| enabled? | `boolean \| null` |

## BetaRequestMCPServerURLDefinition

| Field | Source type |
| --- | --- |
| name | `string` |
| type | `'url'` |
| url | `string` |
| authorization_token? | `string \| null` |
| tool_configuration? | `BetaRequestMCPServerToolConfiguration \| null` |

## BetaRequestMCPToolResultBlockParam

| Field | Source type |
| --- | --- |
| tool_use_id | `string` |
| type | `'mcp_tool_result'` |
| cache_control? | `BetaCacheControlEphemeral \| null` |
| content? | `string \| Array<BetaTextBlockParam>` |
| is_error? | `boolean` |

## BetaTextBlock

| Field | Source type |
| --- | --- |
| citations | `Array<BetaTextCitation> \| null` |
| text | `string` |
| type | `'text'` |

## BetaTextBlockParam

| Field | Source type |
| --- | --- |
| text | `string` |
| type | `'text'` |
| cache_control? | `BetaCacheControlEphemeral \| null` |
| citations? | `Array<BetaTextCitationParam> \| null` |

## BetaTextCitation

`BetaCitationCharLocation | BetaCitationPageLocation | BetaCitationContentBlockLocation | BetaCitationsWebSearchResultLocation | BetaCitationSearchResultLocation`

## BetaTextCitationParam

`BetaCitationCharLocationParam | BetaCitationPageLocationParam | BetaCitationContentBlockLocationParam | BetaCitationWebSearchResultLocationParam | BetaCitationSearchResultLocationParam`
