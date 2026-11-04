---
title: Build AI applications in Dart
hide:
  - toc
---

<div class="aw-hero" markdown>

<span class="aw-eyebrow">DART · SERVERPOD · FLUTTER</span>

# Your AI logic.<br> Your Dart stack.

Build agents with typed tools, stream responses to your application, and keep conversation state on your backend.

[Start with Serverpod](getting-started/serverpod.md){ .md-button .md-button--primary }
[Try plain Dart](getting-started/dart.md){ .md-button }

<span class="aw-status">Development preview · 0.1.0-dev.1 · Dart ≥ 3.12.2</span>

</div>

!!! warning "Read the limits before production"
    AgentWeave is under active development. The packages are not published to pub.dev yet. Start from the repository workspace and check [compatibility](compatibility.md) and [validation evidence](validation.md). AgentWeave is independent; TanStack, OpenAI, and Serverpod do not maintain or endorse it.

## Choose your starting point

<div class="grid cards" markdown>

-   **A Serverpod backend**

    Use authenticated endpoints, native Dart streaming, HTTP/SSE routes, and optional PostgreSQL history.

    [Run the backend example →](getting-started/serverpod.md)

-   **A Dart application or service**

    Use the core runtime with your own provider and application context. No Serverpod dependency is required.

    [Generate your first response →](getting-started/dart.md)

-   **A Flutter client**

    Connect to a backend through the native Serverpod bridge or use your own local model adapter on the device.

    [Choose a connection →](getting-started/frameworks.md)

-   **A provider adapter**

    Implement one model invocation. The runtime handles tools, validation, approvals, and the agent loop.

    [Write a provider →](providers.md) · [Cloudflare guide →](cloudflare.md)

</div>

## Keep responsibilities clear

**The core runtime** owns tool execution and conversation state. **Provider adapters** own provider transport and model options. **Framework integrations** own sessions and authentication. TanStack client interoperability is a wire contract; it does not require your application code to follow TypeScript conventions.

Start with [architecture](architecture.md) for ownership and cancellation rules, or [packages and API](reference.md) to find a symbol.

## Build with evidence

Every support claim has a scope. [Validation](validation.md) distinguishes unit fixtures, real Serverpod/database tests, official-client interoperability, and paid provider checks. [Known limits](compatibility.md) remain visible while the SDK develops.

Contributors and coding agents can use the [contribution guide](contributing.md), [agent guide](agent-guide.md), and [LLM reference](llms.txt).
