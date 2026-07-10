import 'dart:async';

import 'package:dio/dio.dart';
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

/// A server write that could not be committed (offline, timeout, or the
/// server rejected the payload). `toString` returns the user-facing message
/// so call sites can show it in a SnackBar directly.
class ApiWriteException implements Exception {
  ApiWriteException(this.message);

  final String message;

  @override
  String toString() => message;
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

  // All writes are API-first: the write must reach the server (which owns
  // ids and domain math) or fail loudly with an [ApiWriteException] — no
  // optimistic local insert and no offline queueing on any write path.
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

    final created = await _writeToServer(
      () => _api.createTransaction(payload),
    );
    if (created['id'] != null) {
      await _db.upsertTransaction(created);
    }
    await syncNow(silent: true);
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

    final updated = await _writeToServer(
      () => _api.updateTransaction(id, payload),
    );
    if (updated['id'] != null) {
      await _db.upsertTransaction(updated);
    }
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> deleteTransaction(String id) async {
    await _writeToServer(() => _api.deleteTransaction(id));
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
    // The response is a transfer record, not a transaction row, so the local
    // mirror is refreshed by the pull in syncNow rather than an upsert here.
    await _writeToServer(() => _api.createTransfer(payload));
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  /// Runs a server write and converts transport/HTTP failures into a clean
  /// user-facing [ApiWriteException]. API-first: failures are surfaced to the
  /// caller instead of being queued for later sync.
  Future<T> _writeToServer<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw ApiWriteException(_writeErrorMessage(error));
    }
  }

  String _writeErrorMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    final status = error.response?.statusCode;
    if (status != null) {
      return 'The server rejected this change (HTTP $status).';
    }
    return 'Could not reach the server — check your connection and try again.';
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
    await _writeToServer(
      () => _api.updateAccount(id, {
        'name': name,
        'type': type,
        'opening_balance': openingBalance,
        'currency': currency,
        'color': _blankToNull(color),
        'icon': _blankToNull(icon),
      }),
    );
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
    await _writeToServer(
      () => _api.createAccount({
        'name': name,
        'type': type,
        'opening_balance': openingBalance,
        'currency': currency,
        'color': _blankToNull(color),
        'icon': _blankToNull(icon),
        'notes': _blankToNull(notes),
        'account_subtype': _blankToNull(accountSubtype),
      }),
    );
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
    final payload = {
      'name': name,
      'type': type,
      'parent_id': parentId,
      'color': _blankToNull(color),
      'icon': _blankToNull(icon),
    };
    final created = await _writeToServer(() => _api.createCategory(payload));
    if (created['id'] != null) {
      await _db.upsertCategory(created);
    }
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
    final updated = await _writeToServer(
      () => _api.updateCategory(id, {
        'name': name,
        'type': type,
        'parent_id': parentId,
        'color': _blankToNull(color),
        'icon': _blankToNull(icon),
      }),
    );
    if (updated['id'] != null) {
      await _db.upsertCategory(updated);
    }
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> deleteCategory(String id) async {
    await _writeToServer(() => _api.deleteCategory(id));
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> upsertBudget({
    required String categoryId,
    required String month,
    required double amount,
  }) async {
    await _writeToServer(
      () => _api.upsertBudget({
        'category_id': categoryId,
        'month': month,
        'amount': amount,
      }),
    );
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> updateBudget({
    required String id,
    required double amount,
  }) async {
    await _writeToServer(() => _api.updateBudget(id, {'amount': amount}));
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  /// Saves a whole month's budget in one pass: the monthly income row, every
  /// per-category budget amount, and deletions for cleared amounts — then a
  /// single sync. Any failed write aborts with an [ApiWriteException].
  Future<void> saveMonthlyBudgets({
    required String month,
    required double income,
    required double openingBalance,
    List<Map<String, dynamic>> upserts = const [],
    List<String> deleteIds = const [],
  }) async {
    await _writeToServer(
      () => _api.saveMonthlyIncome({
        'month': month,
        'amount': income,
        'opening_balance': openingBalance,
      }),
    );
    for (final entry in upserts) {
      await _writeToServer(() => _api.upsertBudget({...entry, 'month': month}));
    }
    for (final id in deleteIds) {
      await _writeToServer(() => _api.deleteBudget(id));
    }
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
    final saved = await _writeToServer(
      () => id == null
          ? _api.createPortfolioTransaction(payload)
          : _api.updatePortfolioTransaction(id, payload),
    );
    if (saved['id'] != null) {
      await _db.upsertPortfolioTransaction(saved);
    }
    await syncNow(silent: true);
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Future<void> deletePortfolioTransaction(String id) async {
    await _writeToServer(() => _api.deletePortfolioTransaction(id));
    await _db.deletePortfolioTransaction(id);
    await syncNow(silent: true);
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

    final saved = await _writeToServer(
      () => id == null
          ? _api.createStock(payload)
          : _api.updateStock(id, payload),
    );
    if (saved['id'] != null) {
      await _db.upsertStock(saved);
    }
    await syncNow(silent: true);
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
    await _writeToServer(() => _api.archiveAccount(accountId));
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
        try {
          await _createFromRecurring(rule, nextRun);
        } catch (_) {
          // Transaction writes are API-first, so creation can fail while
          // offline. Stop without advancing the schedule; the occurrence is
          // retried on the next materialization pass.
          break;
        }
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

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
