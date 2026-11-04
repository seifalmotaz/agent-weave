import 'dart:async';

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
  test(
    'bound streams isolate subscription cancellation and share parent cancellation',
    () async {
      final parent = CancellationToken();
      final children = <CancellationToken>[];
      Stream<int> blocked(CancellationToken child) async* {
        children.add(child);
        await child.whenCancelled;
        child.throwIfCancelled();
      }

      final one = parent.bindStream(blocked).listen(null);
      final two = parent
          .bindStream(blocked)
          .listen(null, onError: (Object _) {});
      await Future<void>.delayed(Duration.zero);
      await one.cancel().timeout(const Duration(seconds: 1));
      expect(parent.isCancelled, isFalse);
      expect(children[0].isCancelled, isTrue);
      expect(children[1].isCancelled, isFalse);
      parent.cancel();
      expect(children[1].isCancelled, isTrue);
      await children[1].whenCancelled.timeout(const Duration(seconds: 1));
      await two.cancel();
    },
  );

  test('synchronous stream creation errors reach the listener', () async {
    final parent = CancellationToken();
    final error = StateError('create');
    await expectLater(
      parent.bindStream<int>((_) => throw error),
      emitsError(same(error)),
    );
    expect(parent.isCancelled, isFalse);
  });
  test(
    'waitFor stops promptly without cancelling the underlying future',
    () async {
      final token = CancellationToken();
      final pending = Completer<int>();
      final wait = token.waitFor(pending.future);
      token.cancel();
      await expectLater(
        wait.timeout(const Duration(seconds: 1)),
        throwsA(isA<RunCancelled>()),
      );
      expect(pending.isCompleted, isFalse);
      pending.complete(42);
      expect(await pending.future, 42);
    },
  );

  test(
    'waitFor handles pre-cancel, success, failure and late errors',
    () async {
      final preCancelled = CancellationToken()..cancel();
      final late = Completer<int>();
      await expectLater(
        preCancelled.waitFor(late.future),
        throwsA(isA<RunCancelled>()),
      );
      late.completeError(StateError('late'));
      await Future<void>.delayed(Duration.zero);
      final active = CancellationToken();
      expect(await active.waitFor(Future.value(7)), 7);
      final error = StateError('failure');
      await expectLater(
        active.waitFor<int>(Future.error(error)),
        throwsA(same(error)),
      );
      expect(active.isCancelled, isFalse);
      final listener = active.onCancelled.toList();
      active.cancel();
      expect(await listener, hasLength(1));
    },
  );
}
