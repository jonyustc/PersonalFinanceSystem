import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'app_database.dart';

/// Manual two-way merge sync.
///
/// Runs only when the user taps Sync (no timers, no post-write triggers). It
/// **pushes** locally-created/edited/deleted rows to the server first — creates
/// carry the client UUID so the server treats a replay as idempotent — then
/// **pulls** `/sync/changes?since=<cursor>` and merges the delta with
/// last-write-wins: a server row overwrites the local mirror unless that row
/// still has unpushed local changes. Server tombstones remove local rows.
///
/// Transactions, accounts, categories, budgets and monthly income are written
/// offline (their creates accept a client UUID, or upsert idempotently by a
/// natural key). Portfolio and stocks are still written online, but are pulled
/// down here for offline display.
class SyncService {
  SyncService(this._api, this._db);

  final ApiClient _api;
  final AppDatabase _db;

  Future<void> syncAll() async {
    // 1) Push local changes so the server is up to date before we pull.
    final pushError = await _pushLocalChanges();

    // 2) Pull the delta since our last watermark and merge it in.
    final cursor = await _db.syncCursor();
    final body = await _api.getSyncChanges(since: cursor);
    final changes = (body['changes'] as Map?)?.cast<String, dynamic>() ?? {};

    await _mergeList(changes['accounts'], _db.mergeServerAccount);
    await _mergeList(changes['categories'], _db.mergeServerCategory);
    await _mergeList(changes['transactions'], _db.mergeServerTransaction);
    await _mergeList(changes['budgets'], _db.mergeServerBudget);
    await _mergeList(changes['stocks'], _db.mergeServerStock);
    await _mergeList(
        changes['portfolio_transactions'], _db.mergeServerPortfolioTransaction);

    // Monthly income (per-month cache, keyed by month) so the Budgets screen
    // has income + opening balance offline.
    for (final row in (changes['monthly_income'] as List? ?? [])) {
      if (row is Map) {
        final month = row['month']?.toString();
        if (month != null && month.isNotEmpty) {
          await _db.cacheMonthlyIncome(month, row.cast<String, dynamic>());
        }
      }
    }

    for (final tomb in (body['tombstones'] as List? ?? [])) {
      if (tomb is Map) {
        await _db.applyTombstone(
          tomb['resource']?.toString() ?? '',
          tomb['entity_id']?.toString() ?? '',
        );
      }
    }

    // 3) A pulled account row carries the server's authoritative balance, which
    // resets any local drift — but it also drops the optimistic effect of a
    // local create that failed to push. Re-apply those so the display stays
    // correct until the next successful push.
    await _reoverlayUnpushedCreates();

    // 4) Refresh read-only server-computed caches for display (best effort).
    await _refreshDerivedCaches();

    // 5) Advance the watermark so the next sync only fetches newer changes.
    final serverTime = body['server_time']?.toString();
    if (serverTime != null && serverTime.isNotEmpty) {
      await _db.setSyncCursor(serverTime);
    }
    await _db.markSynced();

    if (pushError != null) throw StateError(pushError);
  }

  // ------------------------------- PUSH -------------------------------

  /// Pushes every dirty row and queued delete through the existing endpoints.
  /// Returns a user-facing message if anything failed (so the caller can warn),
  /// but always drains what it can — one bad row must not block the rest.
  Future<String?> _pushLocalChanges() async {
    String? firstError;

    void note(Object error) {
      firstError ??= _writeError(error);
    }

    // Deletes first: a create+delete done offline should net to nothing.
    for (final row in await _db.pendingDeletes()) {
      final resource = row['resource'] as String;
      final id = row['entity_id'] as String;
      try {
        await _deleteOnServer(resource, id);
        await _db.removePendingDelete(resource, id);
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        // Already gone on the server (404) is success for a delete.
        if (status == 404) {
          await _db.removePendingDelete(resource, id);
        } else {
          note(error);
        }
      }
    }

    await _pushTable('transactions', 'transactions', note);
    await _pushTable('categories', 'categories', note);
    await _pushTable('accounts', 'accounts', note);
    await _pushTable('budgets', 'budgets', note);
    await _pushIncome(note);

    return firstError;
  }

  /// Pushes every locally-edited month of income. The endpoint upserts by
  /// (user, month), so a replay is idempotent — no client id needed.
  Future<void> _pushIncome(void Function(Object) note) async {
    for (final row in await _db.dirtyIncomeRows()) {
      final month = row['month']?.toString();
      if (month == null || month.isEmpty) continue;
      try {
        await _api.saveMonthlyIncome({
          'month': month,
          'amount': row['amount'] ?? 0,
          'opening_balance': row['opening_balance'] ?? 0,
        });
        await _db.clearIncomeDirty(month);
      } catch (error) {
        note(error);
      }
    }
  }

  Future<void> _pushTable(
    String table,
    String resource,
    void Function(Object) note,
  ) async {
    for (final row in await _db.dirtyRows(table)) {
      final dirty = (row['dirty'] as int?) ?? 0;
      final payload = _decodePayload(row['raw_json']);
      if (payload == null) continue;
      final id = row['id'].toString();
      try {
        if (dirty == 1) {
          await _createOnServer(resource, payload);
        } else {
          await _updateOnServer(resource, id, payload);
        }
        await _db.clearDirty(table, id);
      } catch (error) {
        note(error);
      }
    }
  }

  Future<void> _createOnServer(String resource, Map<String, dynamic> payload) {
    switch (resource) {
      case 'transactions':
        return _api.createTransaction(payload);
      case 'categories':
        return _api.createCategory(payload);
      case 'accounts':
        return _api.createAccount(payload);
      case 'budgets':
        // Upsert (by category+month, carrying the client id) covers both a
        // first push and a replay idempotently.
        return _api.upsertBudget(payload);
    }
    return Future.value();
  }

  Future<void> _updateOnServer(
    String resource,
    String id,
    Map<String, dynamic> payload,
  ) {
    switch (resource) {
      case 'transactions':
        return _api.updateTransaction(id, payload);
      case 'categories':
        return _api.updateCategory(id, payload);
      case 'accounts':
        return _api.updateAccount(id, payload);
      case 'budgets':
        // A budget edit is the same idempotent upsert as a create.
        return _api.upsertBudget(payload);
    }
    return Future.value();
  }

  Future<void> _deleteOnServer(String resource, String id) {
    switch (resource) {
      case 'transactions':
        return _api.deleteTransaction(id);
      case 'categories':
        return _api.deleteCategory(id);
      case 'accounts':
        return _api.archiveAccount(id);
      case 'budgets':
        return _api.deleteBudget(id);
    }
    return Future.value();
  }

  // ------------------------------- PULL -------------------------------

  Future<void> _mergeList(
    dynamic rows,
    Future<void> Function(Map<String, dynamic>) merge,
  ) async {
    for (final row in (rows as List? ?? [])) {
      if (row is Map) await merge(row.cast<String, dynamic>());
    }
  }

  /// Re-applies the balance effect of transactions still marked as un-pushed
  /// local creates (dirty == 1), on top of the freshly pulled server balances.
  Future<void> _reoverlayUnpushedCreates() async {
    final dirty = await _db.dirtyRows('transactions');
    for (final row in dirty) {
      if ((row['dirty'] as int?) != 1) continue;
      final txn = _decodePayload(row['raw_json']);
      if (txn == null) continue;
      await _db.applyTransactionToBalances(txn, reverse: false);
    }
  }

  Future<void> _refreshDerivedCaches() async {
    try {
      await _db.savePortfolioSummary(await _api.getPortfolioSummary());
    } catch (_) {}
    try {
      await _db.savePortfolios(await _api.getPortfolios());
    } catch (_) {}
    try {
      await _db.saveDashboardSummary(
        await _api.getSimpleDashboard(_monthKey(DateTime.now())),
      );
    } catch (_) {}
  }

  Map<String, dynamic>? _decodePayload(Object? rawJson) {
    if (rawJson is! String || rawJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
    return null;
  }

  String _writeError(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['detail'] is String) {
        return data['detail'] as String;
      }
      final status = error.response?.statusCode;
      if (status != null) return 'Some changes were rejected (HTTP $status).';
      return 'Could not reach the server — some changes are still pending.';
    }
    return 'Some changes could not be synced.';
  }

  String _monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';
}
