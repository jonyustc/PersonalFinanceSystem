import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';
import '../accounts/accounts_page.dart';
import '../dashboard/dashboard_page.dart';
import '../settings/settings_page.dart';
import '../transactions/create_transaction_sheet.dart';
import '../transactions/transactions_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _pages = [
    DashboardPage(),
    TransactionsPage(),
    AccountsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (snapshot?.pendingWrites case final pending? when pending > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Badge(
                  label: Text('$pending'),
                  child: const Icon(Icons.cloud_upload_outlined),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Sync now',
            onPressed: snapshot?.isSyncing == true
                ? null
                : () => ref.read(appControllerProvider.notifier).syncNow(),
            icon: snapshot?.isSyncing == true
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
        ],
      ),
      body: _pages[_index],
      floatingActionButton: _index == 1 || _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => showCreateTransactionSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Transaction'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance),
            label: 'Accounts',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  String get _title {
    return switch (_index) {
      0 => 'Overview',
      1 => 'Transactions',
      2 => 'Accounts',
      _ => 'Settings',
    };
  }
}
