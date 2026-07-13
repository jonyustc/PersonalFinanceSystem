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
    final file = await _writeSnapshot(await getTemporaryDirectory());
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Personal Finance backup',
      text: 'Personal Finance data backup',
    );
  }

  /// Fixed filename for the silent rolling auto-backup kept in app storage.
  static const _autoBackupName = 'personal_finance_autobackup.json';

  /// Silently writes a fresh full backup to app storage (best effort). This is
  /// a recovery copy against in-app data loss; it does NOT survive an uninstall,
  /// so the user should still export to Drive occasionally. Returns the file, or
  /// null on failure (never throws — auto-backup must not disrupt the app).
  Future<File?> autoBackup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final data = await _db.exportData();
      final json = jsonEncode(data);
      final file = File('${dir.path}/$_autoBackupName');
      await file.writeAsString(json);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Path of the latest auto-backup if one exists (for a one-tap export).
  Future<File?> latestAutoBackup() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_autoBackupName');
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// Shares the latest auto-backup via the system sheet so the user can push it
  /// to Drive/Files. Returns false when there is no auto-backup yet.
  Future<bool> shareLatestAutoBackup() async {
    final file = await latestAutoBackup();
    if (file == null) return false;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/json')],
      subject: 'Personal Finance backup',
      text: 'Personal Finance data backup',
    );
    return true;
  }

  /// Writes a single rolling backup file (`personal_finance_backup.json`) to the
  /// given directory, or app storage when [dir] is null. Used by the scheduled
  /// and manual "Back up now" flows. Throws if the directory can't be written
  /// (e.g. a picked folder the OS won't grant direct file access to).
  Future<File> writeBackup({String? dir}) async {
    final targetDir = dir ?? (await getApplicationDocumentsDirectory()).path;
    final data = await _db.exportData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final file = File('$targetDir/personal_finance_backup.json');
    await file.writeAsString(json);
    return file;
  }

  /// Lets the user pick a folder to also keep backups in. Returns the chosen
  /// path, or null if cancelled. On some Android versions the OS returns a
  /// location the app can't write to directly — the caller verifies by writing.
  Future<String?> pickBackupFolder() => FilePicker.platform.getDirectoryPath();

  Future<File> _writeSnapshot(Directory dir) async {
    final data = await _db.exportData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    final file = File('${dir.path}/personal_finance_backup_$stamp.json');
    await file.writeAsString(json);
    return file;
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
