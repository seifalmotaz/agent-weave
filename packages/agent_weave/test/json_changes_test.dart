import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';

void main() {
  test('numeric equality preserves exact mixed and boundary values', () {
    expect(jsonEquals(1, 1.0), isTrue);
    expect(jsonEquals(1.5, 1), isFalse);
    expect(jsonEquals(9007199254740993, 9007199254740992.0), isFalse);
    expect(jsonEquals(9007199254740992.0, 9007199254740993), isFalse);
    expect(jsonEquals(9223372036854775807, 9223372036854775808.0), isFalse);
    expect(jsonEquals(-9223372036854775808, -9223372036854775808.0), isTrue);
    expect(jsonEquals(1, double.infinity), isFalse);
    expect(jsonEquals(1, double.nan), isFalse);
  });

  test(
    'typed changes preserve opaque fields, rows and immutable snapshots',
    () {
      final raw = <String, Object?>{
        'known': 1,
        'opaque': {'secret': true},
        'rows': [
          {'value': 1, 'opaque': 'x'},
        ],
      };
      final result = applyJsonChanges(
        raw,
        {
          'known': 1,
          'rows': [
            {'value': 1},
          ],
        },
        {
          'known': 2,
          'rows': [
            {'value': 2},
          ],
        },
      );
      expect(result, {
        'known': 2,
        'opaque': {'secret': true},
        'rows': [
          {'value': 2, 'opaque': 'x'},
        ],
      });
      (raw['opaque'] as Map)['secret'] = false;
      expect((result['opaque'] as Map)['secret'], true);
      expect(
        () => ((result['rows'] as List).single as Map)['value'] = 3,
        throwsUnsupportedError,
      );
    },
  );
  test(
    'unchanged SDK defaults do not inject null fields into native requests',
    () {
      expect(
        applyJsonChanges(
          {'value': 1, 'private': true},
          {'value': 1, 'default': false},
          {'value': 2, 'default': false},
        ),
        {'value': 2, 'private': true},
      );
      expect(
        applyJsonChanges({'value': 1}, {'value': 1, 'default': false}, {
          'value': 1,
          'default': true,
        }),
        {'value': 1, 'default': true},
      );
    },
  );
  test('deletion and resized arrays apply explicit typed replacements', () {
    expect(
      applyJsonChanges(
        {
          'value': 1,
          'private': true,
          'rows': [
            {'secret': 1},
          ],
        },
        {
          'value': 1,
          'rows': [<String, Object?>{}],
        },
        {'rows': []},
      ),
      {'private': true, 'rows': <Object?>[]},
    );
  });
  test(
    'Dart integer changes do not collapse at JavaScript precision limits',
    () {
      final value = applyJsonChanges(
        {'value': 9007199254740992},
        {'value': 9007199254740992},
        {'value': 9007199254740993},
      );
      expect(value['value'], 9007199254740993);
      expect(jsonEquals(9007199254740992, 9007199254740993), false);
      expect(
        jsonEquals(
          {
            'b': 2,
            'a': [1.0],
          },
          {
            'a': [1],
            'b': 2.0,
          },
        ),
        true,
      );
    },
  );
}
