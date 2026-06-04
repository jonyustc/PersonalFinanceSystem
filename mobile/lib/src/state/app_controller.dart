import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/app_database.dart';
import '../core/session_store.dart';
import '../core/sync_service.dart';

final sessionStoreProvider = Provider((ref) => SessionStore());
final databaseProvider = Provider((ref) => AppDatabase());
final apiClientProvider = Provider(
  (ref) => ApiClient(ref.watch(sessionStoreProvider)),
);
final syncServiceProvider = Provider(
  (ref) => SyncService(ref.watch(apiClientProvider), ref.watch(databaseProvider)),
);

final appControllerProvider =
    AsyncNotifierProvider<AppController, AppSnapshot>(AppController.new);

class AppSnapshot {
  const AppSnapshot({
    required this.session,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.isSyncing,
    required this.pendingWrites,
    required this.lastSyncAt,
    this.notice,
  });

  final Session? session;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> transactions;
  final bool isSyncing;
  final int pendingWrites;
  final String? lastSyncAt;
  final String? notice;

  bool get isAuthenticated => session != null;

  AppSnapshot copyWith({
    Session? session,
    bool clearSession = false,
    List<Map<String, dynamic>>? accounts,
    List<Map<String, dynamic>>? categories,
    List<Map<String, dynamic>>? transactions,
    bool? isSyncing,
    int? pendingWrites,
    String? lastSyncAt,
    String? notice,
  }) {
    return AppSnapshot(
      session: clearSession ? null : session ?? this.session,
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      transactions: transactions ?? this.transactions,
      isSyncing: isSyncing ?? this.isSyncing,
      pendingWrites: pendingWrites ?? this.pendingWrites,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      notice: notice,
    );
  }
}

class AppController extends AsyncNotifier<AppSnapshot>
    with WidgetsBindingObserver {
  Timer? _timer;

  SessionStore get _session => ref.read(sessionStoreProvider);
  AppDatabase get _db => ref.read(databaseProvider);
  ApiClient get _api => ref.read(apiClientProvider);
  SyncService get _sync => ref.read(syncServiceProvider);

  @override
  Future<AppSnapshot> build() async {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _timer?.cancel();
    });

    final session = await _session.load();
    final snapshot = await _readLocal(session: session);
    if (session != null) {
      _startPeriodicSync();
      unawaited(syncNow(silent: true));
    }
    return snapshot;
  }

  Future<void> login(String email, String password) async {
    final auth = await _api.login(email, password);
    await _session.saveFromAuth(auth);
    final session = await _session.load();
    state = AsyncData((await _readLocal(session: session)).copyWith(isSyncing: true));
    _startPeriodicSync();
    await syncNow();
  }

  Future<void> logout() async {
    await _session.clear();
    _timer?.cancel();
    state = AsyncData(await _readLocal(session: null));
  }

  Future<void> syncNow({bool silent = false}) async {
    final current = state.asData?.value;
    if (current == null || current.session == null || current.isSyncing) return;
    if (!silent) {
      state = AsyncData(current.copyWith(isSyncing: true, notice: null));
    }

    try {
      await _sync.syncAll();
      state = AsyncData(
        (await _readLocal(session: await _session.load())).copyWith(
          notice: 'Synced',
        ),
      );
    } catch (error) {
      state = AsyncData(
        (await _readLocal(session: current.session)).copyWith(
          notice: 'Using local data. Sync failed.',
        ),
      );
    }
  }

  Future<void> createTransaction({
    required String accountId,
    required String type,
    required double amount,
    required DateTime date,
    String? categoryId,
    String? merchantName,
    String? description,
  }) async {
    final payload = {
      'account_id': accountId,
      'category_id': categoryId,
      'type': type,
      'amount': amount,
      'txn_date': date.toUtc().toIso8601String(),
      'merchant_name': _blankToNull(merchantName),
      'description': _blankToNull(description),
      'tags': <String>[],
      'transaction_status': 'posted',
    };

    try {
      final created = await _api.createTransaction(payload);
      await _db.upsertTransaction(created);
      unawaited(syncNow(silent: true));
    } catch (_) {
      final local = {
        ...payload,
        'id': const Uuid().v4(),
        'payment_method': null,
      };
      await _db.upsertTransaction(local, pending: true);
      await _db.queuePost('/transactions', payload);
    }

    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncNow(silent: true));
    }
  }

  Future<AppSnapshot> _readLocal({required Session? session}) async {
    return AppSnapshot(
      session: session,
      accounts: await _db.accounts(),
      categories: await _db.categories(),
      transactions: await _db.transactions(),
      isSyncing: false,
      pendingWrites: await _db.pendingCount(),
      lastSyncAt: await _db.lastSyncAt(),
    );
  }

  void _startPeriodicSync() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => unawaited(syncNow(silent: true)),
    );
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
