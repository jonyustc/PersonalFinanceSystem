import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'app_database.dart';

/// Exports the local database to a shareable JSON file and restores it back.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  /// Writes all local data to a JSON file and opens the system share sheet so
  /// the user can save it to Drive, Files, email, etc.
  Future<void> exportBackup() async {
    final data = await _db.exportData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final file = File('${dir.path}/personal_finance_backup_$stamp.json');
    await file.writeAsString(json);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Personal Finance backup',
      text: 'Personal Finance data backup ($stamp)',
    );
  }

  /// Lets the user pick a backup file and restores it into the local database,
  /// replacing current local data. Returns false if the user cancels.
  /// Throws [FormatException] if the file is not a valid backup.
  Future<bool> importBackup() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return false;
    final picked = result.files.single;

    final String content;
    final bytes = picked.bytes;
    if (bytes != null) {
      content = utf8.decode(bytes);
    } else if (picked.path != null) {
      content = await File(picked.path!).readAsString();
    } else {
      throw const FormatException('Could not read the selected file');
    }

    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Not a Personal Finance backup file');
    }
    await _db.importData(decoded);
    return true;
  }
}
