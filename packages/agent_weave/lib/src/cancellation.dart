import 'dart:async';

/// A caller-owned cancellation signal. Never reuse a cancelled signal.
final class CancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (!isCancelled) _cancelled.complete();
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
