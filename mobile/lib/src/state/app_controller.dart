import 'dart:async';
import 'dart:convert';

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
  (ref) => ApiClient(
    ref.watch(sessionStoreProvider),
    onSessionExpired: () =>
        ref.read(appControllerProvider.notifier).expireSession(),
  ),
);
final syncServiceProvider = Provider(
  (ref) =>
      SyncService(ref.watch(apiClientProvider), ref.watch(databaseProvider)),
);

final appControllerProvider = AsyncNotifierProvider<AppController, AppSnapshot>(
  AppController.new,
);

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
    this.authNotice,
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
  final String? authNotice;
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
    String? authNotice,
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
      authNotice: authNotice,
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
    state = AsyncData(
      (await _readLocal(
        session: session,
      )).copyWith(isSyncing: true, authNotice: null),
    );
    _startPeriodicSync();
    await syncNow();
  }

  Future<void> logout() async {
    await _session.clear();
    _timer?.cancel();
    state = AsyncData(await _readLocal(session: null));
  }

  Future<void> expireSession() async {
    await _session.clear(keepTheme: true);
    _timer?.cancel();
    final current = state.asData?.value;
    if (current == null || current.session == null) return;
    state = AsyncData(
      (await _readLocal(
        session: null,
      )).copyWith(authNotice: 'Session expired. Please log in again.'),
    );
  }

  Future<void> syncNow({bool silent = false}) async {
    final current = state.asData?.value;
    if (current == null || current.session == null || current.isSyncing) return;
    if (!silent) {
      state = AsyncData(current.copyWith(isSyncing: true, notice: null));
    }

    try {
      await _sync.syncAll();
      final synced = await _readLocal(session: await _session.load());
      final notice = synced.pendingWrites > 0
          ? 'Synced. ${synced.pendingWrites} pending writes remain.'
          : 'Synced';
      state = AsyncData(synced.copyWith(notice: notice));
    } catch (error) {
      final message = _syncErrorMessage(error);
      if (message.contains('Session expired')) {
        await expireSession();
        return;
      }
      state = AsyncData(
        (await _readLocal(
          session: message.contains('Session expired') ? null : current.session,
        )).copyWith(notice: message),
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
      await _db.applyTransactionBalance(local);
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
    String? transferAccountId,
    String? merchantName,
    String? description,
  }) async {
    final payload = {
      'account_id': accountId,
      'transfer_account_id': transferAccountId,
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
      final updated = await _api.updateTransaction(id, payload);
      await _db.upsertTransaction(updated);
      await syncNow(silent: true);
    } catch (_) {
      final oldRow = await _db.transactionById(id);
      if (oldRow != null) {
        await _db.applyTransactionBalance(_decodeRaw(oldRow), reverse: true);
      }
      final local = {...payload, 'id': id, 'payment_method': null};
      await _db.upsertTransaction(local, pending: true);
      await _db.applyTransactionBalance(local);
      await _db.queueMutation('PATCH', '/transactions/$id', payload);
    }
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> deleteTransaction(String id) async {
    try {
      await _api.deleteTransaction(id);
      await _db.deleteTransaction(id);
      await syncNow(silent: true);
    } catch (_) {
      final oldRow = await _db.transactionById(id);
      if (oldRow != null) {
        await _db.applyTransactionBalance(_decodeRaw(oldRow), reverse: true);
      }
      await _db.deleteTransaction(id);
      await _db.queueMutation('DELETE', '/transactions/$id', const {});
    }
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
    try {
      await _api.createTransfer(payload);
      await syncNow(silent: true);
    } catch (_) {
      final local = {
        'id': const Uuid().v4(),
        'account_id': fromAccountId,
        'transfer_account_id': toAccountId,
        'type': 'transfer',
        'amount': amount,
        'txn_date': date.toUtc().toIso8601String(),
        'transaction_date': date.toUtc().toIso8601String(),
        'description': _blankToNull(notes),
        'merchant_name': null,
        'payment_method': null,
        'tags': <String>[],
        'transaction_status': 'posted',
      };
      await _db.upsertTransaction(local, pending: true);
      await _db.applyTransactionBalance(local);
      await _db.queueMutation('POST', '/transfers', payload);
    }
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
    String? color,
    String? icon,
  }) async {
    final created = await _api.createCategory({
      'name': name,
      'type': type,
      'parent_id': parentId,
      'color': _blankToNull(color),
      'icon': _blankToNull(icon),
    });
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
    return created;
  }

  Future<void> updateCategory({
    required String id,
    required String name,
    required String type,
    String? parentId,
    String? color,
    String? icon,
  }) async {
    await _api.updateCategory(id, {
      'name': name,
      'type': type,
      'parent_id': parentId,
      'color': _blankToNull(color),
      'icon': _blankToNull(icon),
    });
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> deleteCategory(String id) async {
    await _api.deleteCategory(id);
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
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

  Future<void> savePortfolioTransaction({
    String? id,
    required String txnType,
    String? stockId,
    String? brokerAccountId,
    String? newStockName,
    String? newStockSymbol,
    required double quantity,
    required double price,
    double? fees,
    DateTime? date,
    String? notes,
  }) async {
    final needsStock =
        txnType == 'buy' || txnType == 'sell' || txnType == 'income';
    final useNewStock =
        needsStock &&
        (stockId == null || stockId.isEmpty) &&
        !_isBlank(newStockName);
    final payload = {
      'txn_type': txnType,
      'stock_id': _blankToNull(stockId),
      'stock': useNewStock
          ? {
              'symbol': (_blankToNull(newStockSymbol) ?? newStockName!.trim())
                  .toUpperCase(),
              'name': newStockName!.trim(),
              'exchange': 'DSE',
              'currency': state.asData?.value.session?.currency ?? 'BDT',
              'last_price': price,
            }
          : null,
      'broker_account_id': _blankToNull(brokerAccountId),
      'quantity': txnType == 'income' ? 1 : quantity,
      'price': price,
      'fees': fees,
      'txn_date': (date ?? DateTime.now()).toIso8601String().substring(0, 10),
      'notes': _blankToNull(notes),
    };
    try {
      if (id == null) {
        await _api.createPortfolioTransaction(payload);
      } else {
        await _api.updatePortfolioTransaction(id, payload);
      }
      await syncNow(silent: true);
    } catch (_) {
      final localId = id ?? const Uuid().v4();
      final stock = (payload['stock'] as Map?)?.cast<String, dynamic>();
      final resolvedStockId = stockId ?? (stock == null ? null : localId);
      if (stock != null) {
        await _db.upsertStock({'id': resolvedStockId, ...stock});
      }
      final local = _localPortfolioTransaction(
        id: localId,
        payload: payload,
        stockId: resolvedStockId,
        stock: stock,
      );
      await _db.upsertPortfolioTransaction(local, pending: true);
      await _db.queueMutation(
        id == null ? 'POST' : 'PATCH',
        id == null ? '/portfolio/transactions' : '/portfolio/transactions/$id',
        payload,
      );
    }
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> deletePortfolioTransaction(String id) async {
    try {
      await _api.deletePortfolioTransaction(id);
      await syncNow(silent: true);
    } catch (_) {
      await _db.deletePortfolioTransaction(id);
      await _db.queueMutation(
        'DELETE',
        '/portfolio/transactions/$id',
        const {},
      );
    }
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> updateStockPrice({
    required String id,
    required double lastPrice,
  }) async {
    try {
      await _api.updateStock(id, {'last_price': lastPrice});
      await syncNow(silent: true);
    } catch (_) {
      final current = state.asData?.value;
      final existing = current?.stocks
          .where((stock) => stock['id'] == id)
          .firstOrNull;
      if (existing != null) {
        await _db.upsertStock({...existing, 'last_price': lastPrice});
      }
      await _db.queueMutation('PATCH', '/portfolio/stocks/$id', {
        'last_price': lastPrice,
      });
    }
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<String> refreshStockPrices() async {
    try {
      final result = await _api.refreshStockPrices();
      await syncNow(silent: true);
      final updated = result['updated'] ?? 0;
      final missing = (result['missing_symbols'] as List? ?? [])
          .whereType<String>()
          .toList();
      final message = 'Updated $updated DSE prices';
      return missing.isEmpty ? message : '$message. Missing: ${missing.join(', ')}';
    } catch (error) {
      throw Exception('DSE price refresh failed: $error');
    } finally {
      final current = state.asData?.value;
      state = AsyncData(await _readLocal(session: current?.session));
    }
  }

  Future<List<Map<String, dynamic>>> searchDseStocks(String query) {
    return _api.searchDseStocks(query);
  }

  Future<void> saveStock({
    String? id,
    required String name,
    required String symbol,
    String? exchange,
    String? currency,
    required double lastPrice,
  }) async {
    final resolvedCurrency =
        (currency ?? state.asData?.value.session?.currency ?? 'BDT')
            .trim()
            .toUpperCase();
    final createPayload = {
      'name': name.trim(),
      'symbol': symbol.trim().toUpperCase(),
      'exchange': _blankToNull(exchange),
      'currency': resolvedCurrency.isEmpty ? 'BDT' : resolvedCurrency,
      'last_price': lastPrice,
    };
    final updatePayload = {
      'symbol': symbol.trim().toUpperCase(),
      'name': name.trim(),
      'exchange': _blankToNull(exchange),
      'currency': resolvedCurrency.isEmpty ? 'BDT' : resolvedCurrency,
      'last_price': lastPrice,
    };
    final payload = id == null ? createPayload : updatePayload;

    try {
      final saved = id == null
          ? await _api.createStock(payload)
          : await _api.updateStock(id, payload);
      await _db.upsertStock(saved);
      await syncNow(silent: true);
    } catch (_) {
      final localId = id ?? const Uuid().v4();
      await _db.upsertStock({'id': localId, ...createPayload});
      await _db.queueMutation(
        id == null ? 'POST' : 'PATCH',
        id == null ? '/portfolio/stocks' : '/portfolio/stocks/$id',
        payload,
      );
    }
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> setCurrency(String currency) async {
    await _session.saveCurrency(currency);
    final current = state.asData?.value;
    state = AsyncData(
      await _readLocal(session: await _session.load() ?? current?.session),
    );
  }

  Future<void> setThemeMode(String themeMode) async {
    await _session.saveThemeMode(themeMode);
    final current = state.asData?.value;
    state = AsyncData(
      (await _readLocal(
        session: await _session.load() ?? current?.session,
      )).copyWith(themeMode: themeMode),
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

  bool _isBlank(String? value) => _blankToNull(value) == null;

  String _syncErrorMessage(Object error) {
    final raw = error.toString();
    final marker = RegExp(
      r'(Session expired\. Please log in again\.|[A-Za-z ]+ sync failed: [^)\n]+)',
    );
    final match = marker.firstMatch(raw);
    if (match != null) {
      return match.group(0)!;
    }
    return 'Using local data. Sync failed.';
  }

  Map<String, dynamic> _decodeRaw(Map<String, dynamic> row) {
    final raw = row['raw_json'];
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      } catch (_) {
        return row;
      }
    }
    return row;
  }

  Map<String, dynamic> _localPortfolioTransaction({
    required String id,
    required Map<String, dynamic> payload,
    required String? stockId,
    required Map<String, dynamic>? stock,
  }) {
    final txnType = payload['txn_type'] as String;
    final quantity = _asDouble(payload['quantity']);
    final price = _asDouble(payload['price']);
    final fees = payload['fees'] == null
        ? _defaultPortfolioFee(txnType, quantity, price)
        : _asDouble(payload['fees']);
    final total = _portfolioTotal(txnType, quantity, price, fees);
    return {
      'id': id,
      'stock_id': stockId,
      'broker_account_id': payload['broker_account_id'],
      'txn_type': txnType,
      'quantity': quantity,
      'price': price,
      'fees': fees,
      'total_amount': total,
      'cash_flow': _portfolioCashFlow(txnType, total),
      'txn_date': payload['txn_date'],
      'notes': payload['notes'],
      'stock': stock,
    };
  }

  double _portfolioTotal(
    String txnType,
    double quantity,
    double price,
    double fees,
  ) {
    if (txnType == 'buy') return quantity * price + fees;
    if (txnType == 'sell') return quantity * price - fees;
    return price;
  }

  double _defaultPortfolioFee(String txnType, double quantity, double price) {
    if (txnType == 'buy' || txnType == 'sell') {
      return quantity * price * 0.004;
    }
    return 0;
  }

  double _portfolioCashFlow(String txnType, double total) {
    if (txnType == 'buy' || txnType == 'withdraw') return -total;
    return total;
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
