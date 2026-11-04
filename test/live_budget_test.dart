import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import '../tool/live_budget.dart';

void main() {
  late Directory temporary;
  late File ledger;
  setUp(() {
    temporary = Directory.systemTemp.createTempSync('agent-weave-budget-');
    ledger = File('${temporary.path}/ledger.json');
  });
  tearDown(() => temporary.deleteSync(recursive: true));
  http.Request request([
    String path = '/v1/responses',
    String model = 'gpt-5.4-nano',
  ]) => http.Request('POST', Uri.parse('https://api.openai.com$path'))
    ..body = jsonEncode({
      'model': model,
      'max_output_tokens': 128,
      'input': 'Hello',
    });
  test(
    'budget persists before dispatch and blocks requests after its cumulative ceiling',
    () async {
      var dispatched = 0;
      for (
        var i = 0;
        i < BudgetClient.limitMicros ~/ BudgetClient.reservationMicros;
        i++
      ) {
        final client = BudgetClient(
          MockClient((_) async {
            dispatched++;
            return http.Response('{}', 200);
          }),
          ledger,
        );
        await client.send(request());
        client.close();
      }
      expect(
        dispatched,
        BudgetClient.limitMicros ~/ BudgetClient.reservationMicros,
      );
      final client = BudgetClient(
        MockClient((_) async {
          dispatched++;
          return http.Response('{}', 200);
        }),
        ledger,
      );
      await expectLater(client.send(request()), throwsStateError);
      expect(
        dispatched,
        BudgetClient.limitMicros ~/ BudgetClient.reservationMicros,
      );
      expect(
        (jsonDecode(ledger.readAsStringSync()) as Map)['reservedMicros'],
        BudgetClient.limitMicros,
      );
    },
  );
  for (final (path, model) in [
    ('/v1/videos', 'gpt-5.4-nano'),
    ('/v1/responses', 'unapproved'),
  ]) {
    test('rejects unbounded endpoint/model $path $model', () async {
      final client = BudgetClient(
        MockClient((_) async => fail('Must not dispatch')),
        ledger,
      );
      await expectLater(client.send(request(path, model)), throwsStateError);
      expect(ledger.existsSync(), isFalse);
    });
  }
  test(
    'reserves failed requests conservatively without refunding them',
    () async {
      final client = BudgetClient(
        MockClient((_) async => throw const SocketException('offline')),
        ledger,
      );
      await expectLater(
        client.send(request()),
        throwsA(isA<SocketException>()),
      );
      expect(
        (jsonDecode(ledger.readAsStringSync()) as Map)['reservedMicros'],
        250000,
      );
    },
  );
}
