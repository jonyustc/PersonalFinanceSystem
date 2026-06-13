import 'package:google_sign_in/google_sign_in.dart';

/// Thrown when "Sign in with Google" cannot be used.
class GoogleAuthException implements Exception {
  const GoogleAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Wraps google_sign_in to return a Google ID token that our backend verifies.
///
/// [serverClientId] must be the **Web** OAuth client ID (the same one the
/// backend lists in GOOGLE_CLIENT_IDS). Pass it at build time:
///   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=`web-client-id`
class GoogleAuthService {
  // The Web OAuth client ID, supplied at build time and read from env.json via
  // `--dart-define-from-file=env.json` (see mobile/README.md). Must match one of
  // the backend's GOOGLE_CLIENT_IDS values.
  static const _serverClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  bool _initialized = false;

  bool get isConfigured => _serverClientId.isNotEmpty;

  Future<String> obtainIdToken() async {
    if (!isConfigured) {
      throw const GoogleAuthException('Google login is not configured');
    }

    final signIn = GoogleSignIn.instance;
    if (!_initialized) {
      await signIn.initialize(serverClientId: _serverClientId);
      _initialized = true;
    }

    final account = await signIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const GoogleAuthException('Google did not return an ID token');
    }
    return idToken;
  }
}
