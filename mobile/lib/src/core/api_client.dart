import 'package:dio/dio.dart';

import 'session_store.dart';

const productionApiBaseUrl = 'https://personalfinancesystem.onrender.com/api/v1';

class ApiClient {
  ApiClient(this._sessionStore)
      : _dio = Dio(
          BaseOptions(
            baseUrl: const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: productionApiBaseUrl,
            ),
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'Content-Type': 'application/json'},
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final session = await _sessionStore.load();
          if (session != null && options.extra['auth'] != false) {
            options.headers['Authorization'] = 'Bearer ${session.accessToken}';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final SessionStore _sessionStore;

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
      options: Options(extra: {'auth': false}),
    );
    return response.data ?? {};
  }

  Future<List<Map<String, dynamic>>> getAccounts() async {
    final response = await _dio.get<List<dynamic>>(
      '/accounts',
      queryParameters: {'active_only': true},
    );
    return _asMapList(response.data);
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final response = await _dio.get<List<dynamic>>('/categories');
    return _asMapList(response.data);
  }

  Future<List<Map<String, dynamic>>> getBudgets(String month) async {
    final response = await _dio.get<List<dynamic>>(
      '/budgets',
      queryParameters: {'month': month},
    );
    return _asMapList(response.data);
  }

  Future<List<Map<String, dynamic>>> getBudgetSummaryRows(String month) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/budgets/summary',
      queryParameters: {'month': month},
    );
    final body = response.data ?? {};
    return (body['categories'] as List? ?? [])
        .whereType<Map>()
        .map((row) => {
              ...row.cast<String, dynamic>(),
              'month': body['month'] ?? month,
              'amount': row['budget'],
            })
        .toList();
  }

  Future<Map<String, dynamic>> getTransactions({
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/transactions',
      queryParameters: {
        'limit': limit,
        'offset': offset,
        'active_accounts_only': true,
      },
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> createTransaction(
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/transactions',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> updateTransaction(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/transactions/$id',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<void> deleteTransaction(String id) async {
    await _dio.delete('/transactions/$id');
  }

  Future<Map<String, dynamic>> createTransfer(Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/transfers',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> updateAccount(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/accounts/$id',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<void> archiveAccount(String id) async {
    await _dio.delete('/accounts/$id');
  }

  Future<List<Map<String, dynamic>>> getStocks() async {
    final response = await _dio.get<List<dynamic>>('/portfolio/stocks');
    return _asMapList(response.data);
  }

  Future<List<Map<String, dynamic>>> getPortfolioTransactions({
    int limit = 100,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/portfolio/transactions',
      queryParameters: {'limit': limit},
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> getPortfolioSummary() async {
    final response = await _dio.get<Map<String, dynamic>>('/portfolio/summary');
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> createAccount(Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/accounts',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> createCategory(Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/categories',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> upsertBudget(Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/budgets/upsert',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> updateBudget(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/budgets/$id',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> createPortfolioTransaction(
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/portfolio/transactions',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<void> post(String path, Map<String, dynamic> payload) async {
    await _dio.post(path, data: payload);
  }

  static List<Map<String, dynamic>> _asMapList(List<dynamic>? rows) {
    return (rows ?? [])
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
  }
}
