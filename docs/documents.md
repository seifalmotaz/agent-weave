# Send documents to a model

Use `DocumentPart` in a user message to send a document by URL, inline data,
or a provider file ID. The adapter sends the reference or data you provide. It
does not upload or download files for you.

## Send inline text to OpenAI Responses

From the workspace root, run `dart pub get`. Save this example as
`examples/document_demo.dart`. Set `OPENAI_API_KEY` and `OPENAI_MODEL` in your
backend environment, choosing a Responses model available to your account.
Running the example makes a paid provider request.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

Future<void> main() async {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  final modelId = Platform.environment['OPENAI_MODEL'];
  if (apiKey == null || modelId == null) {
    throw StateError('Set OPENAI_API_KEY and OPENAI_MODEL.');
  }
  final client = openai.OpenAIClient.withApiKey(apiKey);
  try {
    final model = openai.OpenAIResponsesModel(client: client, model: modelId);
    final request = ModelRequest(messages: [
      ChatMessage(id: 'user-1', role: MessageRole.user, content: [
        TextPart('Summarize this document.'),
        DocumentPart.bytes(
          'AgentWeave runs agents in Dart.'.codeUnits,
          mimeType: 'text/plain',
          filename: 'note.txt',
        ),
      ]),
    ]);
    await for (final event in model.stream(
      request,
      cancellation: CancellationToken(),
    )) {
      if (event is TextDelta) stdout.write(event.text);
    }
    stdout.writeln();
  } finally {
    client.close();
  }
}
```

Run `dart run examples/document_demo.dart`. A supported model prints a
summary. Provider permissions, model formats, and file size limits still apply.

## Choose a source

Replace the `DocumentPart.bytes` value in the example with one of these:

```dart
// An absolute HTTP(S) URL without embedded credentials.
DocumentPart.url('https://example.com/report.pdf', filename: 'report.pdf')

// Base64-encoded, nonempty file content, without a data URL prefix.
DocumentPart.base64(encodedContent, mimeType: 'application/pdf', filename: 'report.pdf')

// A file already uploaded to OpenAI by your application.
DocumentPart.fileId(fileId, provider: 'openai', filename: 'report.pdf')
```

`DocumentPart.bytes` base64-encodes a nonempty byte list. `base64` accepts
nonempty base64 data and requires a MIME type without parameters. Filenames are
optional. File IDs belong to their issuing provider and cannot be moved between
providers. Your application obtains the ID separately.

## Provider support

- OpenAI Responses accepts URLs, inline data, and file IDs with
  `provider: 'openai'`.
- Anthropic Messages accepts URLs, inline PDF, and inline plain text. File IDs
  are blocked until the pinned SDK supports them.
- OpenAI Chat Completions and the OpenRouter adapter reject document inputs.

These are adapter contracts tested offline. The provider and selected model can
impose additional format and size limits. See [Anthropic Messages](anthropic.md)
and [OpenRouter](openrouter.md).

## History and retention

`RunStore` retains inline document bytes and URLs as part of stored messages.
Authorized history clients receive those values, including signed URLs. Your
application is responsible for retention, access controls, and payload limits.
Persistence across restarts depends on the configured store. A signed URL may
expire even if the history still contains it.

For large inputs, prefer an application-managed URL or a supported provider file
ID. Base64 increases payload size. The example Serverpod configuration has a
512 KB global request limit and the chat route has its own 1 MB limit; the
smaller applicable limit wins. Confirm your deployment's configured limits.

Run `dart --enable-asserts run examples/review_cases/documents.dart` from the
workspace root to exercise the offline request and history contracts without a
provider key. No actual PDF parsing or model acceptance is proved by that fixture.

Provider format rules: [OpenAI file inputs](https://developers.openai.com/api/docs/guides/file-inputs)
and [Anthropic PDF inputs](https://platform.claude.com/docs/en/build-with-claude/pdf-support).
