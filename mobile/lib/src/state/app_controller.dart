import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/app_database.dart';
import '../core/backup_service.dart';
import '../core/backup_settings.dart';
import '../core/google_auth.dart';
import '../core/google_drive_backup.dart';
import '../core/local_ledger.dart';
import '../core/session_store.dart';
import '../core/sync_service.dart';

final sessionStoreProvider = Provider((ref) => SessionStore());
final databaseProvider = Provider((ref) => AppDatabase());
final googleAuthServiceProvider = Provider((ref) => GoogleAuthService());
final backupServiceProvider = Provider(
  (ref) => BackupService(ref.watch(databaseProvider)),
);
final backupSettingsStoreProvider = Provider((ref) => BackupSettingsStore());
final googleDriveBackupProvider = Provider(
  (ref) => GoogleDriveBackup(ref.watch(googleAuthServiceProvider)),
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
  static const _uuid = Uuid();

  SessionStore get _session => ref.read(sessionStoreProvider);
  AppDatabase get _db => ref.read(databaseProvider);
  ApiClient get _api => ref.read(apiClientProvider);
  SyncService get _sync => ref.read(syncServiceProvider);

  @override
  Future<AppSnapshot> build() async {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
    });

    final session = await _session.load();
    final snapshot = await _readLocal(session: session);
    if (session != null) {
      // Manual sync only: startup reads local data and materializes any due
      // recurring entries (a local operation) but never auto-syncs. The user
      // pulls fresh data with the Sync button.
      unawaited(materializeDueRecurring());
      unawaited(maybeRunScheduledBackup());
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
    // If we were in an offline session for a DIFFERENT account, drop that data
    // so two users' rows never mix. Same-user offline edits are kept and pushed
    // on the sync below.
    final user = (auth['user'] as Map?)?.cast<String, dynamic>() ?? {};
    final newEmail = (user['email'] ?? '').toString();
    final prevProfile = await _db.metaJson('profile');
    final prevEmail = (prevProfile?['email'] ?? '').toString();
    if (prevEmail.isNotEmpty && prevEmail != newEmail) {
      await _db.clearAll();
      await _db.clearSyncCursor();
    }
    await _session.saveFromAuth(auth);
    final session = await _session.load();
    await _persistProfile(session);
    state = AsyncData(
      (await _readLocal(session: session)).copyWith(authNotice: null),
    );
    // A one-time pull right after sign-in so a fresh install has data; from
    // then on syncing is manual (the Sync button).
    await syncNow();
  }

  /// Persists the signed-in identity into the local DB so it rides along in
  /// backups and can rebuild an offline session on a fresh, server-less install.
  Future<void> _persistProfile(Session? session) async {
    if (session == null) return;
    await _db.saveMetaJson('profile', {
      'userName': session.userName,
      'email': session.email,
      'currency': session.currency,
    });
  }

  /// Enters the app from a backup file with NO server login — for a fresh
  /// install while the backend is unreachable. Imports the backup, recovers the
  /// identity it carries, and starts an offline session. Returns false if the
  /// user cancelled the file picker.
  Future<bool> restoreBackupOffline() async {
    final imported = await ref.read(backupServiceProvider).importBackup();
    if (!imported) return false;
    // The restored data predates the server; force a full pull on first sync.
    await _db.clearSyncCursor();
    final profile = await _db.metaJson('profile');
    await _session.saveOfflineSession(
      userName: (profile?['userName'] ?? 'Offline user').toString(),
      email: (profile?['email'] ?? '').toString(),
      currency: (profile?['currency'] ?? 'BDT').toString(),
    );
    state = AsyncData(await _readLocal(session: await _session.load()));
    return true;
  }

  /// Exports all local data to a shareable JSON backup file.
  Future<void> exportBackup() => ref.read(backupServiceProvider).exportBackup();

  /// Best-effort silent recovery copy of the local DB. Skipped when signed out.
  /// Never throws — auto-backup must not disrupt normal use.
  Future<void> _autoBackup() async {
    if (state.asData?.value.session == null) return;
    final file = await ref.read(backupServiceProvider).autoBackup();
    if (file != null) {
      await _db.saveMetaJson('auto_backup_at', {
        'at': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Timestamp of the last successful auto-backup, if any (for Settings).
  Future<String?> lastAutoBackupAt() async =>
      (await _db.metaJson('auto_backup_at'))?['at'] as String?;

  /// Shares the latest auto-backup so the user can push it to Drive/Files.
  Future<bool> exportLatestAutoBackup() =>
      ref.read(backupServiceProvider).shareLatestAutoBackup();

  // ------------------------- Scheduled backups -------------------------

  Future<BackupSettings> loadBackupSettings() =>
      ref.read(backupSettingsStoreProvider).load();

  Future<void> setBackupFrequency(BackupFrequency frequency) =>
      ref.read(backupSettingsStoreProvider).setFrequency(frequency);

  /// Picks a folder, verifies it is actually writable by backing up into it,
  /// then remembers it. Returns a user-facing status message.
  Future<String> chooseBackupFolder() async {
    final path = await ref.read(backupServiceProvider).pickBackupFolder();
    if (path == null) return 'No folder selected.';
    try {
      await ref.read(backupServiceProvider).writeBackup(dir: path);
    } catch (_) {
      return "That folder can't be written to on this device. Backups will use "
          'app storage — use Export to save a copy elsewhere.';
    }
    await ref.read(backupSettingsStoreProvider).setCustomDir(path);
    await ref.read(backupSettingsStoreProvider).markBackedUp(path);
    return 'Backup folder set. A copy was saved there.';
  }

  Future<void> clearBackupFolder() =>
      ref.read(backupSettingsStoreProvider).setCustomDir(null);

  /// Connects a Google account for Drive backup, uploads immediately, and
  /// remembers it. Returns the connected email.
  Future<String> connectDrive() async {
    final email = await ref.read(googleDriveBackupProvider).connect();
    await ref.read(backupSettingsStoreProvider).setDriveEmail(email);
    // Seed Drive with the current data right away.
    await ref
        .read(googleDriveBackupProvider)
        .upload(await ref.read(backupServiceProvider).exportJson(), interactive: true);
    await ref.read(backupSettingsStoreProvider).markBackedUp('Google Drive');
    return email;
  }

  Future<void> disconnectDrive() async {
    await ref.read(googleDriveBackupProvider).disconnect();
    await ref.read(backupSettingsStoreProvider).setDriveEmail(null);
  }

  /// Downloads the Drive backup and restores it locally. Returns false if no
  /// Drive backup exists yet.
  Future<bool> restoreFromDrive() async {
    final content = await ref.read(googleDriveBackupProvider).download();
    if (content == null) return false;
    await ref.read(backupServiceProvider).importJson(content);
    await _db.clearSyncCursor();
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
    return true;
  }

  /// Manual "Back up now": writes to the configured destination(s) and records
  /// it. Returns the destination label. Throws on local write failure.
  Future<String> runManualBackup() async {
    final store = ref.read(backupSettingsStoreProvider);
    final settings = await store.load();
    final file =
        await ref.read(backupServiceProvider).writeBackup(dir: settings.customDir);
    var where = settings.customDir == null ? 'App storage' : file.parent.path;
    if (settings.driveEnabled) {
      try {
        await ref
            .read(googleDriveBackupProvider)
            .upload(await ref.read(backupServiceProvider).exportJson());
        where = '$where + Google Drive';
      } catch (_) {
        where = '$where (Drive upload failed — reconnect in Backup settings)';
      }
    }
    await store.markBackedUp(where);
    return where;
  }

  /// Runs a scheduled backup if the chosen frequency says one is due. Called on
  /// app open/resume — a reliable "run if due" that needs no background worker.
  Future<void> maybeRunScheduledBackup() async {
    if (state.asData?.value.session == null) return;
    final store = ref.read(backupSettingsStoreProvider);
    final settings = await store.load();
    if (!settings.isDue) return;
    var where = 'App storage';
    try {
      final file = await ref
          .read(backupServiceProvider)
          .writeBackup(dir: settings.customDir);
      where = settings.customDir == null ? 'App storage' : file.parent.path;
    } catch (_) {
      // A custom folder may have become unwritable; fall back to app storage.
      try {
        await ref.read(backupServiceProvider).writeBackup();
      } catch (_) {}
    }
    if (settings.driveEnabled) {
      try {
        await ref
            .read(googleDriveBackupProvider)
            .upload(await ref.read(backupServiceProvider).exportJson());
        where = '$where + Google Drive';
      } catch (_) {
        // Silent for scheduled runs; the local copy still succeeded.
      }
    }
    await store.markBackedUp(where);
  }

  /// Restores a picked backup file into the local database, then refreshes
  /// state. Returns false if the user cancelled the file picker.
  Future<bool> restoreBackup() async {
    final imported = await ref.read(backupServiceProvider).importBackup();
    if (!imported) return false;
    // The restored data may predate the server, so force the next sync to do a
    // full pull-and-reconcile rather than a delta from a stale watermark.
    await _db.clearSyncCursor();
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
    return true;
  }

  Future<void> logout() async {
    // Keep local data on the device: signing out just returns to the login
    // screen. Signing back in with the SAME account is then instant and works
    // offline; if a DIFFERENT account signs in, `_onAuthenticated` clears the
    // mismatched data (it compares the stored profile email).
    await _session.clear(keepTheme: true);
    state = AsyncData(await _readLocal(session: null));
  }

  Future<void> expireSession() async {
    // An offline session has no server token to expire; a stray 401 from a
    // best-effort API call must not kick the user out of offline mode.
    if (state.asData?.value.session?.isOffline == true) return;
    await _session.clear(keepTheme: true);
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
    // Offline sessions carry no token; there is nothing to sync until sign-in.
    if (current.session!.isOffline) {
      if (!silent) {
        state = AsyncData(current.copyWith(
          notice: 'You\'re offline. Sign in to sync your data.',
        ));
      }
      return;
    }
    if (!silent) {
      state = AsyncData(current.copyWith(isSyncing: true, notice: null));
    }

    try {
      await _sync.syncAll();
      final synced = await _readLocal(session: await _session.load());
      final notice = synced.pendingWrites > 0
          ? 'Synced. ${synced.pendingWrites} changes still to sync.'
          : 'Synced';
      state = AsyncData(synced.copyWith(notice: notice));
      // Keep a fresh local recovery copy after a successful sync.
      unawaited(_autoBackup());
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

  // Transactions, transfers, accounts and categories are LOCAL-FIRST: the row
  // is written to SQLite with a client-generated UUID, marked dirty, and its
  // balance effect applied on-device — no server call. The Sync button pushes
  // dirty rows (idempotent by that UUID) and pulls authoritative data back.
  Future<void> createTransaction({
    required String accountId,
    required String type,
    required double amount,
    required DateTime date,
    String? categoryId,
    String? merchantName,
    String? description,
    bool includeInTotals = true,
    String? counterpartyName,
    String? debtType,
  }) async {
    final payload = <String, dynamic>{
      'id': _uuid.v4(),
      'account_id': accountId,
      'category_id': categoryId,
      'type': type,
      'amount': amount,
      'txn_date': date.toUtc().toIso8601String(),
      'merchant_name': _blankToNull(merchantName),
      'description': _blankToNull(description),
      'tags': <String>[],
      'transaction_status': 'posted',
      'include_in_totals': includeInTotals,
      'counterparty_name': _blankToNull(counterpartyName),
      'debt_type': _blankToNull(debtType),
    };
    await _db.saveLocalTransaction(payload, isNew: true);
    await _db.applyTransactionToBalances(payload, reverse: false);
    await _publishLocal();
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
    bool includeInTotals = true,
    String? counterpartyName,
    String? debtType,
  }) async {
    // Reverse the previous version's balance effect before applying the new one.
    final old = await _db.transactionById(id);
    if (old != null) {
      final oldTxn = _decodeRaw(old['raw_json']) ?? old;
      await _db.applyTransactionToBalances(oldTxn, reverse: true);
    }
    final payload = <String, dynamic>{
      'id': id,
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
      'include_in_totals': includeInTotals,
      'counterparty_name': _blankToNull(counterpartyName),
      'debt_type': _blankToNull(debtType),
    };
    await _db.saveLocalTransaction(payload, isNew: false);
    await _db.applyTransactionToBalances(payload, reverse: false);
    await _publishLocal();
  }

  Future<void> deleteTransaction(String id) async {
    final old = await _db.transactionById(id);
    if (old != null) {
      final oldTxn = _decodeRaw(old['raw_json']) ?? old;
      await _db.applyTransactionToBalances(oldTxn, reverse: true);
    }
    final wasNeverPushed = (old?['dirty'] as int?) == 1;
    await _db.deleteTransaction(id);
    // A row the server already knows about needs its deletion replayed; a
    // purely local (never-pushed) row just disappears.
    if (!wasNeverPushed) await _db.queueDelete('transactions', id);
    await _publishLocal();
  }

  Future<void> createTransfer({
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    required DateTime date,
    String? notes,
    bool isCardPayment = false,
  }) async {
    // A transfer is stored as a single type=transfer transaction row (the
    // backend applies both account balances from one row). CARD_PAYMENT /
    // CARD_SPENDING is derived from the two accounts' types.
    final fromRow = await _db.accountById(fromAccountId) ?? {'type': 'cash'};
    final toRow = await _db.accountById(toAccountId);
    final transferType = normalizeTransferType(fromRow, toRow);
    final payload = <String, dynamic>{
      'id': _uuid.v4(),
      'account_id': fromAccountId,
      'transfer_account_id': toAccountId,
      'type': 'transfer',
      'transaction_type': transferType == 'transfer' ? null : transferType,
      'amount': amount,
      'txn_date': date.toUtc().toIso8601String(),
      'description': _blankToNull(notes),
      'tags': <String>[],
      'transaction_status': 'posted',
      'include_in_totals': true,
    };
    await _db.saveLocalTransaction(payload, isNew: true);
    await _db.applyTransactionToBalances(payload, reverse: false);
    await _publishLocal();
  }

  /// Re-reads the local mirror and publishes it as the current snapshot.
  Future<void> _publishLocal() async {
    final current = state.asData?.value;
    state = AsyncData(await _readLocal(session: current?.session));
  }

  Map<String, dynamic>? _decodeRaw(Object? rawJson) {
    if (rawJson is! String || rawJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
    return null;
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
    final isCard = type == 'card' || type == 'credit_card';
    final payload = <String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'opening_balance': openingBalance,
      'currency': currency,
      'color': _blankToNull(color),
      'icon': _blankToNull(icon),
      // Preserve the already-computed running balance; opening-balance edits
      // are reconciled authoritatively on the next sync.
      'balance': (await _db.accountById(id))?['balance'],
      'current_outstanding': (await _db.accountById(id))?['current_outstanding'],
    };
    await _db.saveLocalAccount(payload, isNew: false);
    // Keep display_balance in step with the type in case it changed.
    if (!isCard) {
      await _db.setAccountBalance(id,
          balance: _asDouble(payload['balance']), outstanding: 0, isCard: false);
    }
    await _publishLocal();
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
    final isCard = type == 'card' || type == 'credit_card';
    final opening = isCard ? 0.0 : openingBalance;
    final payload = <String, dynamic>{
      'id': _uuid.v4(),
      'name': name,
      'type': type,
      'opening_balance': openingBalance,
      'currency': currency,
      'color': _blankToNull(color),
      'icon': _blankToNull(icon),
      'notes': _blankToNull(notes),
      'account_subtype': _blankToNull(accountSubtype),
      // Seed the mirror's running balance so the new account shows immediately.
      'balance': opening,
      'current_outstanding': 0,
      'display_balance': opening,
      'is_active': true,
      'archived': false,
    };
    await _db.saveLocalAccount(payload, isNew: true);
    await _publishLocal();
  }

  Future<Map<String, dynamic>> createCategory({
    required String name,
    required String type,
    String? parentId,
    String? color,
    String? icon,
  }) async {
    final payload = <String, dynamic>{
      'id': _uuid.v4(),
      'name': name,
      'type': type,
      'parent_id': parentId,
      'color': _blankToNull(color),
      'icon': _blankToNull(icon),
    };
    await _db.saveLocalCategory(payload, isNew: true);
    await _publishLocal();
    return payload;
  }

  Future<void> updateCategory({
    required String id,
    required String name,
    required String type,
    String? parentId,
    String? color,
    String? icon,
  }) async {
    final payload = <String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'parent_id': parentId,
      'color': _blankToNull(color),
      'icon': _blankToNull(icon),
    };
    await _db.saveLocalCategory(payload, isNew: false);
    await _publishLocal();
  }

  Future<void> deleteCategory(String id) async {
    final existing = await _db.categories();
    final wasNeverPushed = existing.any(
      (row) => row['id'] == id && (row['dirty'] as int?) == 1,
    );
    await _db.deleteCategory(id);
    if (!wasNeverPushed) await _db.queueDelete('categories', id);
    await _publishLocal();
  }

  /// Saves a whole month's budget LOCAL-FIRST: the monthly income row, every
  /// per-category budget amount, and deletions for cleared amounts are written
  /// to SQLite and marked dirty. Nothing is sent to the server here — the Sync
  /// button pushes the dirty rows (idempotently) and pulls authoritative data
  /// back. Works fully offline.
  Future<void> saveMonthlyBudgets({
    required String month,
    required double income,
    required double openingBalance,
    List<Map<String, dynamic>> upserts = const [],
    List<String> deleteIds = const [],
  }) async {
    await _db.saveLocalMonthlyIncome(
      month,
      amount: income,
      openingBalance: openingBalance,
    );
    for (final entry in upserts) {
      final categoryId = entry['category_id'].toString();
      // Reuse the existing budget's id (an edit) or mint one (a new budget) so
      // the row maps to a single server budget on push.
      final existing = await _db.budgetForMonthCategory(month, categoryId);
      final id = existing?['id']?.toString() ?? _uuid.v4();
      await _db.saveLocalBudget(
        {
          'id': id,
          'category_id': categoryId,
          'month': month,
          'amount': _asDouble(entry['amount']),
        },
        isNew: existing == null,
      );
    }
    for (final id in deleteIds) {
      final existing = await _db.budgetById(id);
      final wasNeverPushed = (existing?['dirty'] as int?) == 1;
      await _db.deleteBudget(id);
      // A budget the server already knows about needs its deletion replayed; a
      // purely local (never-pushed) one just disappears.
      if (!wasNeverPushed) await _db.queueDelete('budgets', id);
    }
    await _publishLocal();
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
    await _publishLocal();
  }

  Future<void> deletePortfolioTransaction(String id) async {
    await _writeToServer(() => _api.deletePortfolioTransaction(id));
    await _db.deletePortfolioTransaction(id);
    await _publishLocal();
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
      // Server prices are updated; portfolio values refresh on the next sync.
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
    await _publishLocal();
  }

  Future<void> setCurrency(String currency) async {
    await _session.saveCurrency(currency);
    final current = state.asData?.value;
    final session = await _session.load() ?? current?.session;
    await _persistProfile(session);
    state = AsyncData(await _readLocal(session: session));
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
    // Local-first: hide it now, queue the archive to replay on sync (unless the
    // account was only ever local and never pushed).
    final row = await _db.accountById(accountId);
    final wasNeverPushed = (row?['dirty'] as int?) == 1;
    await _db.archiveLocalAccount(accountId);
    if (!wasNeverPushed) await _db.queueDelete('accounts', accountId);
    await _publishLocal();
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
          // Writes are local-first so this rarely fails, but if a local write
          // errors, stop without advancing the schedule; the occurrence is
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
      await _publishLocal();
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
    // Materialize due recurring entries (a local-only operation) on resume;
    // never auto-sync — the user syncs manually.
    if (state == AppLifecycleState.resumed) {
      unawaited(materializeDueRecurring());
      unawaited(maybeRunScheduledBackup());
    }
    // Refresh the local recovery copy when the app goes to the background.
    if (state == AppLifecycleState.paused) {
      unawaited(_autoBackup());
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
      pendingWrites: await _db.dirtyCount(),
      lastSyncAt: await _db.lastSyncAt(),
      themeMode: await _session.loadThemeMode(),
    );
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  bool _isBlank(String? value) => _blankToNull(value) == null;

  String _syncErrorMessage(Object error) {
    // A partial-push failure surfaces as a StateError carrying a friendly
    // message from SyncService; show it verbatim.
    if (error is StateError) return error.message;
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status != null) return 'Sync failed (HTTP $status).';
      return 'Could not reach the server. Your changes are saved locally.';
    }
    final raw = error.toString();
    if (raw.contains('Session expired')) {
      return 'Session expired. Please log in again.';
    }
    return 'Sync failed. Your changes are saved locally.';
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }
}
