import 'dart:convert';
import 'model.dart';
import 'storage.dart';

/// Convert authoritative storage to the TanStack chat hydration response.
JsonObject chatHydration(JsonObject? state) {
  if (state == null) {
    return {'messages': <Object?>[], 'activeRun': null, 'interrupts': null};
  }
  final messages = [
    for (final raw in state['messages'] as List? ?? [])
      ChatMessage.fromJson(Map<String, Object?>.from(raw as Map)),
  ];
  final results = {
    for (final message in messages)
      if (message.role == MessageRole.tool) message.toolCallId: message.text,
  };
  final events = (state['events'] as List? ?? []).cast<Map<Object?, Object?>>();
  final terminals = events.where((e) => e['type'] == 'RUN_FINISHED');
  final outcome = terminals.isEmpty ? null : terminals.last['outcome'];
  final pending = outcome is Map ? outcome['interrupts'] : null;
  return {
    'messages': [
      for (final message in messages)
        if (message.role != MessageRole.tool)
          {
            'id': message.id,
            'role': message.role.name,
            'parts': [
              if (message.structuredOutput case final output?)
                {
                  'type': 'structured-output',
                  'status': 'complete',
                  'data': output.data,
                  'partial': output.data,
                  'raw': output.raw,
                },
              for (final part in message.content)
                if (message.structuredOutput == null || part is! TextPart)
                  switch (part) {
                    TextPart(:final text) => {'type': 'text', 'content': text},
                    ImagePart(:final url) => {
                      'type': 'image',
                      'source': {'type': 'url', 'value': url},
                    },
                    DocumentPart part => {
                      'type': 'document',
                      'source': part.sourceJson,
                      if (part.filename != null)
                        'metadata': {'filename': part.filename},
                    },
                    FilePart(:final fileId) => {
                      'type': 'document',
                      'source': {'type': 'file', 'value': fileId},
                    },
                    AudioPart(:final data, :final format) => {
                      'type': 'audio',
                      'source': {
                        'type': 'data',
                        'value': data,
                        'mimeType': format == 'mp3'
                            ? 'audio/mpeg'
                            : 'audio/$format',
                      },
                    },
                    VideoPart(:final url) => {
                      'type': 'video',
                      'source': {'type': 'url', 'value': url},
                    },
                  },
              for (final call in message.toolCalls)
                {
                  'type': 'tool-call',
                  'id': call.id,
                  'name': call.name,
                  'arguments': jsonEncode(call.arguments),
                  'input': call.arguments,
                  'state': results.containsKey(call.id)
                      ? 'output-available'
                      : 'input-available',
                  if (results.containsKey(call.id))
                    'output': jsonDecode(results[call.id]!),
                },
            ],
          },
    ],
    'activeRun': state['status'] == RunStatus.running.name
        ? {'runId': state['runId']}
        : null,
    'interrupts':
        state['status'] == RunStatus.interrupted.name && pending != null
        ? {'runId': state['runId'], 'pending': pending}
        : null,
  };
}
