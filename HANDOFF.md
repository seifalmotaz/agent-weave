# AgentWeave session handoff

Checkpoint date: 2026-11-04. Work is intentionally stopped for a later session.
Read this file, AGENTS.md, ROADMAP.md and the relevant PR before continuing.
Revalidate GitHub state; the status below is a snapshot, not a live guarantee.

## Current scope

The user's latest decision is to finish the base framework with OpenAI and
Anthropic, primarily for Serverpod developers. Other providers and exhaustive
provider API coverage are deferred. Preserve existing integrations and their
honest limits. Dart-native APIs and DX lead; TanStack interoperability remains.
Do not pursue specialized provider features merely to increase coverage.

## Repository and branches

Repository: https://github.com/seifalmotaz/agent-weave
Pages: https://seifalmotaz.github.io/agent-weave/

- Main implementation checkpoint: `7f20c32c95bf26c4b7ff4f0bce7ec2f821bf2fa1`.
- Current working branch: `work/base-framework-checkpoint`, draft PR #1.
  Includes local commits `4890298` (onboarding) and `90f07ef` (scope), plus this
  handoff. Read the branch's latest commit rather than assuming main has it.
- PR #2: `work/openai-anthropic-core`.
- PR #3: `work/serverpod-foundation`.
- PR #4: `work/native-dart-readiness`.

PRs #2–#4 currently contain tracking work plans only. They are not implemented
features or evidence of completion. PR #1 contains actual onboarding/example
changes. All four are drafts; no merge or publication occurred in this wrap-up.

Links:
- https://github.com/seifalmotaz/agent-weave/pull/1
- https://github.com/seifalmotaz/agent-weave/pull/2
- https://github.com/seifalmotaz/agent-weave/pull/3
- https://github.com/seifalmotaz/agent-weave/pull/4

## What works and where we stopped

Core has typed generation/results, sealed native streaming updates and the final
result from the same execution, tools, approvals, cancellation, safe errors and
private continuation contracts. Serverpod has authenticated, owner-scoped
PostgreSQL persistence, real transport fixtures and graceful restart tests.

The latest main implementation added OpenAI direct custom text tools, native
namespace dispatch, typed results/content, approval fallback policy, strict
stream reconciliation and private replay. Async/programmatic custom execution
is unsupported. Typed SDK named-custom selection is missing from published
openai_dart 11.0.1; native transport works. Old unfinished execution profiles
without the complete registered-tool snapshot fail closed; start a new
conversation and retain completed history. See migration docs.

PR #1 adds `examples/review_cases/serverpod_onboarding.dart` and wires it into
`tool/check.dart`. It recreates a client, attaches to stored approval and checks
zero effects before approval and one afterward. This uses MemoryRunStore and
in-process callbacks, not PostgreSQL/WebSocket/process restart. The starting
Dart guide now recommends native streamText/AiAgent.stream before wire events.

## Verified evidence

At main commit 7f20c32, the complete local tool/check passed 694 unit/regression
tests, 38 real PostgreSQL/Serverpod tests, 28 standalone official JavaScript
client scenarios, four Dart Frog scenarios, contract checks and offline recipes.
Core/OpenAI Dartdoc dry runs reported zero warnings/errors. No new paid calls.

GitHub minimum/stable CI run 41888391111 is SUCCESS. Documentation deployment
41888391213 is SUCCESS. The live custom guide, inventory and both LLM files were
verified against source bytes. These results belong to 7f20c32; recheck CI for
the draft branch heads before merging.

PR #1 onboarding consumer, analysis, three documentation checks and strict
MkDocs build pass locally. Independent onboarding review is 8/10 for this scope,
not overall acceptance. Rechecked native consumer, streaming, cancellation and
onboarding examples pass. No concrete blocking defect emerged in that sample;
no new helper abstraction was justified.

## Next session

1. Fetch and inspect the four PRs and CI. Start from PR #1 for the current scope
   and handoff; do not assume the local main branch is the newest checkpoint.
2. Prioritize PR #2: make one compact, discoverable main-flow fixture per OpenAI
   and Anthropic adapter using existing HTTP fixtures. Cover streamed text, tool
   continuation, structured output, cancellation and recreated agents. Record
   supported modes and exact evidence without inventing full parity.
3. Use PR #3 to audit Serverpod claims against real integration tests and close
   demonstrated reconnect/recovery gaps. Do not add redundant tests.
4. Use PR #4 for public API/dependency readiness. Protocol journals and TanStack
   dependencies still live in core. Extract only where concrete coupling
   justifies it. Do not claim the package group is ready for pub.dev: the
   workspace still Git-pins unpublished tanstack_ai_dart changes.
5. Use an independent developer-consumer subagent each implementation round,
   GPT-6.1 Terra low/medium. Run real cases, report honest scoped scores and
   retest findings. Do not use OpenCode.

## Commands and environment

Local SDK: `.dart_tool/dart-3.12.2/dart-sdk/bin/dart`.

```sh
git fetch origin
# In a fresh clone, switch to work/base-framework-checkpoint first.
PATH="$PWD/.dart_tool/dart-3.12.2/dart-sdk/bin:$PATH" dart run tool/check.dart
.dart_tool/docs-venv/bin/python -m unittest discover -s tool -p 'test_docs_site.py'
.dart_tool/docs-venv/bin/mkdocs build --strict
.dart_tool/dart-3.12.2/dart-sdk/bin/dart run tool/build_llms.dart --check
```

Run PostgreSQL suites serially. The main disk is nearly full; compilation hit
ENOSPC. Root checks now compile examples into a cleaned temporary directory.
Use a task-owned TMPDIR on /Volumes/MacExtend if needed, where space is available.
Preserve SDKs, source, reports and paid-budget state; do not delete unrelated files.
Additional isolated worktrees are under
`/Volumes/MacExtend/aw-workstreams-hds6g2sz/` with names matching the work plans.
A fresh session can fetch their remote branches without these local paths.

## External contributions and limits

- Upstream Anthropic request-ID PR #445 is merged:
  https://github.com/davidmigloz/ai_clients_dart/pull/445
  Published anthropic_sdk_dart remained 9.0.1 when checked; merge is not release.
- OpenAI custom tool-choice PR #451 is open:
  https://github.com/davidmigloz/ai_clients_dart/pull/451
  Patched upstream offline suite passed 25,898 tests, three skipped. Local tests
  used a sparse checkout and existing package config. GitHub run 41887508949
  required maintainer action and had no jobs when checked. Revalidate it.
- Existing upstream SDK worktrees live under `.dart_tool/upstream/`; do not
  reapply already-merged patches. Current package pins are not upgraded to forks.
- Overall live-test ceiling is $5. Preserve `.dart_tool/live-budget.json`; do not
  reset reservations or retrieve old chat credentials. If the ledger is missing
  in a fresh environment, establish the prior cumulative spend before paid work.
- No pub.dev publication is authorized by this handoff. Keep publication,
  merging, tests and deployment evidence distinct. No credentials belong here.

## Deferred post-release PRs

These tracking drafts are for after the base release and do not block PRs #1–#4.
They contain work plans only. Each remote branch is named `later/<slug>` and
contains `workstreams/<slug>.md`; continue implementation there after fetching.

- [#5: OpenRouter provider completion](https://github.com/seifalmotaz/agent-weave/pull/5) — `later/openrouter-expansion`
- [#6: Together provider completion](https://github.com/seifalmotaz/agent-weave/pull/6) — `later/together-expansion`
- [#7: Vercel AI Gateway provider completion](https://github.com/seifalmotaz/agent-weave/pull/7) — `later/vercel-gateway-expansion`
- [#8: Cloudflare Workers AI and Gateway completion](https://github.com/seifalmotaz/agent-weave/pull/8) — `later/cloudflare-expansion`
- [#9: Ollama and Flutter local-model validation](https://github.com/seifalmotaz/agent-weave/pull/9) — `later/ollama-local-models`
- [#10: Advanced OpenAI and Anthropic capabilities](https://github.com/seifalmotaz/agent-weave/pull/10) — `later/advanced-provider-capabilities`
- [#11: Dart Frog and Flutter ecosystem expansion](https://github.com/seifalmotaz/agent-weave/pull/11) — `later/framework-ecosystem`

The complete phase index is `workstreams/README.md` on this checkpoint branch.
Work remains paused after this bookkeeping update. No provider implementation,
merge or publication was performed to create these tracking drafts.
