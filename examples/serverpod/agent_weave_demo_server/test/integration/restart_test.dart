import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  test(
    'fresh processes restore a PostgreSQL approval without replaying a completed decision',
    () async {
      final data = await Directory.systemTemp.createTemp(
        'agent-weave-restart-',
      );
      Process? server;
      final logs = StringBuffer();
      Future<void> stop() async {
        final child = server;
        if (child == null) return;
        child.kill(ProcessSignal.sigterm);
        try {
          await child.exitCode.timeout(const Duration(seconds: 30));
        } on TimeoutException {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
          rethrow;
        } finally {
          server = null;
        }
      }

      addTearDown(() async {
        await stop();
        if (data.existsSync()) await data.delete(recursive: true);
      });
      Future<String> start() async {
        final ready = Completer<int>();
        final child = await Process.start(
          Platform.resolvedExecutable,
          ['run', 'test/support/restart_server.dart', data.path],
          environment: {'AGENT_WEAVE_USE_OPENAI': 'false'},
        );
        server = child;
        child.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              logs.writeln(line);
              if (line.startsWith('AGENT_WEAVE_READY ') && !ready.isCompleted) {
                ready.complete(
                  (jsonDecode(line.substring('AGENT_WEAVE_READY '.length))
                          as Map)['port']
                      as int,
                );
              }
            });
        child.stderr.transform(utf8.decoder).listen(logs.write);
        unawaited(
          child.exitCode.then((code) {
            if (!ready.isCompleted) {
              ready.completeError(StateError('Server exited $code: $logs'));
            }
          }),
        );
        final port = await ready.future.timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw StateError('Server not ready: $logs'),
        );
        return 'http://localhost:$port/';
      }

      Future<String> command(
        String action,
        String url, {
        bool expectFailure = false,
        String thread = 'restart-thread',
      }) async {
        final child = await Process.start(
          Platform.resolvedExecutable,
          [
            'run',
            'example/approval_workflow.dart',
            action,
            thread,
            url,
          ],
          environment: {'AGENT_WEAVE_USE_OPENAI': 'false'},
        );
        final out = utf8.decoder.bind(child.stdout).join();
        final err = utf8.decoder.bind(child.stderr).join();
        var exited = false;
        try {
          final code = await child.exitCode.timeout(
            const Duration(seconds: 45),
          );
          exited = true;
          final output = await out;
          final errors = await err;
          expect(
            code,
            expectFailure ? isNot(0) : 0,
            reason: '$output\n$errors\n$logs',
          );
          return '$output\n$errors';
        } finally {
          if (!exited) {
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
          }
        }
      }

      final firstUrl = await start();
      expect(
        await command('start', firstUrl),
        contains('PAUSED restart-thread'),
      );
      await stop();
      final secondUrl = await start();
      final result = await command('approve', secondUrl);
      expect(result, contains('RESUMED restart-thread: Hello Ada'));
      expect(result, contains('Stored UI messages: 3'));
      expect(
        await command('approve', secondUrl, expectFailure: true),
        contains('No pending approval exists for this thread.'),
      );
      expect(
        await command('start', secondUrl, thread: 'rejected-thread'),
        contains('PAUSED rejected-thread'),
      );
      expect(
        await command('reject', secondUrl, thread: 'rejected-thread'),
        contains('Greeting was declined.'),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
