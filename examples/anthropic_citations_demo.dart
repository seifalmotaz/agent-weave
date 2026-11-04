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
