import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';
import '../accounts/accounts_page.dart';
import '../budgets/budgets_page.dart';
import '../categories/categories_page.dart';
import '../dashboard/dashboard_page.dart';
import '../debts/debts_page.dart';
import '../portfolio/portfolio_page.dart';
import '../reports/reports_page.dart';
import '../settings/settings_page.dart';
import '../transactions/create_transaction_sheet.dart';
import '../transactions/search_transactions_page.dart';
import '../transactions/transactions_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final pages = [
      DashboardPage(onOpenTransactions: () => setState(() => _index = 1)),
      const TransactionsPage(),
      const AccountsPage(),
      const BudgetsPage(),
      const DebtsPage(),
      const CategoriesPage(),
      const ReportsPage(),
      const PortfolioPage(),
      const SettingsPage(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_title),
        leading: IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            tooltip: 'Search transactions',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SearchTransactionsPage(),
              ),
            ),
          ),
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
      drawer: NavigationDrawer(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          Navigator.of(context).pop();
          setState(() => _index = value);
        },
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 16, 16),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Personal Finance',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: Text('Dashboard'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: Text('Transactions'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.account_balance_outlined),
            selectedIcon: Icon(Icons.account_balance),
            label: Text('Accounts'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.pie_chart_outline),
            selectedIcon: Icon(Icons.pie_chart),
            label: Text('Budgets'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.handshake_outlined),
            selectedIcon: Icon(Icons.handshake),
            label: Text('Loans'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: Text('Categories'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: Text('Reports'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: Text('Portfolio'),
          ),
          NavigationDrawerDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: Text('Settings'),
          ),
        ],
      ),
      body: pages[_index],
      floatingActionButton: _index == 1
          ? FloatingActionButton(
              tooltip: 'Add transaction',
              onPressed: () => showCreateTransactionSheet(context),
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _bottomIndex,
        onDestinationSelected: (value) => setState(() => _index = _pageIndex(value)),
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
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_outlined),
            selectedIcon: Icon(Icons.show_chart),
            label: 'Stocks',
          ),
        ],
      ),
    );
  }

  // Page indices (DebtsPage sits at 4, shifting Categories/Reports/Portfolio/
  // Settings to 5/6/7/8). The bottom bar still maps to the same five pages:
  // Home, Transactions, Accounts, Reports, Stocks.
  int get _bottomIndex {
    return switch (_index) {
      0 => 0,
      1 => 1,
      2 => 2,
      6 => 3,
      7 => 4,
      _ => 0,
    };
  }

  int _pageIndex(int bottomIndex) {
    return switch (bottomIndex) {
      0 => 0,
      1 => 1,
      2 => 2,
      3 => 6,
      4 => 7,
      _ => 0,
    };
  }

  String get _title {
    return switch (_index) {
      0 => 'Overview',
      1 => 'Transactions',
      2 => 'Accounts',
      3 => 'Budgets',
      4 => 'Loans',
      5 => 'Categories',
      6 => 'Reports',
      7 => 'Portfolio',
      _ => 'Settings',
    };
  }
}
