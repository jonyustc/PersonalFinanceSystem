import 'dart:convert';

import 'api_client.dart';
import 'app_database.dart';

class SyncService {
  SyncService(this._api, this._db);

  final ApiClient _api;
  final AppDatabase _db;

  Future<void> syncAll() async {
    await _replayPendingWrites();

    final results = await Future.wait<bool>([
      _syncResource(
        fetch: _api.getAccounts,
        replace: _db.replaceAccounts,
      ),
      _syncResource(
        fetch: _api.getCategories,
        replace: _db.replaceCategories,
      ),
      _syncResource(
        fetch: () => _fetchTransactions(limit: 250),
        replace: _db.replaceTransactions,
      ),
      _syncResource(
        fetch: () => _api.getBudgets(_monthKey(DateTime.now())),
        replace: _db.replaceBudgets,
      ),
      _syncResource(
        fetch: _api.getStocks,
        replace: _db.replaceStocks,
      ),
      _syncResource(
        fetch: () => _api.getPortfolioTransactions(limit: 250),
        replace: _db.replacePortfolioTransactions,
      ),
    ], eagerError: false);
    if (!results.any((synced) => synced)) {
      throw StateError('No sync endpoints completed');
    }
    await _db.markSynced();
  }

  Future<bool> _syncResource({
    required Future<List<Map<String, dynamic>>> Function() fetch,
    required Future<void> Function(List<Map<String, dynamic>>) replace,
  }) async {
    try {
      await replace(await fetch());
      return true;
    } catch (_) {
      // Keep other datasets syncing; stale local data is better than blocking
      // budgets or portfolio because one endpoint timed out.
      return false;
    }
  }

  Future<void> _replayPendingWrites() async {
    final queued = await _db.queuedMutations();
    for (final item in queued) {
      final id = item['id'] as int;
      final method = item['method'] as String;
      final path = item['path'] as String;
      final payload =
          (jsonDecode(item['payload_json'] as String) as Map).cast<String, dynamic>();

      if (method == 'POST') {
        await _api.post(path, payload);
        await _db.deleteQueuedMutation(id);
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchTransactions({int limit = 250}) async {
    final page = await _api.getTransactions(limit: limit, offset: 0);
    return (page['items'] as List? ?? [])
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
  }

  String _monthKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}';
  }
}
