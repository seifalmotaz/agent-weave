import 'dart:io';

const documents = [
  'README.md',
  'docs/architecture.md',
  'docs/tools.md',
  'docs/providers.md',
  'docs/openai.md',
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
