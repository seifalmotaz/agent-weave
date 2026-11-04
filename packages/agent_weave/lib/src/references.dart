import 'citations.dart';
import 'model.dart' show JsonObject;

/// Opaque coordinates reported by a provider, not Dart string offsets.
sealed class ReferencePosition {
  const ReferencePosition();
  JsonObject toJson();
  factory ReferencePosition.fromJson(JsonObject json) {
    try {
      return switch (json['type']) {
        'text_range' => ProviderTextRange(
          start: json['start'] as int,
          end: json['end'] as int,
        ),
        'text_position' => ProviderTextPosition(json['index'] as int),
        'file_list' => FileListPosition(json['index'] as int),
        _ => throw const FormatException('Unknown reference position.'),
      };
    } catch (_) {
      throw const FormatException('Invalid reference position.');
    }
  }
}

/// Provider-reported endpoints; their unit and end semantics are provider-defined.
final class ProviderTextRange extends ReferencePosition {
  final int start;
  final int end;
  ProviderTextRange({required this.start, required this.end}) {
    if (start < 0 || end < start) {
      throw const FormatException('Invalid provider range.');
    }
  }
  @override
  JsonObject toJson() => {'type': 'text_range', 'start': start, 'end': end};
}

/// A provider-reported insertion point, with provider-defined units.
final class ProviderTextPosition extends ReferencePosition {
  final int index;
  ProviderTextPosition(this.index) {
    if (index < 0) throw const FormatException('Invalid provider position.');
  }
  @override
  JsonObject toJson() => {'type': 'text_position', 'index': index};
}

/// A file-list ordinal, not a text offset.
final class FileListPosition extends ReferencePosition {
  final int index;
  FileListPosition(this.index) {
    if (index < 0) throw const FormatException('Invalid file-list position.');
  }
  @override
  JsonObject toJson() => {'type': 'file_list', 'index': index};
}

/// A reference attached to an enclosing UTF-16 output segment, not a highlight.
/// The provider position is opaque and is never used to slice text.
final class OutputReference {
  final String provider;
  final CitationSource source;
  final int partStart;
  final int partEnd;
  final ReferencePosition position;
  OutputReference({
    required this.provider,
    required this.source,
    required this.partStart,
    required this.partEnd,
    required this.position,
  }) {
    if (provider.trim().isEmpty ||
        partStart < 0 ||
        partEnd < partStart ||
        (source is FileCitationSource &&
            (source as FileCitationSource).provider != provider)) {
      throw const FormatException('Invalid output reference.');
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
    final dangling =
        partEnd == text.length &&
        partEnd > 0 &&
        text.codeUnitAt(partEnd - 1) >= 0xD800 &&
        text.codeUnitAt(partEnd - 1) <= 0xDBFF;
    if (partEnd > text.length ||
        split(partStart) ||
        split(partEnd) ||
        dangling) {
      throw const FormatException('Invalid reference text boundaries.');
    }
  }

  JsonObject toJson() => {
    'provider': provider,
    'source': source.toJson(),
    'partStart': partStart,
    'partEnd': partEnd,
    'position': position.toJson(),
  };
  factory OutputReference.fromJson(JsonObject json) {
    try {
      return OutputReference(
        provider: json['provider'] as String,
        source: CitationSource.fromJson(
          Map<String, Object?>.from(json['source'] as Map),
        ),
        partStart: json['partStart'] as int,
        partEnd: json['partEnd'] as int,
        position: ReferencePosition.fromJson(
          Map<String, Object?>.from(json['position'] as Map),
        ),
      );
    } catch (_) {
      throw const FormatException('Invalid output reference.');
    }
  }
}
