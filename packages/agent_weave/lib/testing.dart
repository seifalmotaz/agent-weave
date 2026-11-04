/// Deterministic providers for application tests. No network or test dependency.
library;

import 'agent_weave.dart';

final class ScriptedChatModel implements ChatModel {
  final List<List<ModelEvent>> _steps;
  final List<ModelRequest> _requests = [];
  int _step = 0;
  @override
  final ModelCapabilities capabilities;

  ScriptedChatModel({
    required Iterable<Iterable<ModelEvent>> steps,
    this.capabilities = const ModelCapabilities(),
  }) : _steps = List.unmodifiable(
         steps.map((step) => List<ModelEvent>.unmodifiable(step)),
       );

  List<ModelRequest> get requests => List.unmodifiable(_requests);
  int get remainingSteps => _steps.length - _step;

  @override
  Stream<ModelEvent> stream(
    ModelRequest request, {
    required CancellationToken cancellation,
  }) async* {
    cancellation.throwIfCancelled();
    if (_step == _steps.length) {
      throw StateError(
        'ScriptedChatModel exhausted after $_step invocations. Add another response step.',
      );
    }
    _requests.add(request);
    for (final event in _steps[_step++]) {
      cancellation.throwIfCancelled();
      yield event;
    }
  }
}
