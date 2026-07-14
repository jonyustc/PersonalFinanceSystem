import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'google_auth.dart';

class GoogleDriveException implements Exception {
  const GoogleDriveException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Backs the local data up to a private per-app folder in the user's Google
/// Drive (the `appDataFolder`, hidden from the user's Drive UI). One rolling
/// file, `personal_finance_backup.json`, is created then overwritten.
///
/// Uses google_sign_in v7 to obtain an OAuth access token for the
/// `drive.appdata` scope and calls the Drive REST API directly (no googleapis
/// dependency). Requires the Android OAuth client (this app's SHA-1) to be
/// registered in Google Cloud Console, and the `drive.appdata` scope to be
/// allowed on the OAuth consent screen.
class GoogleDriveBackup {
  GoogleDriveBackup(this._auth);

  final GoogleAuthService _auth;

  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _fileName = 'personal_finance_backup.json';
  static const _space = 'appDataFolder';

  /// Interactive connect: signs in and authorizes the Drive scope. Returns the
  /// connected account's email.
  Future<String> connect() async {
    final account = await _signIn(interactive: true);
    final headers = await account.authorizationClient.authorizationHeaders(
      const [_scope],
      promptIfNecessary: true,
    );
    if (headers == null) {
      throw const GoogleDriveException('Drive permission was not granted.');
    }
    return account.email;
  }

  /// Forgets the connected Google account on this device.
  Future<void> disconnect() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Best effort; the caller clears the stored email regardless.
    }
  }

  /// Uploads [content] as the rolling backup file (creates it or overwrites).
  /// [interactive] false is used for silent scheduled uploads.
  Future<void> upload(String content, {bool interactive = false}) async {
    final headers = await _headers(interactive: interactive);
    final id = await _existingFileId(headers);
    if (id == null) {
      await _createFile(headers, content);
    } else {
      await _updateFile(headers, id, content);
    }
  }

  /// Downloads the backup file's content, or null if there is no backup yet.
  Future<String?> download() async {
    final headers = await _headers(interactive: true);
    final id = await _existingFileId(headers);
    if (id == null) return null;
    final res = await http.get(
      Uri.parse('https://www.googleapis.com/drive/v3/files/$id?alt=media'),
      headers: headers,
    );
    if (res.statusCode != 200) {
      throw GoogleDriveException('Drive download failed (${res.statusCode}).');
    }
    return utf8.decode(res.bodyBytes);
  }

  // ------------------------------------------------------------------

  Future<GoogleSignInAccount> _signIn({required bool interactive}) async {
    await _auth.ensureInitialized();
    final signIn = GoogleSignIn.instance;
    final attempt = signIn.attemptLightweightAuthentication();
    final silent = attempt == null ? null : await attempt;
    if (silent != null) return silent;
    if (!interactive) {
      throw const GoogleDriveException('Google account not connected.');
    }
    if (!signIn.supportsAuthenticate()) {
      throw const GoogleDriveException(
        'Google sign-in is not supported on this platform.',
      );
    }
    return signIn.authenticate(scopeHint: const [_scope]);
  }

  Future<Map<String, String>> _headers({required bool interactive}) async {
    final account = await _signIn(interactive: interactive);
    final headers = await account.authorizationClient.authorizationHeaders(
      const [_scope],
      promptIfNecessary: interactive,
    );
    if (headers == null) {
      throw const GoogleDriveException('Drive access has not been authorized.');
    }
    return headers;
  }

  Future<String?> _existingFileId(Map<String, String> headers) async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': _space,
      'q': "name = '$_fileName'",
      'fields': 'files(id)',
      'pageSize': '1',
    });
    final res = await http.get(uri, headers: headers);
    if (res.statusCode != 200) {
      throw GoogleDriveException('Drive list failed (${res.statusCode}).');
    }
    final files = (jsonDecode(res.body)['files'] as List?) ?? const [];
    if (files.isEmpty) return null;
    return (files.first as Map)['id'] as String?;
  }

  Future<void> _createFile(Map<String, String> headers, String content) async {
    const boundary = 'pfs_backup_boundary';
    final metadata = jsonEncode({
      'name': _fileName,
      'parents': [_space],
    });
    final body =
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$metadata\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '$content\r\n'
        '--$boundary--';
    final res = await http.post(
      Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files'
        '?uploadType=multipart&fields=id',
      ),
      headers: {
        ...headers,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: utf8.encode(body),
    );
    if (res.statusCode != 200) {
      throw GoogleDriveException('Drive upload failed (${res.statusCode}).');
    }
  }

  Future<void> _updateFile(
    Map<String, String> headers,
    String id,
    String content,
  ) async {
    final res = await http.patch(
      Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files/$id?uploadType=media',
      ),
      headers: {...headers, 'Content-Type': 'application/json; charset=UTF-8'},
      body: utf8.encode(content),
    );
    if (res.statusCode != 200) {
      throw GoogleDriveException('Drive update failed (${res.statusCode}).');
    }
  }
}
