import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_client.dart';
import 'app_database.dart';

class SyncService {
  SyncService(this._api, this._db);

  final ApiClient _api;
  final AppDatabase _db;

  Future<void> syncAll() async {
    await _replayPendingWrites();

    final results = await Future.wait<_SyncResult>([
      _syncResource(
        name: 'accounts',
        fetch: _api.getAccounts,
        replace: _db.replaceAccounts,
      ),
      _syncResource(
        name: 'categories',
        fetch: _api.getCategories,
        replace: _db.replaceCategories,
      ),
      _syncResource(
        name: 'transactions',
        fetch: () => _fetchTransactions(limit: 250),
        replace: _db.replaceTransactions,
      ),
      _syncResource(
        name: 'budgets',
        fetch: () => _api.getBudgetSummaryRows(_monthKey(DateTime.now())),
        replace: _db.replaceBudgets,
      ),
      _syncResource(
        name: 'stocks',
        fetch: _api.getStocks,
        replace: _db.replaceStocks,
      ),
      _syncResource(
        name: 'portfolio transactions',
        fetch: () => _api.getPortfolioTransactions(limit: 250),
        replace: _db.replacePortfolioTransactions,
      ),
    ], eagerError: false);
    try {
      await _db.savePortfolioSummary(await _api.getPortfolioSummary());
    } catch (_) {
      // Portfolio summary is an enhancement over local holdings; keep sync
      // usable when this endpoint is temporarily unavailable.
    }
    try {
      await _db.saveDashboardSummary(
        await _api.getSimpleDashboard(_monthKey(DateTime.now())),
      );
    } catch (_) {
      // Dashboard summary (authoritative card spending/payment) is an
      // enhancement over local computation; offline falls back to local math.
    }
    if (!results.any((result) => result.synced)) {
      String? firstError;
      for (final result in results) {
        if (result.error != null) {
          firstError = result.error;
          break;
        }
      }
      throw StateError(firstError ?? 'No sync endpoints completed');
    }
    await _db.markSynced();
  }

  Future<_SyncResult> _syncResource({
    required String name,
    required Future<List<Map<String, dynamic>>> Function() fetch,
    required Future<void> Function(List<Map<String, dynamic>>) replace,
  }) async {
    try {
      await replace(await fetch());
      return _SyncResult.synced(name);
    } catch (error) {
      // Keep other datasets syncing; stale local data is better than blocking
      // budgets or portfolio because one endpoint timed out.
      return _SyncResult.failed(name, _syncError(name, error));
    }
  }

  Future<void> _replayPendingWrites() async {
    final queued = await _db.queuedMutations();
    for (final item in queued) {
      final id = item['id'] as int;
      final method = item['method'] as String;
      final path = item['path'] as String;
      final payload = (jsonDecode(item['payload_json'] as String) as Map)
          .cast<String, dynamic>();

      try {
        await _api.replayMutation(
          method,
          path,
          _normalizedReplayPayload(method, path, payload),
        );
        await _db.deleteQueuedMutation(id);
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        // A 4xx (except 408 timeout / 429 rate-limit) means the server will
        // never accept this write — drop it so it does not block the queue
        // forever ("always shows pending writes"). Network/5xx errors stay
        // queued for the next sync.
        if (status != null &&
            status >= 400 &&
            status < 500 &&
            status != 408 &&
            status != 429) {
          await _db.deleteQueuedMutation(id);
        }
      } catch (_) {
        // Non-Dio error: keep the write queued and retry on the next sync.
      }
    }
  }

  String _syncError(String name, Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) {
        return 'Session expired. Please log in again.';
      }
      if (status != null) {
        return '$name sync failed: HTTP $status';
      }
      return '$name sync failed: ${error.type.name}';
    }
    return '$name sync failed';
  }

  Map<String, dynamic> _normalizedReplayPayload(
    String method,
    String path,
    Map<String, dynamic> payload,
  ) {
    if (method == 'PATCH' && path.startsWith('/portfolio/stocks/')) {
      final normalized = {...payload};
      normalized.remove('symbol');
      return normalized;
    }
    return payload;
  }

  Future<List<Map<String, dynamic>>> _fetchTransactions({
    int limit = 250,
  }) async {
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

class _SyncResult {
  const _SyncResult({required this.name, required this.synced, this.error});

  factory _SyncResult.synced(String name) {
    return _SyncResult(name: name, synced: true);
  }

  factory _SyncResult.failed(String name, String error) {
    return _SyncResult(name: name, synced: false, error: error);
  }

  final String name;
  final bool synced;
  final String? error;
}
