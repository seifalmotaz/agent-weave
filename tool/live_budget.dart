import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Test-only cost guard. Reservations are deliberately never refunded.
/// A fixed request allowlist excludes jobs, storage, tools, and live sessions.
final class BudgetClient extends http.BaseClient {
  final http.Client inner;
  final File ledger;
  static const reservationMicros = 250000;
  static const limitMicros = 4000000;
  BudgetClient(this.inner, this.ledger);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != 'https://api.openai.com' ||
        request.method != 'POST' ||
        request is! http.Request ||
        request.bodyBytes.length > 16384) {
      throw StateError('Live test request is outside the bounded allowlist.');
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    var reservation = reservationMicros;
    if (request.url.path == '/v1/embeddings') {
      if (body['model'] != 'text-embedding-3-small') {
        throw StateError('Unapproved model.');
      }
    } else if ([
      '/v1/responses',
      '/v1/chat/completions',
    ].contains(request.url.path)) {
      final tokens = body['max_output_tokens'] ?? body['max_completion_tokens'];
      if (body['model'] != 'gpt-5.4-nano' ||
          tokens is! int ||
          tokens < 1 ||
          tokens > 512) {
        throw StateError('Unapproved model or output limit.');
      }
      for (final raw in body['tools'] as List? ?? []) {
        if ((raw as Map)['type'] != 'function') {
          throw StateError('Billable hosted tools are disabled.');
        }
      }
      if (body['background'] == true) {
        throw StateError('Background work is disabled.');
      }
    } else if (request.url.path == '/v1/images/generations') {
      if (body['model'] != 'gpt-image-2' ||
          body['n'] != 1 ||
          body['size'] != '1024x1024' ||
          body['quality'] != 'low' ||
          (body['prompt'] as String).length > 100) {
        throw StateError('Unapproved image request.');
      }
      reservation = 1000000;
    } else if (request.url.path == '/v1/audio/speech') {
      if (body['model'] != 'gpt-4o-mini-tts' ||
          (body['input'] as String).length > 30 ||
          body['response_format'] != 'wav') {
        throw StateError('Unapproved speech request.');
      }
    } else {
      throw StateError('Unapproved endpoint.');
    }
    ledger.parent.createSync(recursive: true);
    final file = ledger.openSync(mode: FileMode.append);
    try {
      file.lockSync(FileLock.exclusive);
      file.setPositionSync(0);
      final previous = file.lengthSync() == 0
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(file.readSync(file.lengthSync())))
                as Map<String, dynamic>;
      final reserved = previous['reservedMicros'] as int? ?? 0;
      if (reserved + reservation > limitMicros) {
        throw StateError('Live test budget exhausted. No request was sent.');
      }
      final entries = <Object?>[
        ...?previous['requests'] as List?,
        {
          'endpoint': request.url.path,
          'model': body['model'],
          'reservedMicros': reservation,
          'at': DateTime.now().toUtc().toIso8601String(),
        },
      ];
      file.truncateSync(0);
      file.setPositionSync(0);
      file.writeStringSync(
        jsonEncode({
          'limitMicros': limitMicros,
          'reservedMicros': reserved + reservation,
          'requests': entries,
        }),
      );
      file.flushSync();
    } finally {
      file.unlockSync();
      file.closeSync();
    }
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}
