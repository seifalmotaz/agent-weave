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
    'packages/agent_weave_anthropic/test',
    'packages/agent_weave_openrouter/test',
    'packages/agent_weave_together/test',
    'packages/agent_weave_http/test',
    'packages/agent_weave_cloudflare/test',
    'packages/agent_weave_vercel_gateway/test',
    'packages/agent_weave_ollama/test',
    'packages/agent_weave_dart_frog/test',
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

  await run('node', ['--test', 'tool/interop/inventory.test.mjs']);
  await run('node', ['--test', 'tool/interop/anthropic-inventory.test.mjs']);
  await run('node', ['tool/interop/anthropic-inventory.mjs', '--check']);
  await run('dart', ['run', 'tool/anthropic_hosted_contract.dart']);
  await run('node', [
    '--test',
    'tool/interop/anthropic-computer-inventory.test.mjs',
  ]);
  await run('node', [
    'tool/interop/anthropic-computer-inventory.mjs',
    '--check',
  ]);
  await run('dart', ['run', 'tool/openai_hosted_contract.dart']);
  await run('node', [
    '--test',
    'tool/interop/openai-hosted-inventory.test.mjs',
  ]);
  await run('node', ['tool/interop/openai-hosted-inventory.mjs', '--check']);
  await run('dart', ['run', 'tool/computer_contract.dart']);
  await run('node', ['--test', 'tool/interop/computer-inventory.test.mjs']);
  await run('node', ['tool/interop/computer-inventory.mjs', '--check']);
  await run('dart', ['run', 'tool/together_contract.dart']);
  await run('node', ['tool/interop/inventory.mjs', '--check']);
  await run('dart', ['run', 'tool/gateway_contract.dart']);
  await run('node', ['tool/interop/gateway-inventory.mjs', '--check']);

  const example = 'examples/serverpod/agent_weave_demo_server';
  final passwords = File('$example/config/passwords.yaml');
  if (!passwords.existsSync()) {
    File('$example/config/passwords.example.yaml').copySync(passwords.path);
  }
  await run('dart', [
    'test',
    'test/integration',
    '--concurrency=1',
  ], directory: example);
  await run('node', ['tool/interop/test.mjs']);
  await run('node', ['tool/interop/dart-frog.mjs']);
  for (final consumer in [
    'ollama',
    'dart_frog',
    'provider_options',
    'openrouter_images',
    'cloudflare_streaming',
    'openai_hosted',
    'output_media_client',
  ]) {
    await run('dart', [
      '--enable-asserts',
      'run',
      'examples/review_cases/$consumer.dart',
    ]);
  }
  await run('dart', ['run', 'examples/review_cases/consumer.dart']);
  await run('dart', ['run', 'examples/review_cases/failures.dart']);
  await run('dart', ['run', 'examples/review_cases/reliability.dart']);
  await run('dart', ['run', 'examples/review_cases/anthropic.dart']);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/anthropic_native.dart',
  ]);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/anthropic_computer.dart',
  ]);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/anthropic_hosted.dart',
  ]);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/structured_continuation_client.dart',
  ]);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/computer.dart',
  ]);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/documents.dart',
  ]);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/openrouter.dart',
  ]);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/openrouter_native.dart',
  ]);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/together.dart',
  ]);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/gateway.dart',
  ]);
  await run('dart', [
    '--enable-asserts',
    'run',
    'examples/review_cases/cloudflare.dart',
  ]);
  await run('python3', ['tool/test_media_fixtures.py']);
  await run('python3', ['tool/test_audit_openai.py']);
  await run('python3', ['tool/test_cloudflare_contract.py']);
  await run('python3', ['tool/cloudflare_contract.py', '--check']);
  await run('python3', ['tool/test_openrouter_contract.py']);
  await run('python3', ['tool/openrouter_contract.py', '--check']);
  await run('python3', ['tool/test_ollama_contract.py']);
  await run('python3', ['tool/ollama_contract.py', '--check']);
  final secret = RegExp(
    r'(sk-(?:proj|svcacct)-[A-Za-z0-9_-]{20,}|sk-or-v1-[A-Za-z0-9_-]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{30,})',
  );
  for (final path in files) {
    final file = File(path);
    if (!file.existsSync()) continue;
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
