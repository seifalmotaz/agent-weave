import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:openai_dart/openai_dart.dart' as api;

/// A provider-executed Responses tool, separate from application executors.
/// New native options survive without a typed SDK decoder discarding them.
final class OpenAIHostedTool {
  final JsonObject definition;
  String get type => definition['type'] as String;
  OpenAIHostedTool(api.ResponseTool tool) : this.fromJson(tool.toJson());
  OpenAIHostedTool.fromJson(JsonObject definition)
    : definition = immutableJson(
        jsonDecode(jsonEncode(definition)) as JsonObject,
      ) {
    if (this.definition['type'] is! String ||
        !openAIHostedToolTypes.contains(this.definition['type'])) {
      throw ArgumentError(
        'Expected a supported provider-executed OpenAI tool.',
      );
    }
    if (type == 'file_search') {
      final ids = definition['vector_store_ids'];
      if (ids is! List ||
          ids.isEmpty ||
          ids.any((id) => id is! String || id.isEmpty)) {
        throw ArgumentError('File search requires vector store IDs.');
      }
    }
    if (type == 'code_interpreter') {
      final container = definition['container'];
      if (!((container is String && container.isNotEmpty) ||
          (container is Map && container['type'] == 'auto'))) {
        throw ArgumentError(
          'Code interpreter requires a container ID or auto configuration.',
        );
      }
    }
    if (type == 'tool_search' && definition['execution'] != 'server') {
      throw ArgumentError('Hosted tool search requires execution: server.');
    }
    if (type == 'image_generation') {
      if ((definition['moderation'] != null &&
              !{'auto', 'low'}.contains(definition['moderation'])) ||
          (definition['output_compression'] != null &&
              (definition['output_compression'] is! int ||
                  (definition['output_compression'] as num) < 0 ||
                  (definition['output_compression'] as num) > 100)) ||
          (definition['input_image_mask'] != null &&
              definition['input_image_mask'] is! Map)) {
        throw ArgumentError(
          'Invalid native image options. Use native JSON for fields the pinned SDK misrepresents.',
        );
      }
    }
  }
}

const openAIHostedToolTypes = {
  'web_search',
  'web_search_preview',
  'web_search_preview_2025_03_11',
  'file_search',
  'code_interpreter',
  'image_generation',
  'tool_search',
};
