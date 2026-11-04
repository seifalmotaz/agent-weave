# OpenAI and Anthropic core application flows

Status: tracking draft. This file is an implementation checklist, not completed implementation.

Goal: validate the base framework with OpenAI Responses/Chat and Anthropic Messages. Other providers and exhaustive endpoint coverage are deferred.

Already present: native adapters, typed streaming/results, tool continuation, private replay, structured-output fixtures and cancellation tests. The independent reviewer found no blocking defect in the sampled native flows.

Remaining:
- [ ] Assemble one discoverable runnable offline main-flow consumer per provider, using existing HTTP fixtures: streamed text, tool continuation, structured result, cancellation and recreated agents.
- [ ] Assert request options, usage and private replay through the public adapter, rather than only the normalizer.
- [ ] Document supported structured-output modes and explicit unsupported combinations per provider.
- [ ] Run independent developer consumers, record concrete findings and scoped scores, and fix/retest findings.
- [ ] Run full minimum/stable CI and update validation evidence.

Live validation is separate. Do not use old chat credentials or make billable calls without the existing budget ledger and authorization. Existing $5 total ceiling still applies.

Start with packages/agent_weave_openai/test, packages/agent_weave_anthropic/test and examples/review_cases. Do not add speculative helper layers or broaden provider scope.
