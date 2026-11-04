import 'dart:convert';
import 'model.dart';

enum RunStatus { running, interrupted, completed, failed, cancelled }

final class RunConflict implements Exception {
  final String message;
  const RunConflict(this.message);
  @override
  String toString() => message;
}

/// Storage implementations must atomically reserve a thread and reject reused
/// run IDs. Persist before publishing events. Never silently steal active runs.
abstract interface class RunStore {
  /// Atomically append a terminal event, checkpoint state, and release the run.
  /// Observers must never see this event before the checkpoint is committed.
  Future<void> complete({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject event,
    required JsonObject state,
  });
  Future<JsonObject> begin({
    required String ownerId,
    required String threadId,
    required String runId,
    String? parentRunId,
  });
  Future<void> save({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject state,
    required bool release,
  });
  Future<JsonObject?> load({required String ownerId, required String threadId});
  Future<String?> threadForRun({
    required String ownerId,
    required String runId,
  });
  Future<void> appendEvent({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject event,
  });
  Future<List<JsonObject>> events({
    required String ownerId,
    required String threadId,
    required String runId,
    int afterSequence = -1,
  });
}

JsonObject copyJson(JsonObject value) =>
    Map<String, Object?>.from(jsonDecode(jsonEncode(value)) as Map);

/// Development storage. A process restart loses all history and reservations.
final class MemoryRunStore implements RunStore {
  final _threads = <(String, String), JsonObject>{};
  final _active = <(String, String), String>{};
  final _runs = <(String, String), String>{};
  final _events = <(String, String, String), List<JsonObject>>{};

  @override
  Future<void> complete({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject event,
    required JsonObject state,
  }) async {
    validateTerminalEvent(event);
    final key = (ownerId, threadId);
    if (_active[key] != runId) {
      throw const RunConflict('Run does not own thread.');
    }
    final journal = _events.putIfAbsent((ownerId, threadId, runId), () => []);
    if (event['sequence'] != journal.length) {
      throw const RunConflict('Event sequence is not contiguous.');
    }
    final eventCopy = copyJson(event);
    final stateCopy = copyJson(state);
    // No await between writes: readers cannot observe a partial commit.
    journal.add(eventCopy);
    _threads[key] = stateCopy;
    _active.remove(key);
  }

  @override
  Future<JsonObject> begin({
    required String ownerId,
    required String threadId,
    required String runId,
    String? parentRunId,
  }) async {
    final key = (ownerId, threadId);
    if (_active.containsKey(key)) throw const RunConflict('Thread is busy.');
    if (_runs.containsKey((ownerId, runId))) {
      throw const RunConflict('Run identifier has already been used.');
    }
    final previous = _threads[key];
    if (previous?['status'] == 'interrupted' &&
        parentRunId != previous?['runId']) {
      throw const RunConflict(
        'Resume must identify the interrupted parent run.',
      );
    }
    if (parentRunId != null && previous?['runId'] != parentRunId) {
      throw const RunConflict('Parent run does not match thread history.');
    }
    _active[key] = runId;
    _runs[(ownerId, runId)] = threadId;
    return copyJson(previous ?? {});
  }

  @override
  Future<void> save({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject state,
    required bool release,
  }) async {
    final key = (ownerId, threadId);
    if (_active[key] != runId) {
      throw const RunConflict('Run does not own thread.');
    }
    _threads[key] = copyJson(state);
    if (release) _active.remove(key);
  }

  @override
  Future<JsonObject?> load({
    required String ownerId,
    required String threadId,
  }) async {
    final state = _threads[(ownerId, threadId)];
    return state == null ? null : copyJson(state);
  }

  @override
  Future<String?> threadForRun({
    required String ownerId,
    required String runId,
  }) async => _runs[(ownerId, runId)];

  @override
  Future<void> appendEvent({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject event,
  }) async {
    if (_active[(ownerId, threadId)] != runId) {
      throw const RunConflict('Run does not own thread.');
    }
    final journal = _events.putIfAbsent((ownerId, threadId, runId), () => []);
    if (event['sequence'] != journal.length) {
      throw const RunConflict('Event sequence is not contiguous.');
    }
    journal.add(copyJson(event));
  }

  @override
  Future<List<JsonObject>> events({
    required String ownerId,
    required String threadId,
    required String runId,
    int afterSequence = -1,
  }) async => [
    for (final event in _events[(ownerId, threadId, runId)] ?? <JsonObject>[])
      if ((event['sequence'] as int) > afterSequence) copyJson(event),
  ];
}

void validateTerminalEvent(JsonObject event) {
  if (event['type'] != 'RUN_FINISHED' && event['type'] != 'RUN_ERROR') {
    throw ArgumentError('Expected a terminal run event.');
  }
}
