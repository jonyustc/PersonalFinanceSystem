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
    required this.budgets,
    required this.stocks,
    required this.portfolioTransactions,
    required this.portfolioSummary,
    required this.isSyncing,
    required this.pendingWrites,
    required this.lastSyncAt,
    required this.themeMode,
    this.notice,
  });

  final Session? session;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> budgets;
  final List<Map<String, dynamic>> stocks;
  final List<Map<String, dynamic>> portfolioTransactions;
  final Map<String, dynamic>? portfolioSummary;
  final bool isSyncing;
  final int pendingWrites;
  final String? lastSyncAt;
  final String themeMode;
  final String? notice;

  bool get isAuthenticated => session != null;

  AppSnapshot copyWith({
    Session? session,
    bool clearSession = false,
    List<Map<String, dynamic>>? accounts,
    List<Map<String, dynamic>>? categories,
    List<Map<String, dynamic>>? transactions,
    List<Map<String, dynamic>>? budgets,
    List<Map<String, dynamic>>? stocks,
    List<Map<String, dynamic>>? portfolioTransactions,
    Map<String, dynamic>? portfolioSummary,
    bool? isSyncing,
    int? pendingWrites,
    String? lastSyncAt,
    String? themeMode,
    String? notice,
  }) {
    return AppSnapshot(
      session: clearSession ? null : session ?? this.session,
      accounts: accounts ?? this.accounts,
      categories: categories ?? this.categories,
      transactions: transactions ?? this.transactions,
      budgets: budgets ?? this.budgets,
      stocks: stocks ?? this.stocks,
      portfolioTransactions:
          portfolioTransactions ?? this.portfolioTransactions,
      portfolioSummary: portfolioSummary ?? this.portfolioSummary,
      isSyncing: isSyncing ?? this.isSyncing,
      pendingWrites: pendingWrites ?? this.pendingWrites,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      themeMode: themeMode ?? this.themeMode,
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
      await syncNow(silent: true);
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

  Future<void> updateTransaction({
    required String id,
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

    final updated = await _api.updateTransaction(id, payload);
    await _db.upsertTransaction(updated);
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> deleteTransaction(String id) async {
    await _api.deleteTransaction(id);
    await _db.deleteTransaction(id);
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    required DateTime date,
    String? notes,
    bool isCardPayment = false,
  }) async {
    final payload = {
      'from_account_id': fromAccountId,
      'to_account_id': toAccountId,
      'amount': amount,
      'transfer_date': date.toUtc().toIso8601String(),
      'notes': _blankToNull(notes),
      'is_card_payment': isCardPayment,
    };
    await _api.createTransfer(payload);
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> updateAccount({
    required String id,
    required String name,
    required String type,
    required double openingBalance,
    required String currency,
    String? color,
    String? icon,
  }) async {
    await _api.updateAccount(id, {
      'name': name,
      'type': type,
      'opening_balance': openingBalance,
      'currency': currency,
      'color': _blankToNull(color),
      'icon': _blankToNull(icon),
    });
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> createAccount({
    required String name,
    required String type,
    required double openingBalance,
    required String currency,
    String? color,
    String? icon,
    String? notes,
    String? accountSubtype,
  }) async {
    await _api.createAccount({
      'name': name,
      'type': type,
      'opening_balance': openingBalance,
      'currency': currency,
      'color': _blankToNull(color),
      'icon': _blankToNull(icon),
      'notes': _blankToNull(notes),
      'account_subtype': _blankToNull(accountSubtype),
    });
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<Map<String, dynamic>> createCategory({
    required String name,
    required String type,
    String? parentId,
  }) async {
    final created = await _api.createCategory({
      'name': name,
      'type': type,
      'parent_id': parentId,
    });
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
    return created;
  }

  Future<void> upsertBudget({
    required String categoryId,
    required String month,
    required double amount,
  }) async {
    await _api.upsertBudget({
      'category_id': categoryId,
      'month': month,
      'amount': amount,
    });
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> updateBudget({
    required String id,
    required double amount,
  }) async {
    await _api.updateBudget(id, {'amount': amount});
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> addStockHolding({
    required String symbol,
    required String name,
    required double quantity,
    required double price,
    DateTime? date,
    String? notes,
  }) async {
    await _api.createPortfolioTransaction({
      'stock': {
        'symbol': symbol.toUpperCase(),
        'name': name,
        'currency': state.asData?.value.session?.currency ?? 'BDT',
        'last_price': price,
      },
      'txn_type': 'buy',
      'quantity': quantity,
      'price': price,
      'txn_date': (date ?? DateTime.now()).toIso8601String().substring(0, 10),
      'notes': _blankToNull(notes),
    });
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> setCurrency(String currency) async {
    await _session.saveCurrency(currency);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: await _session.load() ?? current?.session));
  }

  Future<void> setThemeMode(String themeMode) async {
    await _session.saveThemeMode(themeMode);
    final current = state.asData?.value;
    state = AsyncData(
      (await _readLocal(session: await _session.load() ?? current?.session))
          .copyWith(themeMode: themeMode),
    );
  }

  Future<void> archiveAccount(String accountId) async {
    await _api.archiveAccount(accountId);
    await syncNow(silent: true);
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
      budgets: await _db.budgets(),
      stocks: await _db.stocks(),
      portfolioTransactions: await _db.portfolioTransactions(),
      portfolioSummary: await _db.portfolioSummary(),
      isSyncing: false,
      pendingWrites: await _db.pendingCount(),
      lastSyncAt: await _db.lastSyncAt(),
      themeMode: await _session.loadThemeMode(),
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
