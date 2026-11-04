import 'dart:io';

const documents = [
  'README.md',
  'ROADMAP.md',
  'docs/dart-api.md',
  'docs/offline-support.md',
  'docs/dx-review.md',
  'docs/architecture.md',
  'docs/tools.md',
  'docs/approval-contracts.md',
  'docs/providers.md',
  'docs/documents.md',
  'docs/citations.md',
  'docs/output-references.md',
  'docs/computer-use.md',
  'docs/computer-parameters.md',
  'docs/openai.md',
  'docs/openai-hosted.md',
  'docs/openai-mcp.md',
  'docs/openai-hosted-parameters.md',
  'docs/openrouter.md',
  'docs/openrouter-images.md',
  'docs/openrouter-image-api.md',
  'docs/openrouter-api-reference.md',
  'docs/together.md',
  'docs/cloudflare.md',
  'docs/cloudflare-api-reference.md',
  'docs/vercel-gateway.md',
  'docs/gateway-options.md',
  'docs/together-options.md',
  'docs/anthropic.md',
  'docs/anthropic-hosted.md',
  'docs/anthropic-mcp.md',
  'docs/anthropic-mcp-parameters.md',
  'docs/anthropic-parameters.md',
  'docs/anthropic-computer.md',
  'docs/anthropic-computer-parameters.md',
  'docs/ollama.md',
  'docs/ollama-parameters.md',
  'docs/dart-frog.md',
  'docs/openai-options-audit.md',
  'docs/provider-coverage.md',
  'docs/compatibility.md',
  'docs/updating.md',
  'docs/validation.md',
  'CONTRIBUTING.md',
  'AGENTS.md',
];

void main(List<String> args) {
  final full = documents
      .map((path) => '# Source: $path\n\n${File(path).readAsStringSync()}')
      .join('\n\n');
  final index =
      '''# AgentWeave

> Independent Dart AI runtime with Serverpod integration and TanStack client interoperability.

Development version. Read compatibility and validation before making support claims.

${documents.map((path) => '- [$path](https://github.com/seifalmotaz/agent-weave/blob/main/$path)').join('\n')}

- [Full LLM guide](https://github.com/seifalmotaz/agent-weave/blob/main/llms-full.txt)
''';
  for (final entry in {'llms.txt': index, 'llms-full.txt': full}.entries) {
    final file = File(entry.key);
    if (args.contains('--check')) {
      if (!file.existsSync() || file.readAsStringSync() != entry.value) {
        throw StateError(
          '${entry.key} is stale. Run dart run tool/build_llms.dart.',
        );
      }
    } else {
      file.writeAsStringSync(entry.value);
    }
  }
}
