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
    final response = await _dio.get<List<dynamic>>('/accounts');
    return _asMapList(response.data);
  }

  Future<List<Map<String, dynamic>>> getCategories() async {
    final response = await _dio.get<List<dynamic>>('/categories');
    return _asMapList(response.data);
  }

  Future<Map<String, dynamic>> getTransactions({
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/transactions',
      queryParameters: {'limit': limit, 'offset': offset},
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
