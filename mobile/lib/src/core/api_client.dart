import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'session_store.dart';

const productionApiBaseUrl =
    'https://personalfinancesystem.onrender.com/api/v1';

/// Outcome of a token-refresh attempt. Only [rejected] (the server explicitly
/// refused the refresh token) may end the session; [transient] failures
/// (timeouts, 5xx, offline, cold-starting server) must never log the user out.
enum _RefreshOutcome { success, rejected, transient }

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
          if (options.extra['auth'] != false) {
            var session = await _sessionStore.load();
            if (session != null && _expiresSoon(session.accessToken)) {
              // Proactive refresh: avoids a guaranteed 401 round-trip against
              // a cold-starting server. Best-effort — a transient failure
              // just lets the request proceed with the current token.
              await _refreshSession();
              session = await _sessionStore.load();
            }
            if (session != null) {
              options.headers['Authorization'] =
                  'Bearer ${session.accessToken}';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final status = error.response?.statusCode;
          final isAuthRequest = error.requestOptions.extra['auth'] == false;
          final alreadyRetried = error.requestOptions.extra['retried'] == true;

          if (!isAuthRequest && status == 401 && !alreadyRetried) {
            final outcome = await _refreshSession();
            if (outcome == _RefreshOutcome.success) {
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
                // Retry failed after a successful refresh — surface the
                // error but keep the session; the refresh token is valid.
              }
            } else if (outcome == _RefreshOutcome.rejected) {
              // The server explicitly refused the refresh token — the
              // session is truly dead.
              await onSessionExpired?.call();
            }
            // Transient refresh failure: keep the session, fail the request.
          }
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final SessionStore _sessionStore;
  Future<_RefreshOutcome>? _refreshFuture;

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

  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> payload,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/users/profile',
      data: payload,
    );
    return response.data ?? {};
  }

  Future<_RefreshOutcome> _refreshSession() {
    final existing = _refreshFuture;
    if (existing != null) return existing;

    final future = _performRefresh().whenComplete(() {
      _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<_RefreshOutcome> _performRefresh() async {
    final session = await _sessionStore.load();
    if (session == null) return _RefreshOutcome.rejected;

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': session.refreshToken},
        options: Options(extra: {'auth': false}),
      );
      final body = response.data ?? {};
      final accessToken = body['access_token'] as String?;
      final refreshToken = body['refresh_token'] as String?;
      // A malformed success body is a server hiccup, not a dead session.
      if (accessToken == null || refreshToken == null) {
        return _RefreshOutcome.transient;
      }

      await _sessionStore.saveTokens(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
      return _RefreshOutcome.success;
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      // Only an explicit 4xx verdict from the server (401 invalid token,
      // 422 bad request, ...) kills the session. 408/429 and everything
      // else (5xx, timeout, offline) is transient — the refresh token is
      // still good, retry on a later request.
      if (status != null &&
          status >= 400 &&
          status < 500 &&
          status != 408 &&
          status != 429) {
        return _RefreshOutcome.rejected;
      }
      return _RefreshOutcome.transient;
    }
  }

  /// True when the JWT's `exp` is within 2 minutes (or already past),
  /// so the token should be refreshed before use.
  static bool _expiresSoon(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
              as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) return false;
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
      return expiry.difference(DateTime.now().toUtc()) <
          const Duration(minutes: 2);
    } catch (_) {
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
    String? portfolioId,
  }) async {
    final response = await _dio.get<List<dynamic>>(
      '/portfolio/transactions',
      queryParameters: {
        'limit': limit,
        if (portfolioId != null && portfolioId.isNotEmpty)
          'portfolio_id': portfolioId,
      },
    );
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> getPortfolioSummary({String? portfolioId}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/portfolio/summary',
      queryParameters: {
        if (portfolioId != null && portfolioId.isNotEmpty)
          'portfolio_id': portfolioId,
      },
    );
    return response.data ?? {};
  }

  Future<List<Map<String, dynamic>>> getPortfolios() async {
    final response = await _dio.get<List<dynamic>>('/portfolio/portfolios');
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> getPortfolioAnalytics({
    String? portfolioId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/portfolio/analytics',
      queryParameters: {
        if (portfolioId != null && portfolioId.isNotEmpty)
          'portfolio_id': portfolioId,
      },
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> getPortfolioAnnualPerformance({
    String? portfolioId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/portfolio/performance/annual',
      queryParameters: {
        if (portfolioId != null && portfolioId.isNotEmpty)
          'portfolio_id': portfolioId,
      },
    );
    return response.data ?? {};
  }

  Future<Map<String, dynamic>> getPortfolioPerformanceSeries({
    String? portfolioId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/portfolio/performance/series',
      queryParameters: {
        if (portfolioId != null && portfolioId.isNotEmpty)
          'portfolio_id': portfolioId,
      },
    );
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
