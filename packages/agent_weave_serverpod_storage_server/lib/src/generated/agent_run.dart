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

abstract class AgentRun
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  AgentRun._({
    this.id,
    required this.ownerId,
    required this.threadId,
    required this.runId,
  });

  factory AgentRun({
    int? id,
    required String ownerId,
    required String threadId,
    required String runId,
  }) = _AgentRunImpl;

  factory AgentRun.fromJson(Map<String, dynamic> jsonSerialization) {
    return AgentRun(
      id: jsonSerialization['id'] as int?,
      ownerId: jsonSerialization['ownerId'] as String,
      threadId: jsonSerialization['threadId'] as String,
      runId: jsonSerialization['runId'] as String,
    );
  }

  static final t = AgentRunTable();

  static const db = AgentRunRepository._();

  @override
  int? id;

  String ownerId;

  String threadId;

  String runId;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [AgentRun]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AgentRun copyWith({
    int? id,
    String? ownerId,
    String? threadId,
    String? runId,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentRun',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      'runId': runId,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentRun',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      'runId': runId,
    };
  }

  static AgentRunInclude include() {
    return AgentRunInclude._();
  }

  static AgentRunIncludeList includeList({
    _is.WhereExpressionBuilder<AgentRunTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentRunTable>? orderBy,
    _is.OrderByListBuilder<AgentRunTable>? orderByList,
    AgentRunInclude? include,
  }) {
    return AgentRunIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AgentRun.t),
      orderByList: orderByList?.call(AgentRun.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AgentRunImpl extends AgentRun {
  _AgentRunImpl({
    int? id,
    required String ownerId,
    required String threadId,
    required String runId,
  }) : super._(id: id, ownerId: ownerId, threadId: threadId, runId: runId);

  /// Returns a shallow copy of this [AgentRun]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AgentRun copyWith({
    Object? id = _Undefined,
    String? ownerId,
    String? threadId,
    String? runId,
  }) {
    return AgentRun(
      id: id is int? ? id : this.id,
      ownerId: ownerId ?? this.ownerId,
      threadId: threadId ?? this.threadId,
      runId: runId ?? this.runId,
    );
  }
}

class AgentRunUpdateTable extends _is.UpdateTable<AgentRunTable> {
  AgentRunUpdateTable(super.table);

  _is.ColumnValue<String, String> ownerId(String value) =>
      _is.ColumnValue(table.ownerId, value);

  _is.ColumnValue<String, String> threadId(String value) =>
      _is.ColumnValue(table.threadId, value);

  _is.ColumnValue<String, String> runId(String value) =>
      _is.ColumnValue(table.runId, value);
}

class AgentRunTable extends _is.Table<int?> {
  AgentRunTable({super.tableRelation}) : super(tableName: 'agent_weave_run') {
    updateTable = AgentRunUpdateTable(this);
    ownerId = _is.ColumnString('ownerId', this);
    threadId = _is.ColumnString('threadId', this);
    runId = _is.ColumnString('runId', this);
  }

  late final AgentRunUpdateTable updateTable;

  late final _is.ColumnString ownerId;

  late final _is.ColumnString threadId;

  late final _is.ColumnString runId;

  @override
  List<_is.Column> get columns => [id, ownerId, threadId, runId];
}

class AgentRunInclude extends _is.IncludeObject {
  AgentRunInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => AgentRun.t;
}

class AgentRunIncludeList extends _is.IncludeList {
  AgentRunIncludeList._({
    _is.WhereExpressionBuilder<AgentRunTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AgentRun.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => AgentRun.t;
}

class AgentRunRepository {
  const AgentRunRepository._();

  /// Returns a list of [AgentRun]s matching the given query parameters.
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
  Future<List<AgentRun>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentRunTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentRunTable>? orderBy,
    _is.OrderByListBuilder<AgentRunTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AgentRun>(
      where: where?.call(AgentRun.t),
      orderBy: orderBy?.call(AgentRun.t),
      orderByList: orderByList?.call(AgentRun.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Emits [AgentRun]s matching the given query parameters every time the
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
  /// to that set. Pass [Table] instances such as `AgentRun.t`.
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
  _ida.Stream<List<AgentRun>> watch(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentRunTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentRunTable>? orderBy,
    _is.OrderByListBuilder<AgentRunTable>? orderByList,
    Duration? throttle = const Duration(milliseconds: 30),
    Iterable<_is.Table>? alsoTriggerOnTables,
  }) {
    return session.db.watch<AgentRun>(
      where: where?.call(AgentRun.t),
      orderBy: orderBy?.call(AgentRun.t),
      orderByList: orderByList?.call(AgentRun.t),
      limit: limit,
      offset: offset,
      throttle: throttle,
      alsoTriggerOnTables: alsoTriggerOnTables,
    );
  }

  /// Returns the first matching [AgentRun] matching the given query parameters.
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
  Future<AgentRun?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentRunTable>? where,
    int? offset,
    _is.OrderByBuilder<AgentRunTable>? orderBy,
    _is.OrderByListBuilder<AgentRunTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AgentRun>(
      where: where?.call(AgentRun.t),
      orderBy: orderBy?.call(AgentRun.t),
      orderByList: orderByList?.call(AgentRun.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AgentRun] by its [id] or null if no such row exists.
  Future<AgentRun?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AgentRun>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AgentRun]s in the list and returns the inserted rows.
  ///
  /// The returned [AgentRun]s will have their `id` fields set.
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
  Future<List<AgentRun>> insert(
    _is.DatabaseSession session,
    List<AgentRun> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<AgentRun>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [AgentRun] and returns the inserted row.
  ///
  /// The returned [AgentRun] will have its `id` field set.
  Future<AgentRun> insertRow(
    _is.DatabaseSession session,
    AgentRun row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<AgentRun>(row, transaction: transaction);
  }

  /// Upserts all [AgentRun]s in the list and returns the resulting rows.
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
  /// The returned [AgentRun]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentRun>> upsert(
    _is.DatabaseSession session,
    List<AgentRun> rows, {
    required _is.ColumnSelections<AgentRunTable> conflictColumns,
    _is.ColumnSelections<AgentRunTable>? updateColumns,
    _is.WhereExpressionBuilder<AgentRunTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<AgentRun>(
      rows,
      conflictColumns: conflictColumns(AgentRun.t),
      updateColumns: updateColumns?.call(AgentRun.t),
      updateWhere: updateWhere?.call(AgentRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [AgentRun] and returns the resulting row.
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
  /// The returned [AgentRun] will have its `id` field set.
  Future<AgentRun?> upsertRow(
    _is.DatabaseSession session,
    AgentRun row, {
    required _is.ColumnSelections<AgentRunTable> conflictColumns,
    _is.ColumnSelections<AgentRunTable>? updateColumns,
    _is.WhereExpressionBuilder<AgentRunTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<AgentRun>(
      row,
      conflictColumns: conflictColumns(AgentRun.t),
      updateColumns: updateColumns?.call(AgentRun.t),
      updateWhere: updateWhere?.call(AgentRun.t),
      transaction: transaction,
    );
  }

  /// Updates all [AgentRun]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentRun>> update(
    _is.DatabaseSession session,
    List<AgentRun> rows, {
    _is.ColumnSelections<AgentRunTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<AgentRun>(
      rows,
      columns: columns?.call(AgentRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [AgentRun]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AgentRun> updateRow(
    _is.DatabaseSession session,
    AgentRun row, {
    _is.ColumnSelections<AgentRunTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<AgentRun>(
      row,
      columns: columns?.call(AgentRun.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AgentRun] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AgentRun?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<AgentRunUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<AgentRun>(
      id,
      columnValues: columnValues(AgentRun.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AgentRun]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentRun>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<AgentRunUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<AgentRunTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentRunTable>? orderBy,
    _is.OrderByListBuilder<AgentRunTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<AgentRun>(
      columnValues: columnValues(AgentRun.t.updateTable),
      where: where(AgentRun.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AgentRun.t),
      orderByList: orderByList?.call(AgentRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [AgentRun]s in the list and returns the deleted rows.
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
  Future<List<AgentRun>> delete(
    _is.DatabaseSession session,
    List<AgentRun> rows, {
    _is.OrderByBuilder<AgentRunTable>? orderBy,
    _is.OrderByListBuilder<AgentRunTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<AgentRun>(
      rows,
      orderBy: orderBy?.call(AgentRun.t),
      orderByList: orderByList?.call(AgentRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [AgentRun].
  Future<AgentRun> deleteRow(
    _is.DatabaseSession session,
    AgentRun row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AgentRun>(row, transaction: transaction);
  }

  /// Deletes all rows matching the [where] expression.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentRun>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AgentRunTable> where,
    _is.OrderByBuilder<AgentRunTable>? orderBy,
    _is.OrderByListBuilder<AgentRunTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<AgentRun>(
      where: where(AgentRun.t),
      orderBy: orderBy?.call(AgentRun.t),
      orderByList: orderByList?.call(AgentRun.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentRunTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<AgentRun>(
      where: where?.call(AgentRun.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AgentRun] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AgentRunTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AgentRun>(
      where: where(AgentRun.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
