# agent_weave_openai

OpenAI adapters for AgentWeave. Import this library with a prefix, such as `openai`, to keep provider types separate from core types. Keep credentials on the backend. Uses openai_dart 11.0.1 for provider transport.

Development version, not published to pub.dev yet. Requires Dart 3.12.2 or later.

See the [workspace guide](https://github.com/seifalmotaz/agent-weave),
[compatibility limits](https://github.com/seifalmotaz/agent-weave/blob/main/docs/compatibility.md),
and [Serverpod example](https://github.com/seifalmotaz/agent-weave/tree/main/examples/serverpod).

Independent and unofficial. Not endorsed by TanStack, OpenAI, or Serverpod.

## Computer use

Register `OpenAIComputerTool<C>` in the agent's normal `tools` collection. The
application supplies an executor that performs the ordered, validated actions
and returns a fresh screenshot; this package does not control a computer.
Provide a stable `environmentId` for the same execution environment across
approval resumes. Approval defaults to `ComputerApproval.always`;
`ComputerApproval.safetyChecks` still requires approval whenever OpenAI sends
pending safety checks. The executor receives the original immutable call and
the ordered SDK action values. Handle cancellation and partial effects in the
executor, and do not automatically retry actions.

Use `OpenAIComputerTool.preview` with display dimensions and environment only
for the older `computer_use_preview` profile. Native computer calls require the
OpenAI Responses adapter; Chat Completions and compatible provider namespaces do
not support this continuation. A rejected or failed call ends the continuation;
start a new thread with a fresh screenshot. Safety-check acknowledgement has
fixture coverage but has not been verified against the live GA service.


## Hosted Responses tools

Configure `hostedTools` on `OpenAIResponsesModel` for selected provider-executed
search, code, image generation and server tool-search. Use
`OpenAIHostedTool.fromJson` and `OpenAIResponsesModel.native` when native fields
are missing or mistyped in the installed SDK. Completed image bytes become
ordered `ImagePart` data URLs; native replay and metadata remain private.

See [the hosted-tools guide](https://seifalmotaz.github.io/agent-weave/openai-hosted/)
for an executable example, SDK type limits and unsupported workflows. This does
not establish hosted-tool support for other compatible provider endpoints.

## Custom text tools

Register `OpenAICustomTool<C>` in the normal tools list for direct OpenAI Responses
calls with raw string input and text or native text/image/file output. Provide a
stable executor `bindingId`, application validation and an optional grammar.
Namespaces can use distinct local aliases. Approval denial can continue through
a declared native result; unknown execution failures remain closed.
See the [custom-tool guide](https://seifalmotaz.github.io/agent-weave/openai-custom-tools/)
and compiled live example. Asynchronous/programmatic calls and namespaced
function tools are not integrated. Keep private replay out of UI history.
