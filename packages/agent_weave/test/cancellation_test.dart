import 'package:agent_weave/agent_weave.dart';
import 'package:test/test.dart';

void main() {
  test(
    'cancellation is idempotent for both Future and active event listeners',
    () async {
      final token = CancellationToken();
      var first = 0, second = 0;
      final one = token.onCancelled.listen((_) => first++);
      final two = token.onCancelled.listen((_) => second++);
      final finished = Future.wait([
        one.asFuture<void>(),
        two.asFuture<void>(),
      ]);
      token.cancel();
      token.cancel();
      await token.whenCancelled;
      await finished;
      expect([first, second], [1, 1]);
      expect(token.isCancelled, true);
      expect(token.throwIfCancelled, throwsA(isA<RunCancelled>()));
    },
  );
  test(
    'late listeners receive cancellation even if stream was obtained earlier',
    () async {
      final token = CancellationToken();
      final before = token.onCancelled;
      token.cancel();
      expect(await before.toList(), hasLength(1));
      expect(await token.onCancelled.toList(), hasLength(1));
    },
  );
  test(
    'disposing one listener leaves the other listener and parent state intact',
    () async {
      final token = CancellationToken();
      var disposed = 0;
      final subscription = token.onCancelled.listen((_) => disposed++);
      await subscription.cancel();
      expect(token.isCancelled, false);
      final active = token.onCancelled.toList();
      token.cancel();
      expect(await active, hasLength(1));
      expect(disposed, 0);
    },
  );
}
