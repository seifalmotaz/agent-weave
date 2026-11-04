/// Diagnostics must never prevent cleanup or replace the original run failure.
void reportError(
  void Function(Object, StackTrace)? callback,
  Object error,
  StackTrace stack,
) {
  try {
    callback?.call(error, stack);
  } catch (_) {
    // A failing observer cannot change execution or persistence semantics.
  }
}
