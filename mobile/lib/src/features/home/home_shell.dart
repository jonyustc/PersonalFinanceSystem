import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';
import '../accounts/accounts_page.dart';
import '../budgets/budgets_page.dart';
import '../categories/categories_page.dart';
import '../dashboard/dashboard_page.dart';
import '../portfolio/portfolio_page.dart';
import '../reports/reports_page.dart';
import '../settings/settings_page.dart';
import '../transactions/create_transaction_sheet.dart';
import '../transactions/transactions_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;

  static const _pages = [
    DashboardPage(),
    TransactionsPage(),
    AccountsPage(),
    BudgetsPage(),
    CategoriesPage(),
    ReportsPage(),
    PortfolioPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;

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
        children: const [
          Padding(
            padding: EdgeInsets.fromLTRB(28, 20, 16, 12),
            child: Text('Personal Finance'),
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
      body: _pages[_index],
      floatingActionButton: _index == 1 || _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => showCreateTransactionSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Transaction'),
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

  int get _bottomIndex {
    return switch (_index) {
      0 => 0,
      1 => 1,
      2 => 2,
      5 => 3,
      6 => 4,
      _ => 0,
    };
  }

  int _pageIndex(int bottomIndex) {
    return switch (bottomIndex) {
      0 => 0,
      1 => 1,
      2 => 2,
      3 => 5,
      4 => 6,
      _ => 0,
    };
  }

  String get _title {
    return switch (_index) {
      0 => 'Overview',
      1 => 'Transactions',
      2 => 'Accounts',
      3 => 'Budgets',
      4 => 'Categories',
      5 => 'Reports',
      6 => 'Portfolio',
      _ => 'Settings',
    };
  }
}
