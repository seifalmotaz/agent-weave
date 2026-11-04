# Third-party notices

The interrupt schema identity and approval envelope contracts are derived from
TanStack AI. AgentWeave is independent and unofficial.

TanStack AI is distributed under the following license:

MIT License

Copyright (c) 2025 Tanner Linsley

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Provider transport is supplied by openai_dart, maintained by David Miguel.
Serverpod and the TanStack Dart client are dependencies with their own licenses.
See each dependency's published package for its notices.

## Anthropic transport

The native Messages adapter depends on anthropic_sdk_dart, maintained by David
Miguel and contributors, under the MIT license. It is a third-party SDK and
is not an official Anthropic library. Dependency license notices remain in
the distributed SDK package.

## Cloudflare contract sources

The reviewed API schema subset is from Cloudflare's api-schemas repository,
BSD-3-Clause. Public model documentation schemas are attributed to Cloudflare
under CC BY 4.0. Original source URLs, revision, hashes, retained licenses and
extraction details are in `tool/contracts/cloudflare/README.md`. Generated
inventories reorganize those schemas; AgentWeave remains independent.

## OpenRouter contract source

The pinned official OpenRouter OpenAPI document declares the MIT license. The
example-redacted snapshot, attribution and license are in `tool/contracts/openrouter/`.
Its content hash is separate from the official TypeScript SDK's Git revision and
Apache-2.0 license. No TypeScript SDK implementation is copied into the adapter.
