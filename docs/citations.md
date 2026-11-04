# Cite source documents

Enable Anthropic document citations and read typed attribution from each
assistant message. The adapter normalizes all five citation variants in the
pinned Messages contract. Other provider adapters do not yet normalize citations.

## Run a document question

Set `ANTHROPIC_API_KEY` and `ANTHROPIC_MODEL` in your backend environment, then
run `dart run examples/anthropic_citations_demo.dart`. Choose a model that supports
document citations. This command makes a billable request; ordinary repository
checks do not run it.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:agent_weave/agent_weave.dart';
import 'package:agent_weave_anthropic/agent_weave_anthropic.dart' as anthropic;

Future<void> main() async {
  final key = Platform.environment['ANTHROPIC_API_KEY'];
  final model = Platform.environment['ANTHROPIC_MODEL'];
  if (key == null || key.isEmpty || model == null || model.isEmpty) {
    throw StateError('Set ANTHROPIC_API_KEY and ANTHROPIC_MODEL.');
  }
  final client = anthropic.AnthropicNativeClient.withApiKey(apiKey: key);
  try {
    final result = await generateText(
      model: client.chatModel(model: model, citations: true),
      messages: [
        ChatMessage(
          id: 'question',
          role: MessageRole.user,
          content: [
            DocumentPart.bytes(
              utf8.encode('Annual leave requests need manager approval.'),
              mimeType: 'text/plain',
              filename: 'Leave policy',
            ),
            const TextPart('Who approves annual leave? Cite the policy.'),
          ],
        ),
      ],
    );
    for (final message in result.responseMessages) {
      if (message.role != MessageRole.assistant) continue;
      print(message.text);
      for (final citation in message.citations) {
        final claim = message.text.substring(citation.start, citation.end);
        final source = switch (citation.source) {
          DocumentCitationSource(:final index, :final location) =>
            'document $index, ${location.unit.name} '
                '[${location.start}, ${location.end})',
          UrlCitationSource(:final url) => url,
          SearchResultCitationSource(:final source) => source,
        };
        print('$claim ← $source');
      }
    }
  } finally {
    client.close();
  }
}
```

`citations: true` enables citations on every direct user document across the
conversation history. URL, inline PDF, inline UTF-8 text and Anthropic file-ID
documents use the existing `DocumentPart` factories. The typed SDK configuration
path still cannot decode file-ID sources; use `AnthropicNativeClient` for them.
Custom-content documents and search-result input blocks currently require the
separate raw native API.

Anthropic requires citations on all documents or none. It also rejects document
citations combined with `output_config.format` or the deprecated `output_format`.
AgentWeave checks both rules before dispatch, including formats supplied through
`configure`. Do not combine this option with `generateObject` or an agent output
schema. See [Anthropic's citation contract](https://platform.claude.com/docs/en/build-with-claude/citations).

## Render the answer and its sources

`ChatMessage.citations` is an immutable list. Each `TextCitation` contains
`start` and exclusive `end` offsets into that message's complete `text`, measured
in UTF-16 code units. These are the same offsets used by Dart `String.substring`
and JavaScript `String.slice`. A valid range cannot split a surrogate pair.

`citedText` is the source quotation. It need not match the generated answer span.
Anthropic attaches citations to a complete response text block, so several
citations can share the same answer range. Their order and duplicates are
preserved. The adapter emits them when that block closes, after any remaining
text deltas, and rejects interleaved text blocks that cannot form a contiguous
answer range.

Match `citation.source` to render its reference:

| Dart source | Location |
| --- | --- |
| `DocumentCitationSource` | `index` identifies a document across all request messages. `location` retains character, page or block coordinates. |
| `UrlCitationSource` | `url` and optional `title` identify a web result. |
| `SearchResultCitationSource` | `index` identifies a search-result input, counted separately from documents. `source` is an identifier and need not be a URL. |

Source character and block locations are zero-based. Pages are one-based.
Every source range has an exclusive end. Source coordinates retain the
provider's units; they are not converted to UTF-16 answer offsets. Do not locate
answer spans by searching for `citedText`.

Citation source text, titles and links are application content. The SDK validates
HTTP(S) URL syntax and rejects embedded user credentials, but does not fetch
links, detect secrets in query strings or decide what your users may read.
Apply the same document and link policy as the rest of your application.

## Stream and restore attribution

Native model consumers receive `CitationReady(citation)` alongside `TextDelta`.
`AiAgent.run()` emits this additive protocol extension after the cited text:

```json
{
  "type": "CUSTOM",
  "name": "agent_weave:citation",
  "value": {
    "messageId": "assistant-message-id",
    "citationIndex": 0,
    "citation": {
      "start": 0,
      "end": 6,
      "source": {
        "type": "document",
        "index": 0,
        "location": {"unit": "pages", "start": 1, "end": 2}
      }
    }
  }
}
```

Upsert incremental citations by `(messageId, citationIndex)` in your renderer.
The zero-based index is the annotation position in that message. Replayed events
reuse it, while two identical legitimate citations have distinct indexes. Do not
deduplicate citations by their value. On a final message
snapshot or history hydration, replace that message's attribution with
`message.metadata.agent_weave.citations`. The entries use `TextCitation.toJson()`
and can be decoded with `TextCitation.fromJson()` in Dart. Standard TanStack
clients retain this metadata through snapshots and restoration; an application
must render it. Generic clients may ignore the CUSTOM event until the snapshot.

Closed text-block citations remain attached to retained partial text after a
later failure or cancellation. An unfinished block does not produce a citation.
A citation does not prove the whole run succeeded. Display the run status too.

Only the public projection enters events and hydration. Provider file IDs,
encrypted citation indexes and unknown native fields stay in private replay
state. Original response blocks remain unchanged in storage. Continuation input
omits the known response-only document `file_id` while retaining the web-search
`encrypted_index` needed by the provider. Unknown citation types fail explicitly
instead of exposing an unreviewed payload.

## Add document context or cache control

The native `configure` callback may add `context`, `citations` and `cache_control`
to direct user document blocks. Return copied maps and lists; the supplied body
is immutable. Canonical document source and title remain protected. With
`citations: true`, configuration cannot disable citations. Without the flag,
per-document configuration must still enable all documents or none. Keep the
configuration deterministic when recreating an agent.

The model-level flag covers the ordinary use case. Native configuration and raw
Messages access are separate contracts; forwarding an option does not establish
live cache hits or complete nested provider support.

## Reproduce the offline checks

```sh
dart test packages/agent_weave/test/citations_test.dart
dart test packages/agent_weave_anthropic/test/citations_test.dart
dart run examples/review_cases/anthropic_citations.dart
dart run examples/review_cases/citations_client.dart
dart run tool/check.dart
```

The independent consumer uses loopback HTTP. Additional checks exercise both
clients and real PostgreSQL approval recreation. These fixtures do not contact
Anthropic or prove model availability, citation quality or Flutter rendering.
