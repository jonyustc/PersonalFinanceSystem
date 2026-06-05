import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final session = snapshot?.session;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(session?.userName ?? 'User'),
            subtitle: Text(session?.email ?? ''),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Currency'),
                trailing: DropdownButton<String>(
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
                      ref.read(appControllerProvider.notifier).setCurrency(value);
                    }
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.dark_mode_outlined),
                title: const Text('Theme'),
                trailing: DropdownButton<String>(
                  value: snapshot?.themeMode ?? 'system',
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('System')),
                    DropdownMenuItem(value: 'light', child: Text('Light')),
                    DropdownMenuItem(value: 'dark', child: Text('Dark')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(appControllerProvider.notifier).setThemeMode(value);
                    }
                  },
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: const Text('Local database'),
                subtitle: Text(
                  '${snapshot?.accounts.length ?? 0} accounts, '
                  '${snapshot?.categories.length ?? 0} categories, '
                  '${snapshot?.transactions.length ?? 0} transactions',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.sync_outlined),
                title: Text(syncTime(snapshot?.lastSyncAt)),
                subtitle: Text('${snapshot?.pendingWrites ?? 0} pending writes'),
                trailing: IconButton(
                  tooltip: 'Sync now',
                  icon: const Icon(Icons.sync),
                  onPressed: () => ref.read(appControllerProvider.notifier).syncNow(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => ref.read(appControllerProvider.notifier).logout(),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    );
  }
}
