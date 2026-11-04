import 'model.dart' show JsonObject;

/// Units for a cited source range. Pages are one-based; other units are zero-based.
enum CitationUnit { characters, pages, blocks }

/// A source range with an inclusive start and exclusive end.
final class CitationLocation {
  final CitationUnit unit;
  final int start;
  final int end;
  CitationLocation({
    required this.unit,
    required this.start,
    required this.end,
  }) {
    if (start < (unit == CitationUnit.pages ? 1 : 0) || end <= start) {
      throw const FormatException('Invalid citation location.');
    }
  }
  JsonObject toJson() => {'unit': unit.name, 'start': start, 'end': end};
  factory CitationLocation.fromJson(JsonObject json) {
    try {
      return CitationLocation(
        unit: CitationUnit.values.byName(json['unit'] as String),
        start: json['start'] as int,
        end: json['end'] as int,
      );
    } catch (_) {
      throw const FormatException('Invalid citation location.');
    }
  }
}

/// A portable source reference. Indexes identify items in the provider request.
sealed class CitationSource {
  const CitationSource();
  String? get title;
  JsonObject toJson();
  factory CitationSource.fromJson(JsonObject json) {
    try {
      return switch (json['type']) {
        'url' => UrlCitationSource(
          json['url'] as String,
          title: json['title'] as String?,
        ),
        'file' => FileCitationSource(
          provider: json['provider'] as String,
          fileId: json['fileId'] as String,
          containerId: json['containerId'] as String?,
          filename: json['filename'] as String?,
        ),
        'document' => DocumentCitationSource(
          index: json['index'] as int,
          location: CitationLocation.fromJson(
            Map<String, Object?>.from(json['location'] as Map),
          ),
          title: json['title'] as String?,
        ),
        'search_result' => SearchResultCitationSource(
          index: json['index'] as int,
          source: json['source'] as String,
          location: CitationLocation.fromJson(
            Map<String, Object?>.from(json['location'] as Map),
          ),
          title: json['title'] as String?,
        ),
        _ => throw const FormatException('Unknown citation source.'),
      };
    } catch (_) {
      throw const FormatException('Invalid citation source.');
    }
  }
}

/// An absolute HTTP(S) URL without credentials. The SDK never fetches it.
final class UrlCitationSource extends CitationSource {
  final String url;
  @override
  final String? title;
  UrlCitationSource(this.url, {this.title}) {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid citation URL.');
    }
  }
  @override
  JsonObject toJson() => {'type': 'url', 'url': url, 'title': ?title};
}

/// A provider-scoped file identifier. Applications must authorize retrieval.
final class FileCitationSource extends CitationSource {
  final String provider;
  final String fileId;
  final String? containerId;
  final String? filename;
  FileCitationSource({
    required this.provider,
    required this.fileId,
    this.containerId,
    this.filename,
  }) {
    if (provider.trim().isEmpty ||
        fileId.trim().isEmpty ||
        (containerId != null && containerId!.trim().isEmpty)) {
      throw const FormatException('Invalid file citation.');
    }
  }
  @override
  String? get title => filename;
  @override
  JsonObject toJson() => {
    'type': 'file',
    'provider': provider,
    'fileId': fileId,
    'containerId': ?containerId,
    'filename': ?filename,
  };
}

/// A location in the document at [index] in the provider request.
final class DocumentCitationSource extends CitationSource {
  final int index;
  final CitationLocation location;
  @override
  final String? title;
  DocumentCitationSource({
    required this.index,
    required this.location,
    this.title,
  }) {
    if (index < 0) throw const FormatException('Invalid citation index.');
  }
  @override
  JsonObject toJson() => {
    'type': 'document',
    'index': index,
    'location': location.toJson(),
    'title': ?title,
  };
}

/// A location in a search result at [index] in the provider request.
final class SearchResultCitationSource extends CitationSource {
  final int index;
  final String source;
  final CitationLocation location;
  @override
  final String? title;
  SearchResultCitationSource({
    required this.index,
    required this.source,
    required this.location,
    this.title,
  }) {
    if (index < 0) throw const FormatException('Invalid citation index.');
  }
  @override
  JsonObject toJson() => {
    'type': 'search_result',
    'index': index,
    'source': source,
    'location': location.toJson(),
    'title': ?title,
  };
}

/// An answer-text range in UTF-16 code units, with an exclusive end.
///
/// [citedText] is a quotation from the source, not necessarily answer text.
/// Source coordinates are represented separately by [CitationLocation].
final class TextCitation {
  final int start;
  final int end;
  final String? citedText;
  final CitationSource source;
  TextCitation({
    required this.start,
    required this.end,
    this.citedText,
    required this.source,
  }) {
    if (start < 0 || end <= start) {
      throw const FormatException('Invalid citation range.');
    }
  }
  void validateFor(String text) {
    bool split(int offset) =>
        offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset - 1) >= 0xD800 &&
        text.codeUnitAt(offset - 1) <= 0xDBFF &&
        text.codeUnitAt(offset) >= 0xDC00 &&
        text.codeUnitAt(offset) <= 0xDFFF;
    final danglingHigh =
        end == text.length &&
        end > 0 &&
        text.codeUnitAt(end - 1) >= 0xD800 &&
        text.codeUnitAt(end - 1) <= 0xDBFF;
    if (end > text.length || split(start) || split(end) || danglingHigh) {
      throw const FormatException('Citation range is outside text boundaries.');
    }
  }

  JsonObject toJson() => {
    'start': start,
    'end': end,
    'citedText': ?citedText,
    'source': source.toJson(),
  };
  factory TextCitation.fromJson(JsonObject json) {
    try {
      return TextCitation(
        start: json['start'] as int,
        end: json['end'] as int,
        citedText: json['citedText'] as String?,
        source: CitationSource.fromJson(
          Map<String, Object?>.from(json['source'] as Map),
        ),
      );
    } catch (_) {
      throw const FormatException('Invalid text citation.');
    }
  }
}
