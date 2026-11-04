import 'dart:convert';
import 'dart:io';
import 'package:agent_weave_openai/agent_weave_openai.dart' as api;
import 'package:http/http.dart' as http;
import 'live_budget.dart';

Future<void> main() async {
  final key = Platform.environment['OPENAI_API_KEY'];
  if (key == null) {
    throw StateError('Set OPENAI_API_KEY in the environment.');
  }
  final ledger = File('.dart_tool/live-budget.json');
  final client = api.OpenAIClient(
    config: api.OpenAIConfig(
      authProvider: api.ApiKeyProvider(key),
      timeout: const Duration(seconds: 55),
      retryPolicy: const api.RetryPolicy(maxRetries: 0),
    ),
    httpClient: BudgetClient(http.Client(), ledger),
    streamClientFactory: () => BudgetClient(http.Client(), ledger),
  );
  final report = <String, Object?>{};
  try {
    final image = await api.OpenAIImageModel(client).generate(
      const api.ImageGenerationRequest(
        model: 'gpt-image-2',
        prompt: 'A small solid red square on a white background.',
        n: 1,
        size: api.ImageSize.size1024x1024,
        quality: api.ImageQuality.low,
      ),
    );
    final bytes = base64Decode(image.data.single.b64Json!);
    if (bytes.isEmpty) throw StateError('Empty image result.');
    File('.dart_tool/live-image.png').writeAsBytesSync(bytes);
    report['image'] = {
      'status': 'passed',
      'bytes': bytes.length,
      'usage': image.usage?.toJson(),
    };
    final speech = await api.OpenAISpeechModel(client).speak(
      const api.SpeechRequest(
        model: 'gpt-4o-mini-tts',
        input: 'Hi.',
        voice: api.SpeechVoice.alloy,
        responseFormat: api.SpeechResponseFormat.wav,
      ),
    );
    if (ascii.decode(speech.take(4).toList()) != 'RIFF') {
      throw StateError('Expected WAV audio.');
    }
    report['speech'] = {'status': 'passed', 'bytes': speech.length};
    report['budget'] = jsonDecode(ledger.readAsStringSync());
    File(
      '.dart_tool/live-media-report.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  } catch (error) {
    stderr.writeln(
      'Live media check failed: ${error.runtimeType}. Provider body and key omitted.',
    );
    exitCode = 1;
  } finally {
    client.close();
  }
}
