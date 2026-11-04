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

abstract class AgentThread
    implements _is.TableRow<int?>, _is.ProtocolSerialization {
  AgentThread._({
    this.id,
    required this.ownerId,
    required this.threadId,
    this.activeRun,
    required this.stateJson,
  });

  factory AgentThread({
    int? id,
    required String ownerId,
    required String threadId,
    String? activeRun,
    required String stateJson,
  }) = _AgentThreadImpl;

  factory AgentThread.fromJson(Map<String, dynamic> jsonSerialization) {
    return AgentThread(
      id: jsonSerialization['id'] as int?,
      ownerId: jsonSerialization['ownerId'] as String,
      threadId: jsonSerialization['threadId'] as String,
      activeRun: jsonSerialization['activeRun'] as String?,
      stateJson: jsonSerialization['stateJson'] as String,
    );
  }

  static final t = AgentThreadTable();

  static const db = AgentThreadRepository._();

  @override
  int? id;

  String ownerId;

  String threadId;

  String? activeRun;

  String stateJson;

  @override
  _is.Table<int?> get table => t;

  /// Returns a shallow copy of this [AgentThread]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  AgentThread copyWith({
    int? id,
    String? ownerId,
    String? threadId,
    String? activeRun,
    String? stateJson,
  });
  @override
  Map<String, dynamic> toJson() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentThread',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      if (activeRun != null) 'activeRun': activeRun,
      'stateJson': stateJson,
    };
  }

  @override
  Map<String, dynamic> toJsonForProtocol() {
    return {
      '__className__': 'agent_weave_serverpod_storage.AgentThread',
      if (id != null) 'id': id,
      'ownerId': ownerId,
      'threadId': threadId,
      if (activeRun != null) 'activeRun': activeRun,
      'stateJson': stateJson,
    };
  }

  static AgentThreadInclude include() {
    return AgentThreadInclude._();
  }

  static AgentThreadIncludeList includeList({
    _is.WhereExpressionBuilder<AgentThreadTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentThreadTable>? orderBy,
    _is.OrderByListBuilder<AgentThreadTable>? orderByList,
    AgentThreadInclude? include,
  }) {
    return AgentThreadIncludeList._(
      where: where,
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AgentThread.t),
      orderByList: orderByList?.call(AgentThread.t),
      include: include,
    );
  }

  @override
  String toString() {
    return _is.SerializationManager.encode(this);
  }
}

class _Undefined {}

class _AgentThreadImpl extends AgentThread {
  _AgentThreadImpl({
    int? id,
    required String ownerId,
    required String threadId,
    String? activeRun,
    required String stateJson,
  }) : super._(
         id: id,
         ownerId: ownerId,
         threadId: threadId,
         activeRun: activeRun,
         stateJson: stateJson,
       );

  /// Returns a shallow copy of this [AgentThread]
  /// with some or all fields replaced by the given arguments.
  @_is.useResult
  @override
  AgentThread copyWith({
    Object? id = _Undefined,
    String? ownerId,
    String? threadId,
    Object? activeRun = _Undefined,
    String? stateJson,
  }) {
    return AgentThread(
      id: id is int? ? id : this.id,
      ownerId: ownerId ?? this.ownerId,
      threadId: threadId ?? this.threadId,
      activeRun: activeRun is String? ? activeRun : this.activeRun,
      stateJson: stateJson ?? this.stateJson,
    );
  }
}

class AgentThreadUpdateTable extends _is.UpdateTable<AgentThreadTable> {
  AgentThreadUpdateTable(super.table);

  _is.ColumnValue<String, String> ownerId(String value) =>
      _is.ColumnValue(table.ownerId, value);

  _is.ColumnValue<String, String> threadId(String value) =>
      _is.ColumnValue(table.threadId, value);

  _is.ColumnValue<String, String> activeRun(String? value) =>
      _is.ColumnValue(table.activeRun, value);

  _is.ColumnValue<String, String> stateJson(String value) =>
      _is.ColumnValue(table.stateJson, value);
}

class AgentThreadTable extends _is.Table<int?> {
  AgentThreadTable({super.tableRelation})
    : super(tableName: 'agent_weave_thread') {
    updateTable = AgentThreadUpdateTable(this);
    ownerId = _is.ColumnString('ownerId', this);
    threadId = _is.ColumnString('threadId', this);
    activeRun = _is.ColumnString('activeRun', this);
    stateJson = _is.ColumnString('stateJson', this);
  }

  late final AgentThreadUpdateTable updateTable;

  late final _is.ColumnString ownerId;

  late final _is.ColumnString threadId;

  late final _is.ColumnString activeRun;

  late final _is.ColumnString stateJson;

  @override
  List<_is.Column> get columns => [id, ownerId, threadId, activeRun, stateJson];
}

class AgentThreadInclude extends _is.IncludeObject {
  AgentThreadInclude._();

  @override
  Map<String, _is.Include?> get includes => {};

  @override
  _is.Table<int?> get table => AgentThread.t;
}

class AgentThreadIncludeList extends _is.IncludeList {
  AgentThreadIncludeList._({
    _is.WhereExpressionBuilder<AgentThreadTable>? where,
    super.limit,
    super.offset,
    super.orderBy,
    super.orderByList,
    super.include,
  }) {
    super.where = where?.call(AgentThread.t);
  }

  @override
  Map<String, _is.Include?> get includes => include?.includes ?? {};

  @override
  _is.Table<int?> get table => AgentThread.t;
}

class AgentThreadRepository {
  const AgentThreadRepository._();

  /// Returns a list of [AgentThread]s matching the given query parameters.
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
  Future<List<AgentThread>> find(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentThreadTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentThreadTable>? orderBy,
    _is.OrderByListBuilder<AgentThreadTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.find<AgentThread>(
      where: where?.call(AgentThread.t),
      orderBy: orderBy?.call(AgentThread.t),
      orderByList: orderByList?.call(AgentThread.t),
      limit: limit,
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Emits [AgentThread]s matching the given query parameters every time the
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
  /// to that set. Pass [Table] instances such as `AgentThread.t`.
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
  _ida.Stream<List<AgentThread>> watch(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentThreadTable>? where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentThreadTable>? orderBy,
    _is.OrderByListBuilder<AgentThreadTable>? orderByList,
    Duration? throttle = const Duration(milliseconds: 30),
    Iterable<_is.Table>? alsoTriggerOnTables,
  }) {
    return session.db.watch<AgentThread>(
      where: where?.call(AgentThread.t),
      orderBy: orderBy?.call(AgentThread.t),
      orderByList: orderByList?.call(AgentThread.t),
      limit: limit,
      offset: offset,
      throttle: throttle,
      alsoTriggerOnTables: alsoTriggerOnTables,
    );
  }

  /// Returns the first matching [AgentThread] matching the given query parameters.
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
  Future<AgentThread?> findFirstRow(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentThreadTable>? where,
    int? offset,
    _is.OrderByBuilder<AgentThreadTable>? orderBy,
    _is.OrderByListBuilder<AgentThreadTable>? orderByList,
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findFirstRow<AgentThread>(
      where: where?.call(AgentThread.t),
      orderBy: orderBy?.call(AgentThread.t),
      orderByList: orderByList?.call(AgentThread.t),
      offset: offset,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Finds a single [AgentThread] by its [id] or null if no such row exists.
  Future<AgentThread?> findById(
    _is.DatabaseSession session,
    int id, {
    _is.Transaction? transaction,
    _is.LockMode? lockMode,
    _is.LockBehavior? lockBehavior,
  }) async {
    return session.db.findById<AgentThread>(
      id,
      transaction: transaction,
      lockMode: lockMode,
      lockBehavior: lockBehavior,
    );
  }

  /// Inserts all [AgentThread]s in the list and returns the inserted rows.
  ///
  /// The returned [AgentThread]s will have their `id` fields set.
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
  Future<List<AgentThread>> insert(
    _is.DatabaseSession session,
    List<AgentThread> rows, {
    _is.Transaction? transaction,
    bool ignoreConflicts = false,
    bool noReturn = false,
  }) async {
    return session.db.insert<AgentThread>(
      rows,
      transaction: transaction,
      ignoreConflicts: ignoreConflicts,
      noReturn: noReturn,
    );
  }

  /// Inserts a single [AgentThread] and returns the inserted row.
  ///
  /// The returned [AgentThread] will have its `id` field set.
  Future<AgentThread> insertRow(
    _is.DatabaseSession session,
    AgentThread row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.insertRow<AgentThread>(row, transaction: transaction);
  }

  /// Upserts all [AgentThread]s in the list and returns the resulting rows.
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
  /// The returned [AgentThread]s will have their `id` fields set.
  ///
  /// This is an atomic operation, meaning that if one of the rows fails,
  /// none of the rows will be affected.
  ///
  /// If [noReturn] is set to `true`, the resulting rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentThread>> upsert(
    _is.DatabaseSession session,
    List<AgentThread> rows, {
    required _is.ColumnSelections<AgentThreadTable> conflictColumns,
    _is.ColumnSelections<AgentThreadTable>? updateColumns,
    _is.WhereExpressionBuilder<AgentThreadTable>? updateWhere,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.upsert<AgentThread>(
      rows,
      conflictColumns: conflictColumns(AgentThread.t),
      updateColumns: updateColumns?.call(AgentThread.t),
      updateWhere: updateWhere?.call(AgentThread.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Upserts a single [AgentThread] and returns the resulting row.
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
  /// The returned [AgentThread] will have its `id` field set.
  Future<AgentThread?> upsertRow(
    _is.DatabaseSession session,
    AgentThread row, {
    required _is.ColumnSelections<AgentThreadTable> conflictColumns,
    _is.ColumnSelections<AgentThreadTable>? updateColumns,
    _is.WhereExpressionBuilder<AgentThreadTable>? updateWhere,
    _is.Transaction? transaction,
  }) async {
    return session.db.upsertRow<AgentThread>(
      row,
      conflictColumns: conflictColumns(AgentThread.t),
      updateColumns: updateColumns?.call(AgentThread.t),
      updateWhere: updateWhere?.call(AgentThread.t),
      transaction: transaction,
    );
  }

  /// Updates all [AgentThread]s in the list and returns the updated rows. If
  /// [columns] is provided, only those columns will be updated. Defaults to
  /// all columns.
  /// This is an atomic operation, meaning that if one of the rows fails to
  /// update, none of the rows will be updated.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentThread>> update(
    _is.DatabaseSession session,
    List<AgentThread> rows, {
    _is.ColumnSelections<AgentThreadTable>? columns,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.update<AgentThread>(
      rows,
      columns: columns?.call(AgentThread.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Updates a single [AgentThread]. The row needs to have its id set.
  /// Optionally, a list of [columns] can be provided to only update those
  /// columns. Defaults to all columns.
  Future<AgentThread> updateRow(
    _is.DatabaseSession session,
    AgentThread row, {
    _is.ColumnSelections<AgentThreadTable>? columns,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateRow<AgentThread>(
      row,
      columns: columns?.call(AgentThread.t),
      transaction: transaction,
    );
  }

  /// Updates a single [AgentThread] by its [id] with the specified [columnValues].
  /// Returns the updated row or null if no row with the given id exists.
  Future<AgentThread?> updateById(
    _is.DatabaseSession session,
    int id, {
    required _is.ColumnValueListBuilder<AgentThreadUpdateTable> columnValues,
    _is.Transaction? transaction,
  }) async {
    return session.db.updateById<AgentThread>(
      id,
      columnValues: columnValues(AgentThread.t.updateTable),
      transaction: transaction,
    );
  }

  /// Updates all [AgentThread]s matching the [where] expression with the specified [columnValues].
  /// Returns the list of updated rows.
  ///
  /// If [noReturn] is set to `true`, the updated rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentThread>> updateWhere(
    _is.DatabaseSession session, {
    required _is.ColumnValueListBuilder<AgentThreadUpdateTable> columnValues,
    required _is.WhereExpressionBuilder<AgentThreadTable> where,
    int? limit,
    int? offset,
    _is.OrderByBuilder<AgentThreadTable>? orderBy,
    _is.OrderByListBuilder<AgentThreadTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.updateWhere<AgentThread>(
      columnValues: columnValues(AgentThread.t.updateTable),
      where: where(AgentThread.t),
      limit: limit,
      offset: offset,
      orderBy: orderBy?.call(AgentThread.t),
      orderByList: orderByList?.call(AgentThread.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes all [AgentThread]s in the list and returns the deleted rows.
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
  Future<List<AgentThread>> delete(
    _is.DatabaseSession session,
    List<AgentThread> rows, {
    _is.OrderByBuilder<AgentThreadTable>? orderBy,
    _is.OrderByListBuilder<AgentThreadTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.delete<AgentThread>(
      rows,
      orderBy: orderBy?.call(AgentThread.t),
      orderByList: orderByList?.call(AgentThread.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Deletes a single [AgentThread].
  Future<AgentThread> deleteRow(
    _is.DatabaseSession session,
    AgentThread row, {
    _is.Transaction? transaction,
  }) async {
    return session.db.deleteRow<AgentThread>(row, transaction: transaction);
  }

  /// Deletes all rows matching the [where] expression.
  ///
  /// To specify the order of the returned rows use [orderBy] or [orderByList]
  /// when sorting by multiple columns.
  ///
  /// If [noReturn] is set to `true`, the deleted rows are not read back from
  /// the database and an empty list is returned. This avoids the overhead of
  /// transferring and deserializing the rows when the result is not needed.
  Future<List<AgentThread>> deleteWhere(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AgentThreadTable> where,
    _is.OrderByBuilder<AgentThreadTable>? orderBy,
    _is.OrderByListBuilder<AgentThreadTable>? orderByList,
    _is.Transaction? transaction,
    bool noReturn = false,
  }) async {
    return session.db.deleteWhere<AgentThread>(
      where: where(AgentThread.t),
      orderBy: orderBy?.call(AgentThread.t),
      orderByList: orderByList?.call(AgentThread.t),
      transaction: transaction,
      noReturn: noReturn,
    );
  }

  /// Counts the number of rows matching the [where] expression. If omitted,
  /// will return the count of all rows in the table.
  Future<int> count(
    _is.DatabaseSession session, {
    _is.WhereExpressionBuilder<AgentThreadTable>? where,
    int? limit,
    _is.Transaction? transaction,
  }) async {
    return session.db.count<AgentThread>(
      where: where?.call(AgentThread.t),
      limit: limit,
      transaction: transaction,
    );
  }

  /// Acquires row-level locks on [AgentThread] rows matching the [where] expression.
  Future<void> lockRows(
    _is.DatabaseSession session, {
    required _is.WhereExpressionBuilder<AgentThreadTable> where,
    required _is.LockMode lockMode,
    required _is.Transaction transaction,
    _is.LockBehavior lockBehavior = _is.LockBehavior.wait,
  }) async {
    return session.db.lockRows<AgentThread>(
      where: where(AgentThread.t),
      lockMode: lockMode,
      lockBehavior: lockBehavior,
      transaction: transaction,
    );
  }
}
