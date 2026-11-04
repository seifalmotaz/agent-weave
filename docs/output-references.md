# Read output references

OpenAI references describe URLs, cited files and generated artifacts.
`ChatMessage.references` preserves their distinct positions and enclosing text
segments. Use [text citations](citations.md) when an adapter can supply a verified
UTF-16 answer highlight.

## Run a source-backed answer

Set `OPENAI_API_KEY` and `OPENAI_MODEL`, then run
`dart run examples/openai_references_demo.dart` from the workspace. Choose a model
that supports web search. The command makes a billable request; repository
checks only compile its source.

```dart
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_openai/agent_weave_openai.dart' as openai;

Future<void> main() async {
  final key = Platform.environment['OPENAI_API_KEY'];
  final model = Platform.environment['OPENAI_MODEL'];
  if (key == null || key.isEmpty || model == null || model.isEmpty) {
    throw StateError('Set OPENAI_API_KEY and OPENAI_MODEL.');
  }
  final client = openai.OpenAIClient.withApiKey(key);
  try {
    final result = await generateText(
      model: openai.OpenAIResponsesModel.native(
        client: client,
        model: model,
        hostedTools: [
          openai.OpenAIHostedTool.fromJson({'type': 'web_search'}),
        ],
      ),
      prompt: 'Find the latest stable Dart release and cite its release notes.',
    );
    for (final message in result.responseMessages) {
      if (message.role != MessageRole.assistant) continue;
      print(message.text);
      for (final reference in message.references) {
        final source = switch (reference.source) {
          UrlCitationSource(:final url, :final title) =>
            '${title ?? url}: $url',
          FileCitationSource(:final provider, :final filename) =>
            '$provider file: ${filename ?? 'unnamed'}, resolve on your backend',
          DocumentCitationSource(:final index) => 'Document $index',
          SearchResultCitationSource(:final source) => source,
        };
        print(source);
        print('Reported position: ${reference.position.toJson()}');
      }
    }
  } finally {
    client.close();
  }
}
```

## Choose the right coordinates

Each `OutputReference` contains its provider, typed source, native position and
`partStart`/`partEnd` segment. The segment is an enclosing output-text part in
UTF-16 code units, with an exclusive end. It may be empty. It identifies context,
not the exact cited words. You can read that context with
`message.text.substring(reference.partStart, reference.partEnd)`.

`reference.position` retains the provider's reported values:

| Position | Meaning |
| --- | --- |
| `ProviderTextRange` | Reported start/end values. A zero/zero pair is retained. |
| `ProviderTextPosition` | Reported insertion index in output text. |
| `FileListPosition` | Ordinal in a file list, not a text offset. |

Do not pass these native values to `String.substring`. The reviewed OpenAI
reference does not establish a Unicode unit or a precise end convention. Its
[Code Interpreter example](https://developers.openai.com/api/docs/guides/tools-code-interpreter)
also uses zero/zero coordinates for a generated file. AgentWeave preserves those
values without inventing a highlight or converting the pair into a point.
Synthetic Unicode tests verify the enclosing segment, not the service's indexing
convention.

## Read each OpenAI form

| Native form | Dart source | Position |
| --- | --- | --- |
| Responses `url_citation` | `UrlCitationSource` | `ProviderTextRange` |
| Responses `file_citation` | `FileCitationSource` with filename | `ProviderTextPosition` |
| Responses `container_file_citation` | `FileCitationSource` with container and filename | `ProviderTextRange` |
| Responses `file_path` | `FileCitationSource` without an invented filename | `FileListPosition` |
| Completed Chat `url_citation` | `UrlCitationSource` | `ProviderTextRange` |

The contracts and reviewed declarations are in the
[OpenAI inventory](openai-hosted-inventory.json). Responses uses flat annotation
objects. Completed Chat uses a nested `url_citation` object; an unknown nested
field cannot change the documented annotation kind.

Responses references are emitted after a valid terminal response and stream EOF.
The adapter reconciles annotation-added, content-part and output-item echoes with
terminal output by native indexes. Identical echoes do not add references twice;
two identical annotations at different indexes remain distinct. Null annotation
placeholders do not invent an entry. Conflicting, unknown or malformed entries
fail before local tool execution. Streamed text must match the final text before
the adapter attaches a reference to its enclosing segment.

Raw output and opaque fields remain unchanged in private provider replay.
Only reviewed source and position fields enter public references. Compatible
Responses endpoints do not inherit OpenAI annotation semantics automatically.

## Use completed Chat URL references

Use `OpenAIChatModel(client: client, model: modelId, streamText: false)` when you
need completed Chat annotations. The buffered request retains native response
JSON because the installed SDK's typed Chat decoder drops these annotations.
The existing typed configuration and runtime-owned messages, tools, schema and
limits still apply. The request sends `stream: false` and omits stream-only
usage options. It produces one completed text result with references, rather
than token-by-token delivery.

The default streaming mode accepts an empty annotation list but explicitly
rejects nonempty or malformed streamed Chat annotations. Use buffered Chat or
native Responses for supported references. Native Chat also rejects unknown or
inconsistent finish reasons before tools and permits a final empty-choice usage
event. Provider-specific adapters keep their own protocol rules.

The buffered raw response is private in `openai.chat_completions`. Response-only
Chat annotations are not inserted into subsequent request messages. Other
completed output modes, such as audio and legacy function calls, are not part of
this adapter's reference contract.

## Render and restore references

`ReferenceReady(reference)` is the provider-neutral model event. The runtime
publishes this extension:

```json
{
  "type": "CUSTOM",
  "name": "agent_weave:reference",
  "value": {
    "messageId": "assistant-message",
    "referenceIndex": 0,
    "reference": {
      "provider": "openai",
      "source": {"type": "file", "provider": "openai", "fileId": "file-id"},
      "partStart": 0,
      "partEnd": 0,
      "position": {"type": "file_list", "index": 4}
    }
  }
}
```

Upsert incremental entries by `(messageId, referenceIndex)` to handle replay.
Replace them from `message.metadata.agent_weave.references` on a message snapshot
or history hydration. Decode each JSON entry with `OutputReference.fromJson` in
Dart. Citation and reference arrays can coexist in the same metadata bag. Their
indexes are independent. Applications render the data; a generic TanStack
client retains metadata but does not create source cards for you.

Partial-run metadata remains associated with its retained text. References can
exist on an empty message part, so an empty text string does not imply that no
artifact was produced. A retained reference does not prove the run completed.

## Resolve file handles on the backend

`FileCitationSource` exposes `provider`, `fileId`, optional `containerId` and
optional `filename`. These are intentional public scoped handles, not URLs or
credentials. The `title` getter returns the actual filename when present.
AgentWeave does not manufacture a filename, download a file or host an artifact.

Bind each uploaded or generated file to the authenticated application owner.
Check that ownership and provider before using a backend API client to retrieve
bytes or returning a controlled application URL. A submitted file ID alone is
not authorization. Container files need their matching container context.
Apply the same check when reusing a handle in `DocumentPart.fileId`; the
`openai` provider namespace is shared by references and document input. Do not
assume that a container file ID is an ordinary uploaded-file ID; adapt it through
your backend when the target operation requires a different file resource.

Keep API credentials on the backend. Do not expose an unrestricted file proxy
that accepts arbitrary provider IDs. This SDK does not know your application's
file records or access policy. URL references are also application content;
HTTP(S) validation does not detect secrets in query strings or decide whether
a link is appropriate for a user.

## Reproduce the checks

```sh
dart test packages/agent_weave/test/references_test.dart
dart test packages/agent_weave_openai/test/output_references_test.dart
dart run examples/review_cases/openai_references.dart
dart run examples/review_cases/openai_chat_references.dart
dart run examples/review_cases/citations_client.dart
dart run tool/check.dart
```

Local checks exercise native SDK loopback calls, typed persistence, approvals,
PostgreSQL recreation, both clients and completed-log replay. No live OpenAI
request is needed. Live model acceptance, precise native highlighting, actual
file downloads and Flutter rendering remain unverified.
