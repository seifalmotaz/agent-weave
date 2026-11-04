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

  /// Wait for an already-started future or stop waiting when cancelled.
  ///
  /// Cancellation does not stop the underlying operation. Its eventual error is
  /// consumed if it finishes after this wait has been cancelled.
  Future<T> waitFor<T>(Future<T> future) async {
    final result = Completer<T>();
    void cancelled() {
      if (!result.isCompleted) result.completeError(const RunCancelled());
    }

    future.then<void>(
      (value) {
        if (!result.isCompleted) result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    if (isCancelled) {
      cancelled();
    } else {
      _listeners.add(cancelled);
    }
    try {
      final value = await result.future;
      throwIfCancelled();
      return value;
    } catch (_) {
      throwIfCancelled();
      rethrow;
    } finally {
      _listeners.remove(cancelled);
    }
  }

  /// Bind one stream invocation to this signal without cancelling its siblings.
  Stream<T> bindStream<T>(
    Stream<T> Function(CancellationToken child) create, {
    bool Function(Object)? isCancellationError,
  }) {
    final child = CancellationToken();
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    var active = true;
    void cancelChild() {
      if (active) child.cancel();
    }

    void detach() => _listeners.remove(cancelChild);
    controller = StreamController<T>(
      onListen: () {
        if (isCancelled) {
          child.cancel();
        } else {
          _listeners.add(cancelChild);
        }
        try {
          subscription = create(child).listen(
            controller.add,
            onError: (Object error, StackTrace stack) {
              if (active) controller.addError(error, stack);
            },
            onDone: () {
              active = false;
              detach();
              controller.close();
            },
          );
        } catch (error, stack) {
          active = false;
          detach();
          controller.addError(error, stack);
          controller.close();
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        active = false;
        child.cancel();
        detach();
        try {
          await subscription?.cancel();
        } catch (error) {
          if (error is! RunCancelled &&
              !(isCancellationError?.call(error) ?? false)) {
            rethrow;
          }
        }
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
