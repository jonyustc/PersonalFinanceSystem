import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/core/api_client.dart';
import 'package:mobile/src/core/app_database.dart';
import 'package:mobile/src/state/app_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ApiClient stand-in that simulates being offline: every transaction or
/// transfer write fails with a connection error.
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
}

/// In-memory AppDatabase that records writes so tests can assert the
/// API-first paths never touch the local mirror or the sync queue.
class _RecordingDatabase extends AppDatabase {
  final List<String> queuedPaths = [];
  final List<Map<String, dynamic>> upsertedTransactions = [];
  final List<String> deletedTransactionIds = [];

  @override
  Future<void> queueMutation(
    String method,
    String path,
    Map<String, dynamic> payload,
  ) async {
    queuedPaths.add('$method $path');
  }

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
  Future<int> pendingCount() async => queuedPaths.length;

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

    expect(db.queuedPaths, isEmpty);
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

    expect(db.queuedPaths, isEmpty);
    expect(db.upsertedTransactions, isEmpty);
  });

  test('deleteTransaction offline keeps the local row and does not queue',
      () async {
    final controller = await pumpController();

    await expectLater(
      controller.deleteTransaction('txn-1'),
      throwsA(isA<ApiWriteException>()),
    );

    expect(db.queuedPaths, isEmpty);
    expect(db.deletedTransactionIds, isEmpty);
  });
}
