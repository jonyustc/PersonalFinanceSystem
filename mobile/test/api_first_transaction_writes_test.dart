import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/core/api_client.dart';
import 'package:mobile/src/core/app_database.dart';
import 'package:mobile/src/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ApiClient stand-in that simulates being offline: every write fails with a
/// connection error.
class _OfflineApiClient extends ApiClient {
  _OfflineApiClient(super.sessionStore);

  DioException get _offline => DioException(
    requestOptions: RequestOptions(path: '/test'),
    type: DioExceptionType.connectionError,
  );

  @override
  Future<Map<String, dynamic>> createTransaction(
    Map<String, dynamic> payload,
  ) async {
    throw _offline;
  }

  @override
  Future<Map<String, dynamic>> updateTransaction(
    String id,
    Map<String, dynamic> payload,
  ) async {
    throw _offline;
  }

  @override
  Future<void> deleteTransaction(String id) async {
    throw _offline;
  }

  @override
  Future<Map<String, dynamic>> createTransfer(
    Map<String, dynamic> payload,
  ) async {
    throw _offline;
  }

  @override
  Future<Map<String, dynamic>> createCategory(
    Map<String, dynamic> payload,
  ) async {
    throw _offline;
  }

  @override
  Future<Map<String, dynamic>> updateCategory(
    String id,
    Map<String, dynamic> payload,
  ) async {
    throw _offline;
  }

  @override
  Future<void> deleteCategory(String id) async {
    throw _offline;
  }

  @override
  Future<Map<String, dynamic>> createPortfolioTransaction(
    Map<String, dynamic> payload,
  ) async {
    throw _offline;
  }

  @override
  Future<Map<String, dynamic>> updatePortfolioTransaction(
    String id,
    Map<String, dynamic> payload,
  ) async {
    throw _offline;
  }

  @override
  Future<void> deletePortfolioTransaction(String id) async {
    throw _offline;
  }

  @override
  Future<Map<String, dynamic>> createStock(
    Map<String, dynamic> payload,
  ) async {
    throw _offline;
  }

  @override
  Future<Map<String, dynamic>> updateStock(
    String id,
    Map<String, dynamic> payload,
  ) async {
    throw _offline;
  }
}

/// In-memory AppDatabase that records writes so tests can assert the
/// API-first paths never touch the local mirror. Enqueueing is impossible by
/// construction: AppDatabase no longer exposes any sync_queue insert API, so
/// pendingCount can only ever report legacy leftovers (none in tests).
class _RecordingDatabase extends AppDatabase {
  final List<Map<String, dynamic>> upsertedTransactions = [];
  final List<String> deletedTransactionIds = [];
  final List<Map<String, dynamic>> upsertedCategories = [];
  final List<Map<String, dynamic>> upsertedPortfolioTransactions = [];
  final List<String> deletedPortfolioTransactionIds = [];
  final List<Map<String, dynamic>> upsertedStocks = [];

  @override
  Future<void> upsertTransaction(
    Map<String, dynamic> row, {
    bool pending = false,
  }) async {
    upsertedTransactions.add(row);
  }

  @override
  Future<void> deleteTransaction(String id) async {
    deletedTransactionIds.add(id);
  }

  @override
  Future<void> upsertCategory(
    Map<String, dynamic> row, {
    bool pending = false,
  }) async {
    upsertedCategories.add(row);
  }

  @override
  Future<void> upsertPortfolioTransaction(
    Map<String, dynamic> row, {
    bool pending = false,
  }) async {
    upsertedPortfolioTransactions.add(row);
  }

  @override
  Future<void> deletePortfolioTransaction(String id) async {
    deletedPortfolioTransactionIds.add(id);
  }

  @override
  Future<void> upsertStock(Map<String, dynamic> row) async {
    upsertedStocks.add(row);
  }

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
  Future<int> pendingCount() async => 0;

  @override
  Future<String?> lastSyncAt() async => null;

  @override
  Future<List<Map<String, dynamic>>> recurringRules() async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingDatabase db;
  late ProviderContainer container;

  Future<AppController> pumpController() async {
    SharedPreferences.setMockInitialValues({});
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

  test('createTransaction fails loudly offline and does not queue', () async {
    final controller = await pumpController();

    await expectLater(
      controller.createTransaction(
        accountId: 'acc-1',
        type: 'expense',
        amount: 25,
        date: DateTime(2026, 7, 1),
      ),
      throwsA(
        isA<ApiWriteException>().having(
          (error) => error.message,
          'message',
          contains('Could not reach the server'),
        ),
      ),
    );

    expect(db.upsertedTransactions, isEmpty);
  });

  test('createTransfer fails loudly offline and does not queue', () async {
    final controller = await pumpController();

    await expectLater(
      controller.createTransfer(
        fromAccountId: 'acc-1',
        toAccountId: 'acc-2',
        amount: 100,
        date: DateTime(2026, 7, 1),
        isCardPayment: true,
      ),
      throwsA(isA<ApiWriteException>()),
    );

    expect(db.upsertedTransactions, isEmpty);
  });

  test('deleteTransaction offline keeps the local row and does not queue',
      () async {
    final controller = await pumpController();

    await expectLater(
      controller.deleteTransaction('txn-1'),
      throwsA(isA<ApiWriteException>()),
    );

    expect(db.deletedTransactionIds, isEmpty);
  });

  test('createCategory fails loudly offline with no mirror write', () async {
    final controller = await pumpController();

    await expectLater(
      controller.createCategory(name: 'Groceries', type: 'expense'),
      throwsA(
        isA<ApiWriteException>().having(
          (error) => error.message,
          'message',
          contains('Could not reach the server'),
        ),
      ),
    );

    expect(db.upsertedCategories, isEmpty);
    expect(await db.pendingCount(), 0);
  });

  test('savePortfolioTransaction fails loudly offline with no mirror write',
      () async {
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

    expect(db.upsertedPortfolioTransactions, isEmpty);
    expect(db.upsertedStocks, isEmpty);
  });

  test('deletePortfolioTransaction offline keeps the local row', () async {
    final controller = await pumpController();

    await expectLater(
      controller.deletePortfolioTransaction('ptx-1'),
      throwsA(isA<ApiWriteException>()),
    );

    expect(db.deletedPortfolioTransactionIds, isEmpty);
  });

  test('saveStock fails loudly offline with no mirror write', () async {
    final controller = await pumpController();

    await expectLater(
      controller.saveStock(name: 'Test Stock', symbol: 'TST', lastPrice: 12.5),
      throwsA(isA<ApiWriteException>()),
    );

    expect(db.upsertedStocks, isEmpty);
  });
}
