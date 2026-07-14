import 'package:shared_preferences/shared_preferences.dart';

class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.userName,
    required this.email,
    required this.currency,
    this.isOffline = false,
  });

  final String accessToken;
  final String refreshToken;
  final String userName;
  final String email;
  final String currency;

  /// True when the app was entered from a local backup with no server login
  /// (e.g. a fresh install while the backend is unreachable). Viewing and
  /// local-first editing work; syncing is disabled until a real sign-in.
  final bool isOffline;
}

class SessionStore {
  static const _accessToken = 'access_token';
  static const _refreshToken = 'refresh_token';
  static const _userName = 'user_name';
  static const _email = 'email';
  static const _currency = 'currency';
  static const _themeMode = 'theme_mode';
  static const _offline = 'offline_session';
  static const _rememberMe = 'remember_me';

  Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final offline = prefs.getBool(_offline) ?? false;
    final token = prefs.getString(_accessToken);
    final refresh = prefs.getString(_refreshToken);
    // An offline session has no tokens but still grants entry (data came from a
    // restored backup); a normal session requires both tokens.
    if (!offline && (token == null || refresh == null)) return null;

    return Session(
      accessToken: token ?? '',
      refreshToken: refresh ?? '',
      userName: prefs.getString(_userName) ?? 'User',
      email: prefs.getString(_email) ?? '',
      currency: prefs.getString(_currency) ?? 'BDT',
      isOffline: offline,
    );
  }

  /// Enters the app without a server login, using identity recovered from a
  /// restored backup. No tokens are stored, so syncing stays disabled until the
  /// user signs in for real.
  Future<void> saveOfflineSession({
    required String userName,
    required String email,
    required String currency,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessToken);
    await prefs.remove(_refreshToken);
    await prefs.setString(_userName, userName);
    await prefs.setString(_email, email);
    await prefs.setString(_currency, currency);
    await prefs.setBool(_offline, true);
  }

  Future<String> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeMode) ?? 'light';
  }

  /// Whether the session should survive a full app restart. Defaults to true
  /// (stay signed in); when false, a cold start requires signing in again.
  Future<bool> loadRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberMe) ?? true;
  }

  Future<void> saveRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMe, value);
  }

  Future<void> saveFromAuth(Map<String, dynamic> auth) async {
    final prefs = await SharedPreferences.getInstance();
    final user = (auth['user'] as Map?)?.cast<String, dynamic>() ?? {};
    // A real sign-in supersedes any offline session.
    await prefs.remove(_offline);
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
    await prefs.remove(_offline);
    if (!keepTheme) {
      await prefs.remove(_themeMode);
    }
  }
}
