import 'package:shared_preferences/shared_preferences.dart';

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.userName,
    required this.email,
    required this.currency,
  });

  final String accessToken;
  final String refreshToken;
  final String userName;
  final String email;
  final String currency;
}

class SessionStore {
  static const _accessToken = 'access_token';
  static const _refreshToken = 'refresh_token';
  static const _userName = 'user_name';
  static const _email = 'email';
  static const _currency = 'currency';
  static const _themeMode = 'theme_mode';

  Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_accessToken);
    final refresh = prefs.getString(_refreshToken);
    if (token == null || refresh == null) return null;

    return Session(
      accessToken: token,
      refreshToken: refresh,
      userName: prefs.getString(_userName) ?? 'User',
      email: prefs.getString(_email) ?? '',
      currency: prefs.getString(_currency) ?? 'BDT',
    );
  }

  Future<String> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeMode) ?? 'system';
  }

  Future<void> saveFromAuth(Map<String, dynamic> auth) async {
    final prefs = await SharedPreferences.getInstance();
    final user = (auth['user'] as Map?)?.cast<String, dynamic>() ?? {};
    await prefs.setString(_accessToken, auth['access_token'] as String);
    await prefs.setString(_refreshToken, auth['refresh_token'] as String);
    await prefs.setString(_userName, (user['full_name'] ?? 'User') as String);
    await prefs.setString(_email, (user['email'] ?? '') as String);
    await prefs.setString(
      _currency,
      (user['currency'] ?? user['default_currency'] ?? 'BDT') as String,
    );
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessToken, accessToken);
    await prefs.setString(_refreshToken, refreshToken);
  }

  Future<void> saveCurrency(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currency, currency);
  }

  Future<void> saveThemeMode(String themeMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeMode, themeMode);
  }

  Future<void> clear({bool keepTheme = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessToken);
    await prefs.remove(_refreshToken);
    await prefs.remove(_userName);
    await prefs.remove(_email);
    await prefs.remove(_currency);
    if (!keepTheme) {
      await prefs.remove(_themeMode);
    }
  }
}
