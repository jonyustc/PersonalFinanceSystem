import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/app_database.dart';
import '../core/backup_service.dart';
import '../core/google_auth.dart';
import '../core/session_store.dart';
import '../core/sync_service.dart';

final sessionStoreProvider = Provider((ref) => SessionStore());
final databaseProvider = Provider((ref) => AppDatabase());
final googleAuthServiceProvider = Provider((ref) => GoogleAuthService());
final backupServiceProvider = Provider(
  (ref) => BackupService(ref.watch(databaseProvider)),
);
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
    required this.portfolios,
    required this.portfolioAdvanced,
    required this.dashboardSummary,
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
  final List<Map<String, dynamic>> portfolios;
  final bool portfolioAdvanced;
  final Map<String, dynamic>? dashboardSummary;
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
    List<Map<String, dynamic>>? portfolios,
    bool? portfolioAdvanced,
    Map<String, dynamic>? dashboardSummary,
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
      portfolios: portfolios ?? this.portfolios,
      portfolioAdvanced: portfolioAdvanced ?? this.portfolioAdvanced,
      dashboardSummary: dashboardSummary ?? this.dashboardSummary,
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
      unawaited(materializeDueRecurring());
      unawaited(syncNow(silent: true));
    }
    return snapshot;
  }

  Future<void> login(String email, String password) async {
    final auth = await _api.login(email, password);
    await _onAuthenticated(auth);
  }

  Future<void> loginWithGoogle() async {
    final idToken = await ref.read(googleAuthServiceProvider).obtainIdToken();
    final auth = await _api.loginWithGoogle(idToken);
    await _onAuthenticated(auth);
  }

  /// Shared post-login handling. Note we publish the signed-in state with
  /// isSyncing=false (via _readLocal) BEFORE calling syncNow: syncNow guards on
  /// `isSyncing`, so pre-setting it true here would make the sync a no-op and
  /// leave the spinner stuck forever.
  Future<void> _onAuthenticated(Map<String, dynamic> auth) async {
    await _session.saveFromAuth(auth);
    final session = await _session.load();
    state = AsyncData(
      (await _readLocal(session: session)).copyWith(authNotice: null),
    );
    _startPeriodicSync();
    await syncNow();
  }

  /// Exports all local data to a shareable JSON backup file.
  Future<void> exportBackup() => ref.read(backupServiceProvider).exportBackup();

  /// Restores a picked backup file into the local database, then refreshes
  /// state. Returns false if the user cancelled the file picker.
  Future<bool> restoreBackup() async {
    final imported = await ref.read(backupServiceProvider).importBackup();
    if (!imported) return false;
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
    return true;
  }

  Future<void> logout() async {
    await _session.clear();
    // Drop all cached data + the pending-write queue so the next account does
    // not inherit this user's rows or a stuck queue.
    await _db.clearAll();
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
    final localId = const Uuid().v4();
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
      'reference_number': localId,
    };

    final local = {...payload, 'id': localId, 'payment_method': null};
    await _db.upsertTransaction(local, pending: true);
    await _db.applyTransactionBalance(local);
    await _db.queuePost('/transactions', payload);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
    unawaited(syncNow(silent: true));
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
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
    unawaited(syncNow(silent: true));
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
    final localId = const Uuid().v4();
    final payload = {
      'id': localId,
      'name': name,
      'type': type,
      'parent_id': parentId,
      'color': _blankToNull(color),
      'icon': _blankToNull(icon),
    };
    final local = {...payload, 'children': <Map<String, dynamic>>[]};
    await _db.upsertCategory(local, pending: true);
    await _db.queuePost('/categories', payload);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
    unawaited(syncNow(silent: true));
    return local;
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
    DateTime? recordDate,
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
      'record_date': txnType == 'income'
          ? recordDate?.toIso8601String().substring(0, 10)
          : null,
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

  /// Persists the "Advanced Investor Analytics" preference.
  Future<void> setPortfolioAdvanced(bool value) async {
    await _db.saveMetaJson('portfolio_advanced', {'value': value});
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  // Per-portfolio analytics: fetch live, cache, and fall back to cache offline.
  Future<Map<String, dynamic>> loadPortfolioSummaryFor(String? portfolioId) =>
      _fetchPortfolioMap(
        () => _api.getPortfolioSummary(portfolioId: portfolioId),
        'portfolio_summary_${portfolioId ?? 'all'}',
      );

  Future<Map<String, dynamic>> loadPortfolioAnalytics(String? portfolioId) =>
      _fetchPortfolioMap(
        () => _api.getPortfolioAnalytics(portfolioId: portfolioId),
        'portfolio_analytics_${portfolioId ?? 'all'}',
      );

  Future<Map<String, dynamic>> loadPortfolioAnnual(String? portfolioId) =>
      _fetchPortfolioMap(
        () => _api.getPortfolioAnnualPerformance(portfolioId: portfolioId),
        'portfolio_annual_${portfolioId ?? 'all'}',
      );

  Future<Map<String, dynamic>> loadPortfolioSeries(String? portfolioId) =>
      _fetchPortfolioMap(
        () => _api.getPortfolioPerformanceSeries(portfolioId: portfolioId),
        'portfolio_series_${portfolioId ?? 'all'}',
      );

  Future<Map<String, dynamic>> _fetchPortfolioMap(
    Future<Map<String, dynamic>> Function() fetch,
    String cacheKey,
  ) async {
    try {
      final data = await fetch();
      await _db.saveMetaJson(cacheKey, data);
      return data;
    } catch (_) {
      return (await _db.metaJson(cacheKey)) ?? const <String, dynamic>{};
    }
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
      // The backend returns a friendly message when DSE is unreachable.
      final serverMessage = (result['message'] as String?)?.trim();
      if (serverMessage != null && serverMessage.isNotEmpty) {
        return serverMessage;
      }
      final updated = result['updated'] ?? 0;
      final missing = (result['missing_symbols'] as List? ?? [])
          .whereType<String>()
          .toList();
      final message = 'Updated $updated DSE prices';
      return missing.isEmpty
          ? message
          : '$message. Missing: ${missing.join(', ')}';
    } catch (_) {
      throw Exception(
        'Could not refresh prices. Check your connection and try again.',
      );
    } finally {
      final current = state.asData?.value;
      state = AsyncData(await _readLocal(session: current?.session));
    }
  }

  Future<List<Map<String, dynamic>>> searchDseStocks(String query) {
    return _api.searchDseStocks(query);
  }

  Future<Map<String, dynamic>> getDseDividendEstimate({
    required String symbol,
    String? stockId,
    double taxRatePercent = 10,
  }) {
    return _api.getDseDividendEstimate(
      symbol: symbol,
      stockId: stockId,
      taxRatePercent: taxRatePercent,
    );
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
    // Persist to the backend so the choice survives re-login/sync (otherwise
    // saveFromAuth overwrites it with the stored user currency on next login).
    try {
      await _api.updateProfile({'currency': currency});
    } catch (_) {
      // Offline or transient failure: the local value still applies until the
      // next successful sync.
    }
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

  // ============================ RECURRING =============================

  Future<List<Map<String, dynamic>>> recurringRules() => _db.recurringRules();

  Future<void> saveRecurringRule({
    String? id,
    required String type,
    required String accountId,
    String? transferAccountId,
    String? categoryId,
    required double amount,
    String? merchantName,
    String? description,
    required String frequency,
    int intervalCount = 1,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final ruleId = id ?? const Uuid().v4();
    await _db.upsertRecurringRule({
      'id': ruleId,
      'type': type,
      'account_id': accountId,
      'transfer_account_id': _blankToNull(transferAccountId),
      'category_id': _blankToNull(categoryId),
      'amount': amount,
      'merchant_name': _blankToNull(merchantName),
      'description': _blankToNull(description),
      'frequency': frequency,
      'interval_count': intervalCount < 1 ? 1 : intervalCount,
      'next_run': _dateOnlyIso(startDate),
      'end_date': endDate == null ? null : _dateOnlyIso(endDate),
      'last_run': null,
      'created_at': DateTime.now().toIso8601String(),
    });
    await materializeDueRecurring();
  }

  Future<void> deleteRecurringRule(String id) =>
      _db.deleteRecurringRule(id);

  /// Creates any recurring transactions that have come due (up to today),
  /// advancing each rule's schedule. Safe to call repeatedly — each occurrence
  /// is created once because next_run is persisted after every creation.
  Future<void> materializeDueRecurring() async {
    final rules = await _db.recurringRules();
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    var created = false;

    for (final rule in rules) {
      var nextRun = DateTime.tryParse(rule['next_run'] as String? ?? '');
      if (nextRun == null) continue;
      final endStr = rule['end_date'] as String?;
      final end = endStr == null ? null : DateTime.tryParse(endStr);
      final frequency = rule['frequency'] as String? ?? 'monthly';
      final interval = (rule['interval_count'] as int?) ?? 1;
      String? lastRun = rule['last_run'] as String?;
      var guard = 0;

      while (!nextRun!.isAfter(todayDate) &&
          (end == null || !nextRun.isAfter(end)) &&
          guard < 120) {
        await _createFromRecurring(rule, nextRun);
        created = true;
        lastRun = _dateOnlyIso(nextRun);
        nextRun = _advanceDate(nextRun, frequency, interval);
        guard++;
      }

      await _db.upsertRecurringRule({
        ...rule,
        'next_run': _dateOnlyIso(nextRun),
        'last_run': lastRun,
      });
    }

    if (created) {
      final current = state.asData?.value;
      state = AsyncData(await _readLocal(session: current?.session));
      unawaited(syncNow(silent: true));
    }
  }

  Future<void> _createFromRecurring(
    Map<String, dynamic> rule,
    DateTime date,
  ) async {
    final type = rule['type'] as String? ?? 'expense';
    final amount = _asDouble(rule['amount']);
    if (amount <= 0) return;
    if (type == 'transfer') {
      final to = rule['transfer_account_id'] as String?;
      if (to == null) return;
      await createTransfer(
        fromAccountId: rule['account_id'] as String,
        toAccountId: to,
        amount: amount,
        date: date,
        notes: rule['description'] as String?,
      );
    } else {
      await createTransaction(
        accountId: rule['account_id'] as String,
        type: type,
        amount: amount,
        date: date,
        categoryId: rule['category_id'] as String?,
        merchantName: rule['merchant_name'] as String?,
        description: rule['description'] as String?,
      );
    }
  }

  DateTime _advanceDate(DateTime date, String frequency, int interval) {
    final n = interval < 1 ? 1 : interval;
    switch (frequency) {
      case 'daily':
        return date.add(Duration(days: n));
      case 'weekly':
        return date.add(Duration(days: 7 * n));
      case 'yearly':
        return DateTime(date.year + n, date.month, _clampDay(date.year + n, date.month, date.day));
      case 'monthly':
      default:
        final total = date.month - 1 + n;
        final year = date.year + total ~/ 12;
        final month = total % 12 + 1;
        return DateTime(year, month, _clampDay(year, month, date.day));
    }
  }

  int _clampDay(int year, int month, int day) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return day > lastDay ? lastDay : day;
  }

  String _dateOnlyIso(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(materializeDueRecurring());
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
      portfolios: await _db.portfolios(),
      portfolioAdvanced:
          (await _db.metaJson('portfolio_advanced'))?['value'] == true,
      dashboardSummary: await _db.dashboardSummary(),
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
      'record_date': payload['record_date'],
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
