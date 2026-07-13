import 'package:shared_preferences/shared_preferences.dart';

/// How often an automatic backup should run. The interval is checked on app
/// open/resume (an offline-friendly "run if due" approach — no background
/// worker), so a backup happens the next time the app is used after it falls
/// due rather than at an exact clock time.
enum BackupFrequency {
  off('Off', null),
  daily('Daily', Duration(days: 1)),
  weekly('Weekly', Duration(days: 7)),
  monthly('Monthly', Duration(days: 30));

  const BackupFrequency(this.label, this.interval);

  final String label;
  final Duration? interval;

  static BackupFrequency fromName(String? name) {
    return BackupFrequency.values.firstWhere(
      (f) => f.name == name,
      orElse: () => BackupFrequency.off,
    );
  }
}

class BackupSettings {
  const BackupSettings({
    required this.frequency,
    this.customDir,
    this.lastBackupAt,
    this.lastBackupWhere,
  });

  final BackupFrequency frequency;

  /// A user-picked folder to also write backups into (null = app storage only).
  final String? customDir;
  final String? lastBackupAt; // ISO-8601
  final String? lastBackupWhere; // human label of the last destination

  /// True when a scheduled backup is overdue given the frequency and the last
  /// backup time.
  bool get isDue {
    final interval = frequency.interval;
    if (interval == null) return false;
    if (lastBackupAt == null) return true;
    final last = DateTime.tryParse(lastBackupAt!);
    if (last == null) return true;
    return DateTime.now().difference(last) >= interval;
  }
}

/// Device-scoped backup preferences, persisted in shared_preferences (kept out
/// of the DB so they survive logout, which wipes local data).
class BackupSettingsStore {
  static const _frequency = 'backup_frequency';
  static const _customDir = 'backup_custom_dir';
  static const _lastAt = 'backup_last_at';
  static const _lastWhere = 'backup_last_where';

  Future<BackupSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return BackupSettings(
      frequency: BackupFrequency.fromName(prefs.getString(_frequency)),
      customDir: prefs.getString(_customDir),
      lastBackupAt: prefs.getString(_lastAt),
      lastBackupWhere: prefs.getString(_lastWhere),
    );
  }

  Future<void> setFrequency(BackupFrequency frequency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_frequency, frequency.name);
  }

  Future<void> setCustomDir(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.isEmpty) {
      await prefs.remove(_customDir);
    } else {
      await prefs.setString(_customDir, path);
    }
  }

  Future<void> markBackedUp(String whereLabel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastAt, DateTime.now().toIso8601String());
    await prefs.setString(_lastWhere, whereLabel);
  }
}
