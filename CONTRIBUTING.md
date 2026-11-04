# Contribute to AgentWeave

Open an issue or pull request with the behavior you want to change. Include a
small Dart example showing the intended developer experience.

Use Dart's recommended lints and formatter. Prefer named parameters, typed
configuration, immutable data, sealed events, and Streams. Keep provider-specific
options out of the core runtime. Do not add an abstraction without a caller.

For a bug fix, add a regression test that fails before the fix. For protocol or
provider changes, include representative request/response fixtures and explain
which upstream contract they exercise. Never commit real credentials or private
provider responses.

Run `dart run tool/check.dart` before opening a pull request. Record any check
you could not run. Paid provider tests require explicit authorization and the
existing cumulative budget ledger. Keep them out of ordinary CI.

See [updating upstream](docs/updating.md) for provider, Serverpod, and TanStack
changes. See [AGENTS.md](AGENTS.md) for the repository map and ownership rules.
