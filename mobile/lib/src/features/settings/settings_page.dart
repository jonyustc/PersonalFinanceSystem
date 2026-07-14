import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/section_header.dart';
import '../auth/login_page.dart';
import '../recurring/recurring_page.dart';
import 'backup_settings_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final session = snapshot?.session;
    final isOffline = session?.isOffline == true;
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                foregroundColor: scheme.primary,
                child: const Icon(Icons.person_outline),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session?.userName ?? 'User',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      session?.email ?? '',
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
        ),
        if (isOffline) ...[
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            child: Row(
              children: [
                Icon(Icons.cloud_off_outlined, color: scheme.tertiary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline mode',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Data lives on this device only. Sign in to sync it to '
                        'the server.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton(
                  onPressed: () => _signInToSync(context),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader('Preferences'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            children: [
              _SettingRow(
                icon: Icons.payments_outlined,
                label: 'Currency',
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: session?.currency ?? 'BDT',
                    items: const [
                      DropdownMenuItem(value: 'BDT', child: Text('BDT')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                      DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                      DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                      DropdownMenuItem(value: 'AED', child: Text('AED')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(appControllerProvider.notifier)
                            .setCurrency(value);
                      }
                    },
                  ),
                ),
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.dark_mode_outlined,
                label: 'Theme',
                trailing: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: snapshot?.themeMode ?? 'system',
                    items: const [
                      DropdownMenuItem(value: 'system', child: Text('System')),
                      DropdownMenuItem(value: 'light', child: Text('Light')),
                      DropdownMenuItem(value: 'dark', child: Text('Dark')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref
                            .read(appControllerProvider.notifier)
                            .setThemeMode(value);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader('Data & sync'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: Column(
            children: [
              _SettingRow(
                icon: Icons.storage_outlined,
                label: 'Local database',
                subtitle:
                    '${snapshot?.accounts.length ?? 0} accounts · '
                    '${snapshot?.categories.length ?? 0} categories · '
                    '${snapshot?.transactions.length ?? 0} transactions',
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.sync_outlined,
                label: syncTime(snapshot?.lastSyncAt),
                subtitle: '${snapshot?.pendingWrites ?? 0} unsynced changes',
                trailing: IconButton(
                  tooltip: 'Sync now',
                  icon: const Icon(Icons.sync),
                  onPressed: () =>
                      ref.read(appControllerProvider.notifier).syncNow(),
                ),
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.backup_outlined,
                label: 'Backup & restore',
                subtitle: 'Auto-backup schedule, folder, export and restore',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BackupSettingsPage(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        const SectionHeader('Automation'),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: _SettingRow(
            icon: Icons.event_repeat_outlined,
            label: 'Recurring transactions',
            subtitle: 'Auto-create rent, salary, subscriptions and more',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const RecurringPage()),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        OutlinedButton.icon(
          onPressed: () async {
            final confirmed = await showConfirmDialog(
              context,
              title: 'Sign out?',
              message:
                  'Your data stays on this device. Sign back in with the same '
                  'account to continue where you left off. Signing in with a '
                  'different account will replace it.',
              confirmLabel: 'Sign out',
              icon: Icons.logout,
              destructive: false,
            );
            if (confirmed) {
              await ref.read(appControllerProvider.notifier).logout();
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }

  Future<void> _signInToSync(BuildContext context) async {
    // Push the login page as a sheet; it pops itself on a successful sign-in,
    // which upgrades the offline session to a real one and syncs.
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
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
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: row,
    );
  }
}
