import 'model.dart';

sealed class ImageSource {
  const ImageSource();
  JsonObject toJson();
}

final class ImageUrl extends ImageSource {
  final String url;
  const ImageUrl(this.url);
  @override
  JsonObject toJson() => {'url': url};
}

final class ImageBase64 extends ImageSource {
  final String data;
  const ImageBase64(this.data);
  @override
  JsonObject toJson() => {'b64Json': data};
}

final class ImageGeneration {
  final String id;
  final String model;
  final List<ImageSource> images;
  ImageGeneration({
    required this.id,
    required this.model,
    required Iterable<ImageSource> images,
  }) : images = List.unmodifiable(images);
  JsonObject toJson() => {
    'id': id,
    'model': model,
    'images': images.map((image) => image.toJson()).toList(),
  };
}

final class SpeechGeneration {
  final String id;
  final String model;
  final String audio;
  final String format;
  const SpeechGeneration({
    required this.id,
    required this.model,
    required this.audio,
    required this.format,
  });
  JsonObject toJson() => {
    'id': id,
    'model': model,
    'audio': audio,
    'format': format,
  };
}

final class Transcription {
  final String id;
  final String model;
  final String text;
  const Transcription({
    required this.id,
    required this.model,
    required this.text,
  });
  JsonObject toJson() => {'id': id, 'model': model, 'text': text};
}
