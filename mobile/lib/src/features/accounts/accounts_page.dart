import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());
    final accounts = snapshot.accounts;

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: accounts.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                EmptyPanel(
                  icon: Icons.account_balance_outlined,
                  title: 'No accounts cached',
                  body: 'Sync from the API to bring your accounts into SQLite.',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: accounts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final account = accounts[index];
                final balance = asDouble(account['balance']);
                final currency = (account['currency'] ?? snapshot.session?.currency ?? 'USD') as String;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE0F2FE),
                      foregroundColor: const Color(0xFF0369A1),
                      child: Icon(_accountIcon(account['type'] as String?)),
                    ),
                    title: Text(
                      account['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text((account['type'] as String).replaceAll('_', ' ').toUpperCase()),
                    trailing: Text(
                      money(balance, currency: currency),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                );
              },
            ),
    );
  }

  IconData _accountIcon(String? type) {
    final value = (type ?? '').toLowerCase();
    if (value.contains('card')) return Icons.credit_card;
    if (value.contains('bank')) return Icons.account_balance;
    if (value.contains('mobile')) return Icons.phone_android;
    return Icons.wallet;
  }
}
