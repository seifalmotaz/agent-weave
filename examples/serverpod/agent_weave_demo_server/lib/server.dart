import 'dart:io';
import 'package:agent_weave_serverpod/agent_weave_serverpod.dart';
import 'src/ai/agent_factory.dart';
import 'src/generated/serverpod.dart';

/// Supply your application's authentication handler in the Serverpod setup.
Future<void> run(List<String> args) async {
  final demo = Platform.environment['AGENT_WEAVE_DEMO_MODE'] == 'true';
  final pod = Serverpod(
    args,
    authenticationHandler: (session, key) async {
      if (demo && key == 'agent-weave-local-demo') {
        return AuthenticationInfo('local-demo-user', {}, authId: 'local-demo');
      }
      // Replace with your application's authentication handler.
      return null;
    },
  );
  pod.webServer.addRoute(
    AgentChatRoute<Session>(
      createAgent: createAgent,
      authenticate: (session) => session.authenticated?.userIdentifier,
      createContext: (session) => session,
    ),
    '/api/chat',
  );
  await pod.start();
}
