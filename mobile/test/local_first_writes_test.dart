import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/core/api_client.dart';
import 'package:mobile/src/core/app_database.dart';
import 'package:mobile/src/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ApiClient stand-in that is always offline: every network call throws.
class _OfflineApiClient extends ApiClient {
  _OfflineApiClient(super.sessionStore);

  DioException get _offline => DioException(
    requestOptions: RequestOptions(path: '/test'),
    type: DioExceptionType.connectionError,
  );

  @override
  Future<Map<String, dynamic>> createPortfolioTransaction(
    Map<String, dynamic> payload,
  ) async => throw _offline;

  @override
  Future<void> deletePortfolioTransaction(String id) async => throw _offline;

  @override
  Future<Map<String, dynamic>> createStock(
    Map<String, dynamic> payload,
  ) async => throw _offline;
}

/// In-memory AppDatabase recording the local-first writes so tests can assert
/// the money-entry paths persist offline without any network call.
class _RecordingDatabase extends AppDatabase {
  final List<Map<String, dynamic>> localTransactions = [];
  final List<bool> localTransactionIsNew = [];
  final List<Map<String, dynamic>> localCategories = [];
  final List<Map<String, dynamic>> localAccounts = [];
  final List<String> queuedDeletes = [];
  final List<Map<String, dynamic>> ledgerApplied = [];
  final List<Map<String, dynamic>> localBudgets = [];
  final List<bool> localBudgetIsNew = [];
  Map<String, dynamic>? localIncome;

  @override
  Future<void> saveLocalTransaction(
    Map<String, dynamic> row, {
    required bool isNew,
  }) async {
    localTransactions.add(row);
    localTransactionIsNew.add(isNew);
  }

  @override
  Future<void> saveLocalCategory(
    Map<String, dynamic> row, {
    required bool isNew,
  }) async {
    localCategories.add(row);
  }

  @override
  Future<void> saveLocalAccount(
    Map<String, dynamic> row, {
    required bool isNew,
  }) async {
    localAccounts.add(row);
  }

  @override
  Future<void> applyTransactionToBalances(
    Map<String, dynamic> txn, {
    required bool reverse,
  }) async {
    ledgerApplied.add(txn);
  }

  @override
  Future<void> queueDelete(String resource, String id) async {
    queuedDeletes.add('$resource:$id');
  }

  @override
  Future<void> saveLocalMonthlyIncome(
    String month, {
    required double amount,
    required double openingBalance,
  }) async {
    localIncome = {
      'month': month,
      'amount': amount,
      'opening_balance': openingBalance,
    };
  }

  @override
  Future<Map<String, dynamic>?> budgetForMonthCategory(
    String month,
    String categoryId,
  ) async => null;

  @override
  Future<void> saveLocalBudget(
    Map<String, dynamic> row, {
    required bool isNew,
  }) async {
    localBudgets.add(row);
    localBudgetIsNew.add(isNew);
  }

  @override
  Future<Map<String, dynamic>?> budgetById(String id) async =>
      {'id': id, 'dirty': 0};

  @override
  Future<void> deleteBudget(String id) async {}

  @override
  Future<Map<String, dynamic>?> accountById(String id) async => null;

  @override
  Future<Map<String, dynamic>?> transactionById(String id) async => null;

  @override
  Future<void> deleteTransaction(String id) async {}

  @override
  Future<void> deleteCategory(String id) async {}

  // Reads used by build()/_readLocal.
  @override
  Future<List<Map<String, dynamic>>> accounts() async => [];
  @override
  Future<List<Map<String, dynamic>>> categories() async => [];
  @override
  Future<List<Map<String, dynamic>>> transactions() async => [];
  @override
  Future<List<Map<String, dynamic>>> budgets() async => [];
  @override
  Future<List<Map<String, dynamic>>> stocks() async => [];
  @override
  Future<List<Map<String, dynamic>>> portfolioTransactions() async => [];
  @override
  Future<Map<String, dynamic>?> portfolioSummary() async => null;
  @override
  Future<List<Map<String, dynamic>>> portfolios() async => [];
  @override
  Future<Map<String, dynamic>?> metaJson(String key) async => null;
  @override
  Future<Map<String, dynamic>?> dashboardSummary() async => null;
  @override
  Future<int> dirtyCount() async => 0;
  @override
  Future<String?> lastSyncAt() async => null;
  @override
  Future<List<Map<String, dynamic>>> recurringRules() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingDatabase db;
  late ProviderContainer container;

  Future<AppController> pumpController({
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    db = _RecordingDatabase();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWith(
          (ref) => _OfflineApiClient(ref.watch(sessionStoreProvider)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appControllerProvider.future);
    return container.read(appControllerProvider.notifier);
  }

  group('local-first money entry works offline', () {
    test('createTransaction persists locally with a client id and applies the '
        'ledger, without any network call', () async {
      final controller = await pumpController();

      await controller.createTransaction(
        accountId: 'acc-1',
        type: 'expense',
        amount: 25,
        date: DateTime(2026, 7, 1),
      );

      expect(db.localTransactions, hasLength(1));
      expect(db.localTransactionIsNew.single, isTrue);
      expect(db.localTransactions.single['id'], isNotNull);
      expect(db.ledgerApplied, hasLength(1));
    });

    test('createTransfer stores a single type=transfer row', () async {
      final controller = await pumpController();

      await controller.createTransfer(
        fromAccountId: 'acc-1',
        toAccountId: 'acc-2',
        amount: 100,
        date: DateTime(2026, 7, 1),
      );

      expect(db.localTransactions.single['type'], 'transfer');
      expect(db.localTransactions.single['transfer_account_id'], 'acc-2');
      expect(db.ledgerApplied, hasLength(1));
    });

    test('deleteTransaction of a synced row queues the deletion for replay',
        () async {
      final controller = await pumpController();

      await controller.deleteTransaction('txn-1');

      expect(db.queuedDeletes, contains('transactions:txn-1'));
    });

    test('createCategory persists locally with a client id', () async {
      final controller = await pumpController();

      final created = await controller.createCategory(
        name: 'Groceries',
        type: 'expense',
      );

      expect(created['id'], isNotNull);
      expect(db.localCategories.single['name'], 'Groceries');
    });
  });

  group('budgets & income are local-first (offline)', () {
    test('saveMonthlyBudgets writes income + a new budget locally, no network',
        () async {
      final controller = await pumpController();

      // The api client is offline; a local-first save must not throw.
      await controller.saveMonthlyBudgets(
        month: '2026-07',
        income: 5000,
        openingBalance: 200,
        upserts: [
          {'category_id': 'cat-1', 'amount': 800},
        ],
      );

      expect(db.localIncome?['amount'], 5000);
      expect(db.localIncome?['opening_balance'], 200);
      expect(db.localBudgets.single['category_id'], 'cat-1');
      expect(db.localBudgets.single['amount'], 800);
      expect(db.localBudgets.single['id'], isNotNull);
      // No existing budget for the month → treated as a new (POST-on-sync) row.
      expect(db.localBudgetIsNew.single, isTrue);
    });

    test('saveMonthlyBudgets queues a cleared budget for deletion', () async {
      final controller = await pumpController();

      await controller.saveMonthlyBudgets(
        month: '2026-07',
        income: 5000,
        openingBalance: 0,
        deleteIds: ['bud-1'],
      );

      expect(db.queuedDeletes, contains('budgets:bud-1'));
    });
  });

  group('offline session (fresh install, server down)', () {
    test('enters authenticated from a stored offline session', () async {
      final controller = await pumpController(prefs: {'offline_session': true});
      final snap = controller.state.asData!.value;
      expect(snap.isAuthenticated, isTrue);
      expect(snap.session!.isOffline, isTrue);
    });

    test('syncNow is a no-op in offline mode and prompts sign-in', () async {
      final controller = await pumpController(prefs: {'offline_session': true});

      // Must not throw or hit the network (the api client is offline-only).
      await controller.syncNow();

      final snap = controller.state.asData!.value;
      expect(snap.isSyncing, isFalse);
      expect(snap.notice, contains('Sign in'));
    });
  });

  group('portfolio & stock writes remain online-only', () {
    test('savePortfolioTransaction fails loudly offline', () async {
      final controller = await pumpController();

      await expectLater(
        controller.savePortfolioTransaction(
          txnType: 'buy',
          newStockName: 'Test Stock',
          newStockSymbol: 'TST',
          quantity: 10,
          price: 25,
          date: DateTime(2026, 7, 1),
        ),
        throwsA(isA<ApiWriteException>()),
      );
    });

    test('saveStock fails loudly offline', () async {
      final controller = await pumpController();

      await expectLater(
        controller.saveStock(name: 'Test Stock', symbol: 'TST', lastPrice: 12.5),
        throwsA(isA<ApiWriteException>()),
      );
    });
  });
}
