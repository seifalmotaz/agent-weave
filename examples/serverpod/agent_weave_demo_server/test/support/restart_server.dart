import 'dart:convert';
import 'dart:io';
import 'package:agent_weave_demo_server/src/generated/serverpod.dart';

/// A test-only server with random ports and a parent-owned durable database.
Future<void> main(List<String> args) async {
  if (args.length != 1) throw ArgumentError('Pass the database directory.');
  final pod = Serverpod(
    ['--mode=test', '--apply-migrations'],
    authenticationHandler: (session, key) async =>
        key == 'agent-weave-local-demo'
        ? AuthenticationInfo('restart-owner', {}, authId: 'restart-demo')
        : null,
    configOverride: (config) => config.copyWith(
      apiServer: ServerConfig(
        port: 0,
        publicHost: 'localhost',
        publicPort: 0,
        publicScheme: 'http',
      ),
      insightsServer: ServerConfig(
        port: 0,
        publicHost: 'localhost',
        publicPort: 0,
        publicScheme: 'http',
      ),
      database: PostgresDatabaseConfig.embedded(
        dataPath: args.single,
        name: 'agent_weave_restart',
        // Migrations hold a lock connection while applying SQL on another.
        maxConnectionCount: 10,
      ),
    ),
  );
  await pod.start();
  stdout.writeln('AGENT_WEAVE_READY ${jsonEncode({'port': pod.server.port})}');
}
