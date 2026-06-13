import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'session_store.dart';

const productionApiBaseUrl =
    'https://personalfinancesystem.onrender.com/api/v1';

class ApiClient {
  ApiClient(this._sessionStore, {Future<void> Function()? onSessionExpired})
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
          if (kDebugMode) {
            debugPrint('API ${options.method} ${options.uri}');
          }
          final session = await _sessionStore.load();
          if (session != null && options.extra['auth'] != false) {
            options.headers['Authorization'] = 'Bearer ${session.accessToken}';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;
          final isAuthRequest = error.requestOptions.extra['auth'] == false;
          final alreadyRetried = error.requestOptions.extra['retried'] == true;

          if (!isAuthRequest && status == 401 && !alreadyRetried) {
            final refreshed = await _refreshSession();
            if (refreshed) {
              final session = await _sessionStore.load();
              final retryOptions = error.requestOptions;
              retryOptions.extra['retried'] = true;
              if (session != null) {
                retryOptions.headers['Authorization'] =
                    'Bearer ${session.accessToken}';
              }

              try {
                final response = await _dio.fetch<dynamic>(retryOptions);
                handler.resolve(response);
                return;
              } on DioException {
                // Fall through to the original auth-expiry handling below.
              }
            }
          }

          if (!isAuthRequest && (status == 401 || status == 403)) {
            await onSessionExpired?.call();
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final SessionStore _sessionStore;
  Future<bool>? _refreshFuture;

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
      options: Options(extra: {'auth': false}),
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> loginWithGoogle(String idToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/google',
      data: {'id_token': idToken},
      options: Options(extra: {'auth': false}),
    );
    return response.data ?? {};
  }

  Future<bool> _refreshSession() {
    final existing = _refreshFuture;
    if (existing != null) return existing;

    final future = _performRefresh().whenComplete(() {
      _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<bool> _performRefresh() async {
    final session = await _sessionStore.load();
    if (session == null) return false;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': session.refreshToken},
        options: Options(extra: {'auth': false}),
      );
      final body = response.data ?? {};
      final accessToken = body['access_token'] as String?;
      final refreshToken = body['refresh_token'] as String?;
      if (accessToken == null || refreshToken == null) return false;

      await _sessionStore.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      return true;
    } on DioException {
      return false;
    }
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
        .map(
          (row) => {
            ...row.cast<String, dynamic>(),
            'month': body['month'] ?? month,
            'amount': row['budget'],
          },
        )
        .toList();
  }

  Future<Map<String, dynamic>> getBudgetSummary(String month) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/budgets/summary',
      queryParameters: {'month': month},
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> getMonthlyIncome(String month) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/budgets/income',
      queryParameters: {'month': month},
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> saveMonthlyIncome(
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/budgets/income',
      data: payload,
    );
    return response.data ?? {};
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

  Future<Map<String, dynamic>> createTransfer(
    Map<String, dynamic> payload,
  ) async {
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

  Future<Map<String, dynamic>> createStock(Map<String, dynamic> payload) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/portfolio/stocks',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> refreshStockPrices() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/portfolio/stocks/refresh-prices',
    );
    return response.data ?? {};
  }

  Future<List<Map<String, dynamic>>> searchDseStocks(String query) async {
    final response = await _dio.get<List<dynamic>>(
      '/portfolio/stocks/dse/search',
      queryParameters: {'query': query, 'limit': 12},
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> getDseDividendEstimate({
    required String symbol,
    String? stockId,
    double taxRatePercent = 10,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/portfolio/stocks/dse/dividend-estimate',
      queryParameters: {
        'symbol': symbol,
        if (stockId != null && stockId.isNotEmpty) 'stock_id': stockId,
        'tax_rate_percent': taxRatePercent,
      },
    );
    return response.data ?? {};
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

  Future<Map<String, dynamic>> getSimpleDashboard(String month) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/dashboard/simple',
      queryParameters: {'month': month},
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> getCardReport({
    required String fromDate,
    required String toDate,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/reports/cards',
      queryParameters: {
        'from_date': fromDate,
        'to_date': toDate,
      },
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> createAccount(
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/accounts',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> createCategory(
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/categories',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> updateCategory(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/categories/$id',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<void> deleteCategory(String id) async {
    await _dio.delete('/categories/$id');
  }

  Future<Map<String, dynamic>> upsertBudget(
    Map<String, dynamic> payload,
  ) async {
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

  Future<void> deleteBudget(String id) async {
    await _dio.delete('/budgets/$id');
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

  Future<Map<String, dynamic>> updatePortfolioTransaction(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/portfolio/transactions/$id',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<void> deletePortfolioTransaction(String id) async {
    await _dio.delete('/portfolio/transactions/$id');
  }

  Future<Map<String, dynamic>> updateStock(
    String id,
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/portfolio/stocks/$id',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<void> post(String path, Map<String, dynamic> payload) async {
    await _dio.post(path, data: payload);
  }

  Future<void> replayMutation(
    String method,
    String path,
    Map<String, dynamic> payload,
  ) async {
    await _dio.request<void>(
      path,
      data: method == 'DELETE' ? null : payload,
      options: Options(method: method),
    );
  }

  static List<Map<String, dynamic>> _asMapList(List<dynamic>? rows) {
    return (rows ?? [])
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
  }
}
