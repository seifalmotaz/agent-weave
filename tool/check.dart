import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final listing = await Process.run('git', [
    'ls-files',
    '-co',
    '--exclude-standard',
    '-z',
  ]);
  final files = (listing.stdout as String)
      .split('\x00')
      .where((p) => p.isNotEmpty)
      .toList();
  final dartFiles = files
      .where(
        (p) =>
            p.endsWith('.dart') &&
            !p.contains('/generated/') &&
            !p.contains('/src/protocol/'),
      )
      .toList();
  await run('dart', [
    'format',
    '--output=none',
    '--set-exit-if-changed',
    ...dartFiles,
  ]);
  await run('dart', ['analyze', '--fatal-infos']);
  await run('dart', ['run', 'tool/build_llms.dart', '--check']);
  await run('dart', [
    'test',
    'test',
    'packages/agent_weave/test',
    'packages/agent_weave_openai/test',
    'packages/agent_weave_serverpod_client/test',
  ]);
  await run('npm', [
    'ci',
    '--prefix',
    'tool/interop',
    '--ignore-scripts',
    '--no-audit',
    '--no-fund',
  ]);

  const example = 'examples/serverpod/agent_weave_demo_server';
  final passwords = File('$example/config/passwords.yaml');
  if (!passwords.existsSync()) {
    File('$example/config/passwords.example.yaml').copySync(passwords.path);
  }
  await run('dart', ['test', 'test/integration'], directory: example);
  await run('node', ['tool/interop/test.mjs']);
  await run('python3', ['tool/test_audit_openai.py']);
  final secret = RegExp(
    r'(sk-(?:proj|svcacct)-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,})',
  );
  for (final path in files) {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() > 2000000) continue;
    final text = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
    if (secret.hasMatch(text)) {
      throw StateError('Credential pattern found in $path');
    }
  }
  stdout.writeln('AgentWeave checks passed. Live provider calls were not run.');
}

Future<void> run(
  String executable,
  List<String> arguments, {
  String? directory,
}) async {
  stdout.writeln('Checking: $executable ${arguments.take(5).join(' ')}');
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: directory,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, arguments, 'Check failed', code);
  }
}
