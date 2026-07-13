import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/core/api_client.dart';
import 'package:mobile/src/core/app_database.dart';
import 'package:mobile/src/core/session_store.dart';
import 'package:mobile/src/core/sync_service.dart';

/// Records what the engine pushes and serves a scripted /sync/changes response.
class _FakeApi extends ApiClient {
  _FakeApi(super.sessionStore);

  Map<String, dynamic> nextChanges = {
    'server_time': '2026-07-12T00:00:00Z',
    'changes': <String, dynamic>{},
    'tombstones': <dynamic>[],
  };
  bool createTransactionThrows = false;

  final createdTransactions = <Map<String, dynamic>>[];
  final updatedTransactionIds = <String>[];
  final deletedTransactionIds = <String>[];
  final upsertedBudgets = <Map<String, dynamic>>[];
  final deletedBudgetIds = <String>[];
  final savedIncome = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getSyncChanges({String? since}) async =>
      nextChanges;

  @override
  Future<Map<String, dynamic>> upsertBudget(
    Map<String, dynamic> payload,
  ) async {
    upsertedBudgets.add(payload);
    return payload;
  }

  @override
  Future<void> deleteBudget(String id) async => deletedBudgetIds.add(id);

  @override
  Future<Map<String, dynamic>> saveMonthlyIncome(
    Map<String, dynamic> payload,
  ) async {
    savedIncome.add(payload);
    return payload;
  }

  @override
  Future<Map<String, dynamic>> createTransaction(
    Map<String, dynamic> payload,
  ) async {
    if (createTransactionThrows) throw Exception('rejected');
    createdTransactions.add(payload);
    return payload;
  }

  @override
  Future<Map<String, dynamic>> updateTransaction(
    String id,
    Map<String, dynamic> payload,
  ) async {
    updatedTransactionIds.add(id);
    return payload;
  }

  @override
  Future<void> deleteTransaction(String id) async =>
      deletedTransactionIds.add(id);

  @override
  Future<Map<String, dynamic>> getPortfolioSummary({String? portfolioId}) async => {};
  @override
  Future<List<Map<String, dynamic>>> getPortfolios() async => [];
  @override
  Future<Map<String, dynamic>> getSimpleDashboard(String month) async => {};
}

/// In-memory stand-in for AppDatabase that behaves like the real dirty/queue
/// bookkeeping (mutates on clearDirty / removePendingDelete) so the engine's
/// control flow is exercised end to end without a device database.
class _FakeDb extends AppDatabase {
  final Map<String, List<Map<String, dynamic>>> dirty = {
    'transactions': [],
    'categories': [],
    'accounts': [],
    'budgets': [],
  };
  final pending = <Map<String, dynamic>>[];
  final incomeDirty = <Map<String, dynamic>>[];

  final mergedTransactions = <Map<String, dynamic>>[];
  final mergedAccounts = <Map<String, dynamic>>[];
  final tombstoned = <String>[];
  final reoverlaid = <String>[];
  String? cursor;
  bool marked = false;

  @override
  Future<String?> syncCursor() async => cursor;
  @override
  Future<void> setSyncCursor(String serverTime) async => cursor = serverTime;
  @override
  Future<void> markSynced() async => marked = true;

  @override
  Future<List<Map<String, dynamic>>> dirtyRows(String table) async =>
      List.of(dirty[table] ?? const []);
  @override
  Future<void> clearDirty(String table, String id) async =>
      dirty[table]?.removeWhere((r) => r['id'] == id);

  @override
  Future<List<Map<String, dynamic>>> dirtyIncomeRows() async =>
      List.of(incomeDirty);
  @override
  Future<void> clearIncomeDirty(String month) async =>
      incomeDirty.removeWhere((r) => r['month'] == month);

  @override
  Future<List<Map<String, dynamic>>> pendingDeletes() async => List.of(pending);
  @override
  Future<void> removePendingDelete(String resource, String id) async => pending
      .removeWhere((r) => r['resource'] == resource && r['entity_id'] == id);

  @override
  Future<void> mergeServerTransaction(Map<String, dynamic> row) async =>
      mergedTransactions.add(row);
  @override
  Future<void> mergeServerAccount(Map<String, dynamic> row) async =>
      mergedAccounts.add(row);
  @override
  Future<void> mergeServerCategory(Map<String, dynamic> row) async {}
  @override
  Future<void> mergeServerBudget(Map<String, dynamic> row) async {}
  @override
  Future<void> mergeServerStock(Map<String, dynamic> row) async {}
  @override
  Future<void> mergeServerPortfolioTransaction(Map<String, dynamic> row) async {}
  @override
  Future<void> cacheMonthlyIncome(String m, Map<String, dynamic> r) async {}

  @override
  Future<void> applyTombstone(String resource, String entityId) async =>
      tombstoned.add('$resource:$entityId');
  @override
  Future<void> applyTransactionToBalances(
    Map<String, dynamic> txn, {
    required bool reverse,
  }) async =>
      reoverlaid.add(txn['id'].toString());

  @override
  Future<void> savePortfolioSummary(Map<String, dynamic> s) async {}
  @override
  Future<void> savePortfolios(List<Map<String, dynamic>> r) async {}
  @override
  Future<void> saveDashboardSummary(Map<String, dynamic> s) async {}
}

Map<String, dynamic> _dirtyRow(String id, int dirty) => {
  'id': id,
  'dirty': dirty,
  'raw_json': jsonEncode({'id': id, 'account_id': 'a1', 'type': 'expense', 'amount': 10}),
};

void main() {
  late _FakeDb db;
  late _FakeApi api;
  late SyncService sync;

  setUp(() {
    db = _FakeDb();
    api = _FakeApi(SessionStore());
    sync = SyncService(api, db);
  });

  test('push dispatches by dirty state (1=create, 2=update), drains deletes, '
      'and clears what succeeds', () async {
    db.dirty['transactions'] = [_dirtyRow('t1', 1), _dirtyRow('t2', 2)];
    db.pending.add({'resource': 'transactions', 'entity_id': 'd1'});

    await sync.syncAll();

    expect(api.createdTransactions.single['id'], 't1');
    expect(api.updatedTransactionIds, ['t2']);
    expect(api.deletedTransactionIds, ['d1']);
    expect(db.dirty['transactions'], isEmpty); // cleared on success
    expect(db.pending, isEmpty); // delete drained
    expect(db.cursor, '2026-07-12T00:00:00Z');
    expect(db.marked, isTrue);
  });

  test('push upserts dirty budgets (create + edit), replays budget deletes, '
      'and pushes edited income', () async {
    db.dirty['budgets'] = [
      {
        'id': 'b1',
        'dirty': 1,
        'raw_json': jsonEncode(
            {'id': 'b1', 'category_id': 'c1', 'month': '2026-07', 'amount': 800}),
      },
      {
        'id': 'b2',
        'dirty': 2,
        'raw_json': jsonEncode(
            {'id': 'b2', 'category_id': 'c2', 'month': '2026-07', 'amount': 500}),
      },
    ];
    db.pending.add({'resource': 'budgets', 'entity_id': 'b3'});
    db.incomeDirty.add(
        {'month': '2026-07', 'amount': 5000, 'opening_balance': 200});

    await sync.syncAll();

    // Both a new and an edited budget go through the idempotent upsert path.
    expect(api.upsertedBudgets.map((b) => b['id']), containsAll(['b1', 'b2']));
    expect(api.deletedBudgetIds, ['b3']);
    expect(api.savedIncome.single['month'], '2026-07');
    expect(api.savedIncome.single['amount'], 5000);
    expect(db.dirty['budgets'], isEmpty); // cleared on success
    expect(db.pending, isEmpty); // budget delete drained
    expect(db.incomeDirty, isEmpty); // income dirty cleared
  });

  test('pull merges each resource, applies tombstones and advances the cursor',
      () async {
    api.nextChanges = {
      'server_time': '2026-07-13T09:00:00Z',
      'changes': {
        'accounts': [{'id': 'a1'}],
        'transactions': [{'id': 't9'}, {'id': 't10'}],
      },
      'tombstones': [
        {'resource': 'transactions', 'entity_id': 'gone'},
      ],
    };

    await sync.syncAll();

    expect(db.mergedAccounts.single['id'], 'a1');
    expect(db.mergedTransactions.map((r) => r['id']), ['t9', 't10']);
    expect(db.tombstoned, ['transactions:gone']);
    expect(db.cursor, '2026-07-13T09:00:00Z');
  });

  test('a create that fails to push stays dirty, is re-overlaid, and the sync '
      'reports the failure', () async {
    db.dirty['transactions'] = [_dirtyRow('t1', 1)];
    api.createTransactionThrows = true;

    await expectLater(sync.syncAll(), throwsA(isA<StateError>()));

    expect(db.dirty['transactions'], isNotEmpty); // not cleared
    expect(db.reoverlaid, contains('t1')); // effect re-applied post-pull
  });
}
