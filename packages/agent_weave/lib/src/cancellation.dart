import 'dart:async';

/// A caller-owned cancellation signal. Never reuse a cancelled signal.
final class CancellationToken {
  final Completer<void> _cancelled = Completer<void>();
  final _listeners = <void Function()>{};

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  /// A single cancellation event, including for a listener attached after cancel.
  /// Cancel the subscription to release its listener when a request finishes.
  Stream<void> get onCancelled {
    late final StreamController<void> controller;
    void emit() {
      controller.add(null);
      unawaited(controller.close());
    }

    controller = StreamController<void>(
      onListen: () {
        if (isCancelled) {
          emit();
        } else {
          _listeners.add(emit);
        }
      },
      onCancel: () {
        _listeners.remove(emit);
      },
    );
    return controller.stream;
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    for (final listener in _listeners.toList()) {
      listener();
    }
    _listeners.clear();
  }

  void throwIfCancelled() {
    if (isCancelled) throw const RunCancelled();
  }
}

final class RunCancelled implements Exception {
  const RunCancelled();
  @override
  String toString() => 'The run was cancelled.';
}
