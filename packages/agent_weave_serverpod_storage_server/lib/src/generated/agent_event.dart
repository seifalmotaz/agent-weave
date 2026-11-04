/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */
/*   To generate run: "serverpod generate"    */

// ignore_for_file: implementation_imports
// ignore_for_file: library_private_types_in_public_api
// ignore_for_file: non_constant_identifier_names
// ignore_for_file: public_member_api_docs
// ignore_for_file: type_literal_in_constant_pattern
// ignore_for_file: use_super_parameters
// ignore_for_file: invalid_use_of_internal_member

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'dart:async' as _ida;
import 'package:serverpod/serverpod.dart' as _is;

abstract class AgentStoredEvent
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  AgentStoredEvent._({
    this.id,
    required this.ownerId,
    required this.threadId,
    required this.runId,
    required this.sequence,
    required this.eventJson,
  });

  factory AgentStoredEvent({
    int? id,
    required String ownerId,
    required String threadId,
    required String runId,
    required int sequence,
    required String eventJson,
  }) = _AgentStoredEventImpl;

  factory AgentStoredEvent.fromJson(Map<String, dynamic> jsonSerialization) {
    return AgentStoredEvent(
      id: jsonSerialization['id'] as int?,
      ownerId: jsonSerialization['ownerId'] as String,
      threadId: jsonSerialization['threadId'] as String,
      runId: jsonSerialization['runId'] as String,
      sequence: jsonSerialization['sequence'] as int,
      eventJson: jsonSerialization['eventJson'] as String,
    );
  }

  static final t = AgentStoredEventTable();

  static const db = AgentStoredEventRepository._();

  @override
  int? id;

  String ownerId;

  String threadId;

  String runId;

  int sequence;

  String eventJson;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [AgentStoredEvent]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AgentStoredEvent copyWith({
    int? id,
    String? ownerId,
    String? threadId,
    String? runId,
    int? sequence,
    String? eventJson,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentStoredEvent',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      'runId': runId,
      'sequence': sequence,
      'eventJson': eventJson,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentStoredEvent',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      'runId': runId,
      'sequence': sequence,
      'eventJson': eventJson,
    };
  }

  static AgentStoredEventInclude include() {
    return AgentStoredEventInclude._();
  }

  static AgentStoredEventIncludeList includeList({
    _is.WhereExpressionBuilder<AgentStoredEventTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentStoredEventTable>? orderBy,
    _is.OrderByListBuilder<AgentStoredEventTable>? orderByList,
    AgentStoredEventInclude? include,
  }) {
    return AgentStoredEventIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AgentStoredEvent.t),
      orderByList: orderByList?.call(AgentStoredEvent.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AgentStoredEventImpl extends AgentStoredEvent {
  _AgentStoredEventImpl({
    int? id,
    required String ownerId,
    required String threadId,
    required String runId,
    required int sequence,
    required String eventJson,
  }) : super._(
         id: id,
         ownerId: ownerId,
         threadId: threadId,
         runId: runId,
         sequence: sequence,
         eventJson: eventJson,
       );

  /// Returns a shallow copy of this [AgentStoredEvent]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AgentStoredEvent copyWith({
    Object? id = _Undefined,
    String? ownerId,
    String? threadId,
    String? runId,
    int? sequence,
    String? eventJson,
  }) {
    return AgentStoredEvent(
      id: id is int? ? id : this.id,
      ownerId: ownerId ?? this.ownerId,
      threadId: threadId ?? this.threadId,
      runId: runId ?? this.runId,
      sequence: sequence ?? this.sequence,
      eventJson: eventJson ?? this.eventJson,
    );
  }
}

class AgentStoredEventUpdateTable
    extends _is.UpdateTable<AgentStoredEventTable> {
  AgentStoredEventUpdateTable(super.table);

  _is.ColumnValue<String, String> ownerId(String value) =>
      _is.ColumnValue(table.ownerId, value);

  _is.ColumnValue<String, String> threadId(String value) =>
      _is.ColumnValue(table.threadId, value);

  _is.ColumnValue<String, String> runId(String value) =>
      _is.ColumnValue(table.runId, value);

  _is.ColumnValue<int, int> sequence(int value) =>
      _is.ColumnValue(table.sequence, value);

  _is.ColumnValue<String, String> eventJson(String value) =>
      _is.ColumnValue(table.eventJson, value);
}

class AgentStoredEventTable extends _is.Table<int?> {
  AgentStoredEventTable({super.tableRelation})
    : super(tableName: 'agent_weave_event') {
    updateTable = AgentStoredEventUpdateTable(this);
    ownerId = _is.ColumnString('ownerId', this);
    threadId = _is.ColumnString('threadId', this);
    runId = _is.ColumnString('runId', this);
    sequence = _is.ColumnInt('sequence', this);
    eventJson = _is.ColumnString('eventJson', this);
  }

  late final AgentStoredEventUpdateTable updateTable;

  late final _is.ColumnString ownerId;

  late final _is.ColumnString threadId;

  late final _is.ColumnString runId;

  late final _is.ColumnInt sequence;

  late final _is.ColumnString eventJson;

  @override
  List<_is.Column> get columns => [
    id,
    ownerId,
    threadId,
    runId,
    sequence,
    eventJson,
  ];
}

class AgentStoredEventInclude extends _is.IncludeObject {
  AgentStoredEventInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => AgentStoredEvent.t;
}

class AgentStoredEventIncludeList extends _is.IncludeList {
  AgentStoredEventIncludeList._({
    _is.WhereExpressionBuilder<AgentStoredEventTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AgentStoredEvent.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => AgentStoredEvent.t;
}

class AgentStoredEventRepository {
  const AgentStoredEventRepository._();

  /// Returns a list of [AgentStoredEvent]s matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order of the items use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// The maximum number of items can be set by [limit]. If no limit is set,
  /// all items matching the query will be returned.
  ///
  /// [offset] defines how many items to skip, after which [limit] (or all)
  /// items are read from the database.
  ///
  /// ```dart
  /// var persons = await Persons.db.find(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.firstName,
  ///   limit: 100,
  /// );
  /// ```
  Future<List<AgentStoredEvent>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentStoredEventTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentStoredEventTable>? orderBy,
    _is.OrderByListBuilder<AgentStoredEventTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AgentStoredEvent>(
      where: where?.call(AgentStoredEvent.t),
      orderBy: orderBy?.call(AgentStoredEvent.t),
      orderByList: orderByList?.call(AgentStoredEvent.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Emits [AgentStoredEvent]s matching the given query parameters every time the
  /// source tables are modified.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order of the items use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// The maximum number of items can be set by [limit]. If no limit is set,
  /// all items matching the query will be returned.
  ///
  /// [offset] defines how many items to skip, after which [limit] (or all)
  /// items are read from the database.
  ///
  /// Use [throttle] to specify the minimum interval between queries. It can
  /// also be set to `null`, in which case the stream will only be throttled
  /// when its subscription is paused.
  ///
  /// Source tables are collected from the queried table, [where], [orderBy],
  /// [orderByList], and the [include] graph. [alsoTriggerOnTables] is added
  /// to that set. Pass [Table] instances such as `AgentStoredEvent.t`.
  ///
  /// Raw [Expression] SQL is not inspected. Tables referenced only in raw
  /// SQL must be passed via [alsoTriggerOnTables].
  ///
  /// The stream always reads committed state and never joins an ambient
  /// [Transaction]. Emissions for a write fire after that write commits.
  ///
  /// Currently only supported on SQLite. Calling this method on PostgreSQL
  /// throws an [UnsupportedError].
  ///
  /// ```dart
  /// var subscription = Persons.db.watch(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.firstName,
  ///   limit: 100,
  /// ).listen((persons) {
  ///   // Handle the latest matching rows.
  /// });
  /// ```
  _ida.Stream<List<AgentStoredEvent>> watch(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentStoredEventTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentStoredEventTable>? orderBy,
    _is.OrderByListBuilder<AgentStoredEventTable>? orderByList,
    Duration? throttle = const Duration(milliseconds: 30),
    Iterable<_is.Table>? alsoTriggerOnTables,
  }) {
    return session.db.watch<AgentStoredEvent>(
      where: where?.call(AgentStoredEvent.t),
      orderBy: orderBy?.call(AgentStoredEvent.t),
      orderByList: orderByList?.call(AgentStoredEvent.t),
      limit: limit,
      offset: offset,
      throttle: throttle,
      alsoTriggerOnTables: alsoTriggerOnTables,
    );
  }

  /// Returns the first matching [AgentStoredEvent] matching the given query parameters.
  ///
  /// Use [where] to specify which items to include in the return value.
  /// If none is specified, all items will be returned.
  ///
  /// To specify the order use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// [offset] defines how many items to skip, after which the next one will be picked.
  ///
  /// ```dart
  /// var youngestPerson = await Persons.db.findFirstRow(
  ///   session,
  ///   where: (t) => t.lastName.equals('Jones'),
  ///   orderBy: (t) => t.age,
  /// );
  /// ```
  Future<AgentStoredEvent?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentStoredEventTable>? where,
    int? offset,
    _is.OrderByBuilder<AgentStoredEventTable>? orderBy,
    _is.OrderByListBuilder<AgentStoredEventTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AgentStoredEvent>(
      where: where?.call(AgentStoredEvent.t),
      orderBy: orderBy?.call(AgentStoredEvent.t),
      orderByList: orderByList?.call(AgentStoredEvent.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AgentStoredEvent] by its [id] or null if no such row exists.
  Future<AgentStoredEvent?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AgentStoredEvent>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AgentStoredEvent]s in the list and returns the inserted rows.
  ///
  /// The returned [AgentStoredEvent]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// insert, none of the rows will be inserted.
  ///
  /// If [ignoreConflicts] is set to `true`, rows that conflict with existing
  /// rows are silently skipped, and only the successfully inserted rows are
  /// returned.
  ///
  /// If [noReturn] is set to `true`, the inserted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentStoredEvent>> insert(
    _is.DatabaseSession session,
    List<AgentStoredEvent> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<AgentStoredEvent>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [AgentStoredEvent] and returns the inserted row.
  ///
  /// The returned [AgentStoredEvent] will have its `id` field set.
  Future<AgentStoredEvent> insertRow(
    _is.DatabaseSession session,
    AgentStoredEvent row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<AgentStoredEvent>(
      row,
      transaction: transaction,
    );
  }

  /// Upserts all [AgentStoredEvent]s in the list and returns the resulting rows.
  ///
  /// If a row conflicts on the given [conflictColumns], the existing row is
  /// updated with the new values. Otherwise, a new row is inserted.
  ///
  /// If [updateColumns] is provided, only those columns will be updated on
  /// conflict. If null, all non-conflict, non-id columns are updated.
  ///
  /// If [updateWhere] is provided, the update only applies to rows matching the
  /// given expression. Conflicting rows that don't match are skipped and not
  /// returned, so the resulting list may be shorter than [rows].
  ///
  /// The returned [AgentStoredEvent]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentStoredEvent>> upsert(
    _is.DatabaseSession session,
    List<AgentStoredEvent> rows, {
    required _is.ColumnSelections<AgentStoredEventTable> conflictColumns,
    _is.ColumnSelections<AgentStoredEventTable>? updateColumns,
    _is.WhereExpressionBuilder<AgentStoredEventTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<AgentStoredEvent>(
      rows,
      conflictColumns: conflictColumns(AgentStoredEvent.t),
      updateColumns: updateColumns?.call(AgentStoredEvent.t),
      updateWhere: updateWhere?.call(AgentStoredEvent.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [AgentStoredEvent] and returns the resulting row.
  ///
  /// If the row conflicts on the given [conflictColumns], the existing row is
  /// updated. Otherwise, a new row is inserted.
  ///
  /// If [updateColumns] is provided, only those columns will be updated on
  /// conflict. If null, all non-conflict, non-id columns are updated.
  ///
  /// If [updateWhere] is provided, the update only applies when the existing
  /// row matches the expression. Returns `null` if no row was affected — for
  /// example when [updateWhere] does not match the conflicting row.
  ///
  /// The returned [AgentStoredEvent] will have its `id` field set.
  Future<AgentStoredEvent?> upsertRow(
    _is.DatabaseSession session,
    AgentStoredEvent row, {
    required _is.ColumnSelections<AgentStoredEventTable> conflictColumns,
    _is.ColumnSelections<AgentStoredEventTable>? updateColumns,
    _is.WhereExpressionBuilder<AgentStoredEventTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<AgentStoredEvent>(
      row,
      conflictColumns: conflictColumns(AgentStoredEvent.t),
      updateColumns: updateColumns?.call(AgentStoredEvent.t),
      updateWhere: updateWhere?.call(AgentStoredEvent.t),
      transaction: transaction,
    );
  }

  /// Updates all [AgentStoredEvent]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentStoredEvent>> update(
    _is.DatabaseSession session,
    List<AgentStoredEvent> rows, {
    _is.ColumnSelections<AgentStoredEventTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<AgentStoredEvent>(
      rows,
      columns: columns?.call(AgentStoredEvent.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [AgentStoredEvent]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AgentStoredEvent> updateRow(
    _is.DatabaseSession session,
    AgentStoredEvent row, {
    _is.ColumnSelections<AgentStoredEventTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<AgentStoredEvent>(
      row,
      columns: columns?.call(AgentStoredEvent.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AgentStoredEvent] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AgentStoredEvent?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<AgentStoredEventUpdateTable>
    columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<AgentStoredEvent>(
      id,
      columnValues: columnValues(AgentStoredEvent.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AgentStoredEvent]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentStoredEvent>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<AgentStoredEventUpdateTable>
    columnValues,
    required _is.WhereExpressionBuilder<AgentStoredEventTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentStoredEventTable>? orderBy,
    _is.OrderByListBuilder<AgentStoredEventTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<AgentStoredEvent>(
      columnValues: columnValues(AgentStoredEvent.t.updateTable),
      where: where(AgentStoredEvent.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AgentStoredEvent.t),
      orderByList: orderByList?.call(AgentStoredEvent.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [AgentStoredEvent]s in the list and returns the deleted rows.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// This is an atomic operation, meaning that if one of the rows fail to
  /// be deleted, none of the rows will be deleted.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentStoredEvent>> delete(
    _is.DatabaseSession session,
    List<AgentStoredEvent> rows, {
    _is.OrderByBuilder<AgentStoredEventTable>? orderBy,
    _is.OrderByListBuilder<AgentStoredEventTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<AgentStoredEvent>(
      rows,
      orderBy: orderBy?.call(AgentStoredEvent.t),
      orderByList: orderByList?.call(AgentStoredEvent.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [AgentStoredEvent].
  Future<AgentStoredEvent> deleteRow(
    _is.DatabaseSession session,
    AgentStoredEvent row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AgentStoredEvent>(
      row,
      transaction: transaction,
    );
  }

  /// Deletes all rows matching the [where] expression.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentStoredEvent>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AgentStoredEventTable> where,
    _is.OrderByBuilder<AgentStoredEventTable>? orderBy,
    _is.OrderByListBuilder<AgentStoredEventTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<AgentStoredEvent>(
      where: where(AgentStoredEvent.t),
      orderBy: orderBy?.call(AgentStoredEvent.t),
      orderByList: orderByList?.call(AgentStoredEvent.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentStoredEventTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<AgentStoredEvent>(
      where: where?.call(AgentStoredEvent.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AgentStoredEvent] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AgentStoredEventTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AgentStoredEvent>(
      where: where(AgentStoredEvent.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
