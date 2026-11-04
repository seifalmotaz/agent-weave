import 'dart:convert';
import 'package:agent_weave/agent_weave.dart';
import 'package:serverpod/serverpod.dart';

/// PostgreSQL-backed store using the module's generated database models.
///
/// Reservations survive process restarts. Active runs are never automatically
/// re-executed: tools may have committed external effects before a crash.
final class ServerpodRunStore implements RunStore {
  final Session session;
  const ServerpodRunStore(this.session);

  @override
  Future<JsonObject> begin({
    required String ownerId,
    required String threadId,
    required String runId,
    String? parentRunId,
  }) => session.db.transaction((tx) async {
    final ownerThread = QueryParameters.named({
      'owner': ownerId,
      'thread': threadId,
    });
    final params = QueryParameters.named({
      'owner': ownerId,
      'thread': threadId,
      'run': runId,
    });
    await session.db.unsafeQuery(
      '''
      INSERT INTO agent_weave_thread ("ownerId", "threadId", "stateJson")
      VALUES (@owner, @thread, '{}')
      ON CONFLICT ("ownerId", "threadId") DO NOTHING
      ''',
      parameters: ownerThread,
      transaction: tx,
    );
    final rows = await session.db.unsafeQuery(
      '''
      SELECT "activeRun", "stateJson" FROM agent_weave_thread
      WHERE "ownerId" = @owner AND "threadId" = @thread FOR UPDATE
      ''',
      parameters: ownerThread,
      transaction: tx,
    );
    final row = rows.single;
    if (row[0] != null) throw const RunConflict('Thread is busy.');
    final previous = Map<String, Object?>.from(
      jsonDecode(row[1] as String) as Map,
    );
    if ((previous['status'] == 'interrupted' || parentRunId != null) &&
        previous['runId'] != parentRunId) {
      throw const RunConflict('Parent run does not match thread history.');
    }
    final inserted = await session.db.unsafeQuery(
      '''
      INSERT INTO agent_weave_run ("ownerId", "threadId", "runId")
      VALUES (@owner, @thread, @run)
      ON CONFLICT ("ownerId", "runId") DO NOTHING RETURNING id
      ''',
      parameters: params,
      transaction: tx,
    );
    if (inserted.isEmpty) {
      throw const RunConflict('Run identifier has already been used.');
    }
    await session.db.unsafeQuery(
      '''
      UPDATE agent_weave_thread SET "activeRun" = @run
      WHERE "ownerId" = @owner AND "threadId" = @thread
      ''',
      parameters: params,
      transaction: tx,
    );
    return previous;
  });

  @override
  Future<void> save({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject state,
    required bool release,
  }) async {
    final rows = await session.db.unsafeQuery(
      '''
      UPDATE agent_weave_thread SET "stateJson" = @state, "activeRun" = @active
      WHERE "ownerId" = @owner AND "threadId" = @thread AND "activeRun" = @run
      RETURNING id
      ''',
      parameters: QueryParameters.named({
        'owner': ownerId,
        'thread': threadId,
        'run': runId,
        'state': jsonEncode(state),
        'active': release ? null : runId,
      }),
    );
    if (rows.isEmpty) throw const RunConflict('Run does not own thread.');
  }

  @override
  Future<JsonObject?> load({
    required String ownerId,
    required String threadId,
  }) async {
    final rows = await session.db.unsafeQuery(
      '''
      SELECT "stateJson" FROM agent_weave_thread
      WHERE "ownerId" = @owner AND "threadId" = @thread
      ''',
      parameters: QueryParameters.named({'owner': ownerId, 'thread': threadId}),
    );
    return rows.isEmpty
        ? null
        : Map<String, Object?>.from(
            jsonDecode(rows.single[0] as String) as Map,
          );
  }

  @override
  Future<String?> threadForRun({
    required String ownerId,
    required String runId,
  }) async {
    final rows = await session.db.unsafeQuery('''
      SELECT "threadId" FROM agent_weave_run WHERE "ownerId" = @owner AND "runId" = @run
      ''', parameters: QueryParameters.named({'owner': ownerId, 'run': runId}));
    return rows.isEmpty ? null : rows.single[0] as String;
  }

  @override
  Future<void> appendEvent({
    required String ownerId,
    required String threadId,
    required String runId,
    required JsonObject event,
  }) async {
    final rows = await session.db.unsafeQuery(
      '''
      INSERT INTO agent_weave_event ("ownerId", "threadId", "runId", "sequence", "eventJson")
      SELECT @owner, @thread, @run, @sequence, @event
      FROM agent_weave_thread WHERE "ownerId" = @owner AND "threadId" = @thread
        AND "activeRun" = @run
      RETURNING id
      ''',
      parameters: QueryParameters.named({
        'owner': ownerId,
        'thread': threadId,
        'run': runId,
        'sequence': event['sequence'],
        'event': jsonEncode(event),
      }),
    );
    if (rows.isEmpty) throw const RunConflict('Run does not own thread.');
  }

  @override
  Future<List<JsonObject>> events({
    required String ownerId,
    required String threadId,
    required String runId,
    int afterSequence = -1,
  }) async {
    final rows = await session.db.unsafeQuery(
      '''
      SELECT "eventJson" FROM agent_weave_event
      WHERE "ownerId" = @owner AND "threadId" = @thread AND "runId" = @run
        AND "sequence" > @after ORDER BY "sequence"
      ''',
      parameters: QueryParameters.named({
        'owner': ownerId,
        'thread': threadId,
        'run': runId,
        'after': afterSequence,
      }),
    );
    return [
      for (final row in rows)
        Map<String, Object?>.from(jsonDecode(row[0] as String) as Map),
    ];
  }
}
