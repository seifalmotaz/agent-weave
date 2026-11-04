# OpenAI hosted tools

Configure provider-executed tools on `OpenAIResponsesModel`, separately from
the application's `AiAgent.tools`. OpenAI executes hosted searches, code and
image generation. AgentWeave executes only registered application tools, after
the complete response has been validated and any approval has been resolved.

## Search from Dart

This example runs on a backend. Select an OpenAI model that supports the
configured tool and set `OPENAI_API_KEY` and `OPENAI_MODEL`. Running it makes a
billable provider request. The repository checks compile it without making that
request.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

Future<void> main() async {
  final key = Platform.environment['OPENAI_API_KEY'];
  final modelId = Platform.environment['OPENAI_MODEL'];
  if (key == null || key.isEmpty || modelId == null || modelId.isEmpty) {
    throw StateError('Set OPENAI_API_KEY and OPENAI_MODEL.');
  }
  final client = openai.OpenAIClient.withApiKey(key);
  try {
    final result = await generateText(
      model: openai.OpenAIResponsesModel.native(
        authorityBindingId: 'example-authority',
        client: client,
        model: modelId,
        hostedTools: [
          openai.OpenAIHostedTool.fromJson({
            'type': 'web_search',
            'user_location': {
              'type': 'approximate',
              'city': 'Cairo',
              'country': 'EG',
            },
          }),
        ],
        toolChoice: 'auto',
      ),
      prompt: 'Find the latest stable Dart release.',
      maxOutputTokens: 1024,
    );
    print(result.text);
  } finally {
    client.close();
  }
}
```

The same source is in
[`examples/openai_hosted_demo.dart`](https://github.com/seifalmotaz/agent-weave/blob/main/examples/openai_hosted_demo.dart).
For Serverpod, pass this model to the agent behind your authenticated endpoint
and use `ServerpodRunStore` for durable history. Keep the provider client alive
for the application lifetime, then close it on shutdown.

## Definitions and native options

`OpenAIHostedTool` accepts an SDK `ResponseTool`.
`OpenAIHostedTool.fromJson` accepts an immutable snapshot of native JSON.
Use the latter when the installed SDK cannot represent a field accurately.
The adapter currently recognizes these hosted tool families:

| Tool | Integrated behavior |
| --- | --- |
| `web_search` and the pinned preview variants | Retain ordered native calls and search metadata for private continuation |
| `file_search` | Require vector-store IDs; retain private queries and results |
| `code_interpreter` | Require a container ID or auto configuration; retain private code, container IDs and outputs |
| `image_generation` | Retain native output and expose completed image bytes as an `ImagePart` data URL |
| `tool_search` with `execution: server` | Retain server search calls and loaded definitions; ordinary executors must still be registered by the application |

One definition per family is allowed. Hosted tools do not add local executors.
Client tool search, shell, custom-tool and patch lifecycles are not
integrated and fail explicitly. Computer use has its own
[application-controlled contract](computer-use.md).

`OpenAIResponsesModel.native` keeps SDK authentication, client ownership and
cancellation while using native JSON/SSE for Responses. Declare a stable,
nonsecret `authorityBindingId` for the provider account and endpoint. Change it
when that authority changes. It cannot be inferred from rotating API keys.

For managed tools, supply immutable `options` for additional native request
fields and `toolChoice` for tool selection. These values are copied at
construction and included in the private continuation contract. Both typed and
native constructors reject `configure` callbacks when managed tools are present.
History, model, tools, output schema and execution bounds remain runtime-owned.
Native extensions are preserved; acceptance by a live model is not guaranteed.

For ordinary models without managed tools, the existing typed and native
`configure` callbacks remain available. The typed view patches changes onto
original JSON, retaining unchanged unknown fields. These callbacks cannot add
managed tools or replace the model or tool choice. Use immutable `options` for
configuration that must stay stable across resumed approvals. Callback validation
runs during the next model invocation and can fail after a local tool has run;
it is not a preflight guarantee for arbitrary application code.

For registered local functions used alongside managed tools, declare native
function settings through `functionToolOptions`, keyed by the registered name:

```dart
functionToolOptions: {
  'lookupCustomer': {'strict': true, 'defer_loading': false},
},
```

This map is frozen and included in the profile. Supported settings retain the
existing function handler's limits: `strict`, `defer_loading`, `async: false`
and direct `allowed_callers`. Asynchronous or programmatic function execution
still requires a separate handler. A name must identify a registered function;
the map cannot replace its schema, description or executor.

With `openai_dart 11.0.1`, image-generation masks,
moderation and compression have incorrect SDK types; native JSON accepts an
object mask, `auto` or `low` moderation, and integer compression from 0 to 100.
The type correction is proposed in [upstream PR #436](https://github.com/davidmigloz/ai_clients_dart/pull/436);
this workspace continues to use the released SDK pin.

Function tools may use strict schemas and deferred loading. Their names and
schemas must still match registered executors. Asynchronous and programmatic
function continuations need a separate handler and are rejected. Background
Responses, `previous_response_id` and provider-owned conversations are also
outside the agent's stateless full-history replay contract; use SDK resource
APIs separately for those workflows.

## Output, storage and privacy

Completed image results become `ImagePart` data URLs in assistant history.
Their position among text parts is retained in native Dart results, sanitized
client snapshots and hydration. Image-only responses work too. The inline bytes
are persisted with the conversation, so application storage and response-size
limits must account for them. AgentWeave does not host or optimize artifacts.

Raw ordered Responses output is stored under `openai.responses`. Top-level
response metadata is retained under `openai.responses.metadata`. Both are
server-side `providerData`, excluded from public history and events. Unknown
fields on recognized output items survive replay. Never expose raw checkpoints
as a client history endpoint.

Reviewed annotations produce public typed references, including scoped file
handles. Code outputs, unselected metadata and opaque native fields stay private.
Applications render source cards and authorize file retrieval. Precise native
highlights, partial image progress, hosted-tool progress and container downloads
remain outside this adapter's normalization contract.

## Verification and scope

The [generated field inventory](openai-hosted-parameters.md) records selected
official Node SDK declarations and an executable Dart request fixture. Its
upstream check detects changes to the selected declarations. It does not
certify all nested constraints or the whole OpenAI API.

Offline cases verify request preservation, mixed hosted/application tools,
approval and recreation, terminal validation, cancellation, media ordering,
private replay, native Dart and official JavaScript clients, and PostgreSQL
history. No live hosted search, container, tool-search or Responses-image
request was made for this increment. The earlier standalone Images API smoke
test is a separate workflow. See [validation](validation.md).


## Output references

Completed Responses annotations now produce typed sources and native positions.
See [output references](output-references.md) for all four forms, persistence,
file authorization and the distinction between native indexes and UTF-16 text.
Partial images, hosted progress and artifact hosting remain open.


## MCP approvals

Remote MCP uses a separate provider-owned approval lifecycle. See [MCP approvals](openai-mcp.md) for configuration, owner-bound credentials, generic client interrupts, denial and indeterminate continuations.
