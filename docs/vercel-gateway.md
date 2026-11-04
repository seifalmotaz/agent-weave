# Use Vercel AI Gateway

`agent_weave_vercel_gateway` provides `GatewayChatModel` for the public Chat
Completions endpoint and `GatewayResponsesModel` for the public Responses
endpoint. They use different request and stream formats. Neither uses the
internal Vercel AI SDK V4 language-model wire protocol.

## Send a request

From the workspace root, run `dart pub get`. Save the following as
`examples/gateway_demo.dart`. Set `GATEWAY_API_KEY`, `GATEWAY_MODEL`, and
`GATEWAY_PROVIDER` in your backend environment. Choose a model and a provider
available to your account. Running the example makes a paid request.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_vercel_gateway/agent_weave_vercel_gateway.dart' as gateway;

Future<void> main() async {
  final key = Platform.environment['GATEWAY_API_KEY'];
  final modelId = Platform.environment['GATEWAY_MODEL'];
  final provider = Platform.environment['GATEWAY_PROVIDER'];
  if (key == null || modelId == null || provider == null) {
    throw StateError('Set GATEWAY_API_KEY, GATEWAY_MODEL, and GATEWAY_PROVIDER.');
  }
  final client = gateway.GatewayClient.withApiKey(apiKey: key);
  try {
    final model = gateway.GatewayChatModel(
      client: client,
      model: modelId,
      options: gateway.GatewayOptions(order: [provider]),
    );
    final result = await generateText(model: model, prompt: 'Say hello.');
    print(result.text);
  } finally {
    client.close();
  }
}
```

Run `dart run examples/gateway_demo.dart`. The response prints to the terminal.
To use Responses, replace `GatewayChatModel` with `GatewayResponsesModel`.
The same models work with `AiAgent` and its tools, approvals, and stored
history. See the [Dart API guide](dart-api.md).

## Resolve credentials per request

For a rotating Gateway token or bring-your-own-key (BYOK) credentials, use a
resolver. This example reads the environment each time the client makes a
request. Save it as `examples/gateway_byok_demo.dart`, and set
`GATEWAY_API_KEY`, `GATEWAY_MODEL`, and `ANTHROPIC_API_KEY` on the backend.
Choose a model available through the Anthropic provider. Running the example
makes a paid request.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_vercel_gateway/agent_weave_vercel_gateway.dart' as gateway;

String requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) throw StateError('Set $name.');
  return value;
}

Future<void> main() async {
  final modelId = requiredEnvironment('GATEWAY_MODEL');
  final client = gateway.GatewayClient(
    credentialResolver: () => gateway.GatewayCredentials(
      token: requiredEnvironment('GATEWAY_API_KEY'),
      byok: {
        'anthropic': [
          {'apiKey': requiredEnvironment('ANTHROPIC_API_KEY')},
        ],
      },
    ),
  );
  try {
    final model = gateway.GatewayResponsesModel(client: client, model: modelId);
    final result = await generateText(model: model, prompt: 'Say hello.');
    print(result.text);
  } finally {
    client.close();
  }
}
```

Replace the environment reads with your backend secret manager to rotate
credentials while the process runs. BYOK credential fields differ by provider.
Credentials belong in `GatewayCredentials`, not `GatewayOptions` or ordinary
`providerOptions`.

## Options and raw responses

`GatewayOptions` serializes routing preferences such as `models`, `order`, and
`only`, plus cache, timeout, privacy, and other fields. Both models also accept
provider-specific JSON through `providerOptions`. Serialization fixtures do not
prove that the live Gateway or a selected provider accepts or honors each field,
nor do they establish cost or billing behavior.

For native JSON, use `GatewayClient.createChat`, `streamChat`, `createResponse`,
or `streamResponse`. Nonstreaming results include native JSON, status, and
headers. Streams expose event envelopes and retain unknown metadata. Model
adapters normalize a limited set of fields; they do not invent a selected
provider identity from unverified metadata.

Responses accepts document URLs and inline data, but the high-level Gateway
adapter blocks file IDs. Chat does not accept documents or audio output. Model
and provider input support varies. See [documents](documents.md).

## Request lifetime and privacy

Credential resolution runs inside each request's deadline. The default total
deadline is two minutes; configure `requestTimeout` on `GatewayClient` or its
transport. A cancellation token or expired deadline prevents a late credential
resolver from dispatching the request. Close the Gateway client at shutdown.
`GatewayClient.withTransport` borrows its transport, and an injected HTTP client
is also caller-owned. Close borrowed resources yourself.

Errors are redacted using the request's credentials. Treat raw error details and
backend logs as private, and never send credentials or provider error details to
clients. AgentWeave stores model content in history, not request credentials.
A provider could still echo a secret in its model output, so the application
must protect any content it sends or stores.

Offline fixtures cover selected request and stream behavior, including Chat
continuation. Live Gateway behavior, provider selection, model acceptance, and
billing have not been verified. See [provider coverage](provider-coverage.md).

## Track option updates

The generated [option reference](gateway-options.md) maps 16 named options from
the pinned official SDK to their Dart entry points. It distinguishes typed
routing, request credentials, native extensions and SDK-only features. This is
an update-review aid, not proof of public endpoint or model behavior.

Use `GatewayCaching`, `GatewayServiceTier`, and `GatewayProviderSort` for fixed
option values. Unrepresented service-owned fields can use `GatewayOptions.extra`;
it rejects credentials, typed-field replacement and client-only image decoding.
Conditional Decisions fallbacks, batch jobs and image decoding are not implemented
by these Chat/Responses adapters.

After `npm ci --prefix tool/interop --ignore-scripts`, reproduce the field check:

```sh
dart run tool/gateway_contract.dart
node tool/interop/gateway-inventory.mjs --check
```

The independent consumer exercise is also runnable without a provider key:

```sh
dart --enable-asserts run examples/review_cases/gateway.dart
```
