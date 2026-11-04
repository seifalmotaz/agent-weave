# OpenAI computer protocol inventory

Generated from the pinned official Node SDK. This is a selected protocol inventory, not full computer or endpoint coverage.

- The pinned schema requires pending_safety_checks; the GA driver accepts its absence, while legacy action calls require it.
- Screenshot detail is a separately documented driver extension absent from this Node pin.
- Output ID, status and created_by are not integrated; native replay and runtime-owned fields are not public options.

## ComputerTool

| Field | Source type | Disposition |
| --- | --- | --- |
| type | `'computer'` | typed |

## ComputerUsePreviewTool

| Field | Source type | Disposition |
| --- | --- | --- |
| display_height | `number` | typed |
| display_width | `number` | typed |
| environment | `'windows' \| 'mac' \| 'linux' \| 'ubuntu' \| 'browser'` | typed |
| type | `'computer_use_preview'` | typed |

## ResponseComputerToolCall

| Field | Source type | Disposition |
| --- | --- | --- |
| id | `string` | private-replay |
| call_id | `string` | native-controlled |
| pending_safety_checks | `Array<ResponseComputerToolCall.PendingSafetyCheck>` | native-controlled |
| status | `'in_progress' \| 'completed' \| 'incomplete'` | native-controlled |
| type | `'computer_call'` | native-controlled |
| action? | `ResponseComputerToolCall.Click \| ResponseComputerToolCall.DoubleClick \| ResponseComputerToolCall.Drag \| ResponseComputerToolCall.Keypress \| ResponseComputerToolCall.Move \| ResponseComputerToolCall.Screenshot \| ResponseComputerToolCall.Scroll \| ResponseComputerToolCall.Type \| ResponseComputerToolCall.Wait` | typed |
| actions? | `ComputerActionList` | typed |

## ResponseComputerToolCall.PendingSafetyCheck

| Field | Source type | Disposition |
| --- | --- | --- |
| id | `string` | native-controlled |
| code? | `string \| null` | native-controlled |
| message? | `string \| null` | native-controlled |

## ResponseComputerToolCall.Click

| Field | Source type | Disposition |
| --- | --- | --- |
| button | `'left' \| 'right' \| 'wheel' \| 'back' \| 'forward'` | typed |
| type | `'click'` | typed |
| x | `number` | typed |
| y | `number` | typed |
| keys? | `Array<string> \| null` | typed |

## ResponseComputerToolCall.DoubleClick

| Field | Source type | Disposition |
| --- | --- | --- |
| keys | `Array<string> \| null` | typed |
| type | `'double_click'` | typed |
| x | `number` | typed |
| y | `number` | typed |

## ResponseComputerToolCall.Drag

| Field | Source type | Disposition |
| --- | --- | --- |
| path | `Array<Drag.Path>` | typed |
| type | `'drag'` | typed |
| keys? | `Array<string> \| null` | typed |

## ResponseComputerToolCall.Drag.Path

| Field | Source type | Disposition |
| --- | --- | --- |
| x | `number` | typed |
| y | `number` | typed |

## ResponseComputerToolCall.Keypress

| Field | Source type | Disposition |
| --- | --- | --- |
| keys | `Array<string>` | typed |
| type | `'keypress'` | typed |

## ResponseComputerToolCall.Move

| Field | Source type | Disposition |
| --- | --- | --- |
| type | `'move'` | typed |
| x | `number` | typed |
| y | `number` | typed |
| keys? | `Array<string> \| null` | typed |

## ResponseComputerToolCall.Screenshot

| Field | Source type | Disposition |
| --- | --- | --- |
| type | `'screenshot'` | typed |

## ResponseComputerToolCall.Scroll

| Field | Source type | Disposition |
| --- | --- | --- |
| scroll_x | `number` | typed |
| scroll_y | `number` | typed |
| type | `'scroll'` | typed |
| x | `number` | typed |
| y | `number` | typed |
| keys? | `Array<string> \| null` | typed |

## ResponseComputerToolCall.Type

| Field | Source type | Disposition |
| --- | --- | --- |
| text | `string` | typed |
| type | `'type'` | typed |

## ResponseComputerToolCall.Wait

| Field | Source type | Disposition |
| --- | --- | --- |
| type | `'wait'` | typed |

## ResponseComputerToolCallOutputItem

| Field | Source type | Disposition |
| --- | --- | --- |
| id | `string` | not-integrated |
| call_id | `string` | native-controlled |
| output | `ResponseComputerToolCallOutputScreenshot` | typed |
| status | `'completed' \| 'incomplete' \| 'failed' \| 'in_progress'` | not-integrated |
| type | `'computer_call_output'` | native-controlled |
| acknowledged_safety_checks? | `Array<ResponseComputerToolCallOutputItem.AcknowledgedSafetyCheck>` | native-controlled |
| created_by? | `string` | not-integrated |

## ResponseComputerToolCallOutputItem.AcknowledgedSafetyCheck

| Field | Source type | Disposition |
| --- | --- | --- |
| id | `string` | native-controlled |
| code? | `string \| null` | native-controlled |
| message? | `string \| null` | native-controlled |

## ResponseComputerToolCallOutputScreenshot

| Field | Source type | Disposition |
| --- | --- | --- |
| type | `'computer_screenshot'` | typed |
| file_id? | `string` | typed |
| image_url? | `string` | typed |
