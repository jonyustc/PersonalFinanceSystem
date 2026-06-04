import 'dart:convert';

import 'api_client.dart';
import 'app_database.dart';

class SyncService {
  SyncService(this._api, this._db);

  final ApiClient _api;
  final AppDatabase _db;

  Future<void> syncAll() async {
    await _replayPendingWrites();

    final accounts = await _api.getAccounts();
    final categories = await _api.getCategories();
    final transactions = await _fetchAllTransactions();

    await _db.replaceAccounts(accounts);
    await _db.replaceCategories(categories);
    await _db.replaceTransactions(transactions);
    await _db.markSynced();
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

  Future<List<Map<String, dynamic>>> _fetchAllTransactions() async {
    const limit = 100;
    var offset = 0;
    final items = <Map<String, dynamic>>[];

    while (true) {
      final page = await _api.getTransactions(limit: limit, offset: offset);
      final pageItems = (page['items'] as List? ?? [])
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList();
      items.addAll(pageItems);

      final next = page['next_offset'];
      if (next == null) break;
      offset = next as int;
    }

    return items;
  }
}
