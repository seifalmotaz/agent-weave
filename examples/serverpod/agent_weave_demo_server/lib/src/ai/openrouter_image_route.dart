import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openrouter/agent_weave_openrouter.dart' as router;
import 'package:agent_weave_serverpod/agent_weave_serverpod.dart';
import 'package:agent_weave_serverpod_storage_server/agent_weave_serverpod_storage_server.dart';

/// Register with pod.webServer.addRoute(route, '/api/images').
/// The application owns the client and closes it at shutdown.
AgentGenerationRoute<
  router.OpenRouterImageRequest,
  router.OpenRouterImageResponse
>
createOpenRouterImageRoute({
  required router.OpenRouterClient client,
  required String model,
}) {
  final image = router.OpenRouterImageModel(client: client);
  return AgentGenerationRoute(
    authenticate: (session) => session.authenticated?.userIdentifier,
    // Keep model, count and routing policy on the server.
    decode: (input) => router.OpenRouterImageRequest(
      model: model,
      prompt: input['prompt'] as String,
      n: 1,
    ),
    createTask: (session) => GenerationTask(
      store: ServerpodRunStore(session),
      execute: (request, context) => image.generate(
        request,
        cancellation: context.cancellation,
      ),
      encodeResult: (response) => response.raw,
    ),
  );
}
