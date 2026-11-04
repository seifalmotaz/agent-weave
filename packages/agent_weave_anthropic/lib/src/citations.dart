import 'package:agent_weave/agent_weave.dart';

/// Projects a native citation to the fields safe for public agent output.
TextCitation anthropicTextCitation(
  Map<String, Object?> citation, {
  required int start,
  required int end,
}) {
  try {
    CitationLocation location(CitationUnit unit, String first, String last) =>
        CitationLocation(
          unit: unit,
          start: citation[first] as int,
          end: citation[last] as int,
        );
    final type = citation['type'];
    final CitationSource source = switch (type) {
      'char_location' ||
      'page_location' ||
      'content_block_location' => DocumentCitationSource(
        index: citation['document_index'] as int,
        title: citation['document_title'] as String?,
        location: switch (type) {
          'char_location' => location(
            CitationUnit.characters,
            'start_char_index',
            'end_char_index',
          ),
          'page_location' => location(
            CitationUnit.pages,
            'start_page_number',
            'end_page_number',
          ),
          _ => location(
            CitationUnit.blocks,
            'start_block_index',
            'end_block_index',
          ),
        },
      ),
      'web_search_result_location' => UrlCitationSource(
        citation['url'] as String,
        title: citation['title'] as String?,
      ),
      'search_result_location' => SearchResultCitationSource(
        index: citation['search_result_index'] as int,
        source: citation['source'] as String,
        title: citation['title'] as String?,
        location: location(
          CitationUnit.blocks,
          'start_block_index',
          'end_block_index',
        ),
      ),
      _ => throw UnsupportedError('Unsupported Anthropic citation type: $type'),
    };
    return TextCitation(
      start: start,
      end: end,
      source: source,
      citedText: citation['cited_text'] as String,
    );
  } on TypeError {
    throw const FormatException('Malformed Anthropic citation.');
  }
}

/// Build an input representation without response-only file identifiers.
Map<String, dynamic> anthropicReplayBlock(JsonObject block) {
  final result = Map<String, dynamic>.from(block);
  if (block['type'] == 'text' && block['citations'] is List) {
    result['citations'] = [
      for (final value in block['citations'] as List)
        () {
          final citation = Map<String, dynamic>.from(value as Map);
          if ({
            'char_location',
            'page_location',
            'content_block_location',
          }.contains(citation['type'])) {
            citation.remove('file_id');
          }
          return citation;
        }(),
    ];
  }
  return result;
}
