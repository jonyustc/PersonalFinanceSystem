import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backup_settings.dart';
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_header.dart';

/// WhatsApp-style backup control panel: choose how often to auto-back-up, where
/// to keep a copy, and back up / export / restore on demand.
class BackupSettingsPage extends ConsumerStatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  ConsumerState<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends ConsumerState<BackupSettingsPage> {
  BackupSettings? _settings;
  bool _busy = false;

  AppController get _controller => ref.read(appControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _controller.loadBackupSettings();
    if (mounted) setState(() => _settings = settings);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = _settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const SectionHeader(
                  'Automatic backup',
                  subtitle: 'Runs when you open the app if one is due',
                ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      for (final f in BackupFrequency.values)
                        ChoiceChip(
                          label: Text(f.label),
                          selected: settings.frequency == f,
                          onSelected: (_) => _setFrequency(f),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader('Where backups are kept'),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
                  child: Column(
                    children: [
                      _Row(
                        icon: Icons.smartphone_outlined,
                        label: 'App storage',
                        subtitle: 'Always kept on this device (fast, private)',
                        trailing: Icon(Icons.check_circle, color: scheme.primary),
                      ),
                      const Divider(height: 1),
                      _Row(
                        icon: Icons.folder_outlined,
                        label: 'Also save to a folder',
                        subtitle: settings.customDir ?? 'Not set',
                        trailing: settings.customDir == null
                            ? TextButton(
                                onPressed: _busy ? null : _chooseFolder,
                                child: const Text('Choose'),
                              )
                            : TextButton(
                                onPressed: _busy ? null : _clearFolder,
                                child: const Text('Remove'),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeader('Google Drive'),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: settings.driveEnabled
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.cloud_done_outlined,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Connected',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      Text(
                                        settings.driveEmail!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _busy ? null : _restoreFromDrive,
                                    icon: const Icon(Icons.cloud_download_outlined),
                                    label: const Text('Restore'),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _busy ? null : _disconnectDrive,
                                    icon: const Icon(Icons.logout),
                                    label: const Text('Disconnect'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Back up automatically to a private folder in your '
                              'Google Drive — restore it on any device.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            FilledButton.tonalIcon(
                              onPressed: _busy ? null : _connectDrive,
                              icon: const Icon(Icons.cloud_outlined),
                              label: const Text('Connect Google Drive'),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: AppSpacing.md),
                _StatusCard(settings: settings),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: _busy ? null : _backupNow,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.backup_outlined),
                  label: const Text('Back up now'),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _export,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Export / share backup…'),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: const Icon(Icons.restore_outlined),
                  label: const Text('Restore from a file'),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Backups in app storage are erased if you uninstall the app. '
                  'To keep a copy off this phone, use Export / share and save it '
                  'to Google Drive or Files.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _setFrequency(BackupFrequency frequency) async {
    await _controller.setBackupFrequency(frequency);
    await _load();
  }

  Future<void> _chooseFolder() async {
    setState(() => _busy = true);
    try {
      final message = await _controller.chooseBackupFolder();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _clearFolder() async {
    await _controller.clearBackupFolder();
    await _load();
  }

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    try {
      final where = await _controller.runManualBackup();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backed up to $where')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _connectDrive() async {
    setState(() => _busy = true);
    try {
      final email = await _controller.connectDrive();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Drive connected: $email')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not connect Drive: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _disconnectDrive() async {
    await _controller.disconnectDrive();
    await _load();
  }

  Future<void> _restoreFromDrive() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore from Google Drive?',
      message:
          'This replaces the data on this device with the latest Drive backup.',
      confirmLabel: 'Restore',
      icon: Icons.cloud_download_outlined,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final restored = await _controller.restoreFromDrive();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              restored ? 'Restored from Google Drive' : 'No Drive backup found',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    try {
      await _controller.exportBackup();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  Future<void> _restore() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore from backup?',
      message:
          'This replaces the data on this device with the backup file. A sync '
          'may later reconcile it with the server.',
      confirmLabel: 'Choose file',
      icon: Icons.restore_outlined,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      final restored = await _controller.restoreBackup();
      if (!mounted || !restored) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup restored')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $error')));
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.settings});

  final BackupSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = settings.lastBackupAt == null
        ? 'No backup yet'
        : syncTime(settings.lastBackupAt);
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.history, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  last,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (settings.lastBackupWhere != null)
                  Text(
                    settings.lastBackupWhere!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
