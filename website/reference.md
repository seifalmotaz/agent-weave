# Packages and API

The monorepo contains fourteen packages. Use the smallest set needed by your application.

| Package | Owns |
| --- | --- |
| `agent_weave` | Provider contracts, typed tools, agent execution, results, generation tasks, protocol events |
| `agent_weave_anthropic` | Native Anthropic JSON/SSE, Messages and typed computer toolsets |
| `agent_weave_openrouter` | OpenRouter native Chat/Responses and private replay |
| `agent_weave_ollama` | Native local Ollama chat, typed options, embeddings and NDJSON |
| `agent_weave_dart_frog` | Authenticated Dart Frog chat, history, replay and generation handlers |
| `agent_weave_http` | Shared JSON HTTP transport for provider adapters |
| `agent_weave_vercel_gateway` | Vercel AI Gateway Chat and Responses adapters |
| `agent_weave_cloudflare` | Workers AI and AI Gateway REST clients and selected model adapters |
| `agent_weave_together` | Native Together Chat Completions client and adapter |
| `agent_weave_openai` | OpenAI model adapters and typed provider resource access |
| `agent_weave_serverpod` | Authenticated HTTP/SSE routes and native endpoint helpers |
| `agent_weave_serverpod_client` | Native transport for the existing TanStack Dart client |
| `agent_weave_serverpod_storage_server` | Optional PostgreSQL run store and generated Serverpod module |
| `agent_weave_serverpod_storage_client` | Generated protocol types for the optional storage module |

## Core entry points

| Symbol | Use |
| --- | --- |
| `generateText` | Stateless request returning a typed `AgentResult` |
| `generateObject<T>` | Schema-validated JSON decoded into your Dart type |
| `AiAgent<C>` | Reusable agent definition with a trusted application context |
| `AiAgent.generate` | Stored conversation run returning a typed result |
| `AiAgent.run` | Stored conversation run returning streaming events |
| `Tool<I, O, C>` | Schema-validated tool with typed input, output, and context |
| `ClientTool<C>` | Explicitly registered client-executed tool |
| `OpenAIComputerTool<C>` | Application-executed native Responses computer tool; see [computer use](computer-use.md) |
| `ModelFinished.continuation` | Completed provider invocation requiring another checkpointed, counted step |
| `StructuredMessageOutput` | Immutable parsed structured data retained in assistant history |
| `AnthropicHostedTool` | Provider-executed search/fetch/code/tool-search definition, separate from local executors |
| `CancellationToken` | Cancellation Future and disposable single-event Stream |
| `RunStore` | Atomic reservations, checkpoints, and persisted events |
| `GenerationTask<P, R>` | Typed operation with generation progress/result events |

See [the Dart API guide](dart-api.md) for complete recipes and [architecture](architecture.md) for lifecycle and ownership rules.

## Test entry point

`package:agent_weave/testing.dart` exports `ScriptedChatModel`. It has no dependency on `package:test`; your application chooses its test framework. See [testing](testing.md).

## Provider-specific types

Import `agent_weave_openai` with a prefix, such as `openai`. Provider types can share names with core types. Model and account capabilities vary; an adapter's supported request formats do not mean every selected model accepts them.

The [Cloudflare guide](cloudflare.md) separates native, gateway and compatible contracts. The [OpenAI guide](openai.md) distinguishes normalized adapters from delegated provider resources. The [operation inventory](openai-api-inventory.json) is an update-review list, not an endpoint parity certificate.

## Generate API reference locally

From the repository root:

```sh
cd packages/agent_weave
dart doc --output ../../.dart_tool/api-core
```

Open `.dart_tool/api-core/index.html` relative to the repository root. Repeat inside another package to generate its API documentation. The published site provides curated guides; it does not currently host generated Dartdoc output.
