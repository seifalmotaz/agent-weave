import 'dart:convert';
import 'dart:io';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;

Future<void> main() async {
  final values = <String, Map<String, Object?>>{
    'FileSearchTool': {
      'type': 'file_search',
      'vector_store_ids': ['vs'],
      'filters': {'type': 'eq', 'key': 'category', 'value': 'manual'},
      'max_num_results': 4,
      'ranking_options': {
        'ranker': 'auto',
        'score_threshold': 0.5,
        'hybrid_search': {'embedding_weight': 0.7, 'text_weight': 0.3},
      },
    },
    'WebSearchTool': {
      'type': 'web_search',
      'external_web_access': true,
      'filters': {
        'allowed_domains': ['example.com'],
      },
      'search_context_size': 'high',
      'user_location': {
        'type': 'approximate',
        'city': 'Cairo',
        'country': 'EG',
        'region': 'Cairo',
        'timezone': 'Africa/Cairo',
      },
    },
    'WebSearchPreviewTool': {
      'type': 'web_search_preview',
      'search_content_types': ['text'],
      'search_context_size': 'high',
      'user_location': {
        'type': 'approximate',
        'city': 'Cairo',
        'country': 'EG',
        'region': 'Cairo',
        'timezone': 'Africa/Cairo',
      },
    },
    'ToolSearchTool': {
      'type': 'tool_search',
      'description': 'Search tools',
      'execution': 'server',
      'parameters': {'type': 'object'},
    },
    'Tool.CodeInterpreter': {
      'type': 'code_interpreter',
      'allowed_callers': ['direct'],
      'container': {
        'type': 'auto',
        'file_ids': ['file'],
        'memory_limit': '4g',
        'network_policy': {'type': 'disabled'},
      },
    },
    'Tool.ImageGeneration': {
      'type': 'image_generation',
      'action': 'edit',
      'background': 'transparent',
      'input_fidelity': 'high',
      'input_image_mask': {
        'file_id': 'mask',
        'image_url': 'data:image/png;base64,bWFzaw==',
      },
      'model': 'gpt-image-1.5',
      'moderation': 'low',
      'output_compression': 75,
      'output_format': 'webp',
      'partial_images': 2,
      'quality': 'high',
      'size': '1024x1024',
    },
  };
  final serialized = {
    for (final entry in values.entries)
      entry.key: api.OpenAIHostedTool.fromJson(entry.value).definition,
  };
  await File(
    '.dart_tool/openai-hosted-options.json',
  ).writeAsString(jsonEncode(serialized));
}
