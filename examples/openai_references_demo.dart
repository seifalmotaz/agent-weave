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
        authorityBindingId: 'example-authority',
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
