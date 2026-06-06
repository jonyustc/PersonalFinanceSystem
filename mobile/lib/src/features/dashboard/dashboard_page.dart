import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance_summary.dart';
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../transactions/transaction_details_page.dart';
import '../transactions/transaction_tile.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key, this.onOpenTransactions});

  final VoidCallback? onOpenTransactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final currency = snapshot.session?.currency ?? 'BDT';
    final summary = buildFinanceSummary(
      accounts: snapshot.accounts,
      categories: snapshot.categories,
      transactions: snapshot.transactions,
      budgets: snapshot.budgets,
      stocks: snapshot.stocks,
      portfolioTransactions: snapshot.portfolioTransactions,
    );

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _BalanceSummary(
            summary: summary,
            currency: currency,
            accounts: snapshot.accounts,
          ),
          const SizedBox(height: 18),
          _RecentTransactions(
            snapshot.transactions,
            currency: currency,
            onOpenTransactions: onOpenTransactions,
          ),
        ],
      ),
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary({
    required this.summary,
    required this.currency,
    required this.accounts,
  });

  final FinanceSummary summary;
  final String currency;
  final List<Map<String, dynamic>> accounts;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SummaryCard(
          label: 'Total assets',
          value: money(summary.assets, currency: currency),
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFF15803D),
          onTap: () => _showBalanceDetails(
            context,
            title: 'Assets',
            rows: _assetRows(accounts, summary, currency),
            totalLabel: 'Total assets',
            total: summary.assets,
            currency: currency,
          ),
        ),
        const SizedBox(height: 10),
        _SummaryCard(
          label: 'Total liabilities',
          value: money(summary.creditCardOutstanding, currency: currency),
          icon: Icons.credit_card_outlined,
          color: const Color(0xFFB91C1C),
          onTap: () => _showBalanceDetails(
            context,
            title: 'Liabilities',
            rows: _liabilityRows(accounts, currency),
            totalLabel: 'Total liabilities',
            total: summary.creditCardOutstanding,
            currency: currency,
          ),
        ),
        const SizedBox(height: 10),
        _SummaryCard(
          label: 'Balance',
          value: money(summary.netWorth, currency: currency),
          icon: Icons.balance_outlined,
          color: Theme.of(context).colorScheme.primary,
          onTap: () => _showBalanceDetails(
            context,
            title: 'Balance',
            rows: [
              _BalanceDetailRow('Total assets', summary.assets),
              _BalanceDetailRow(
                'Total liabilities',
                -summary.creditCardOutstanding,
              ),
            ],
            totalLabel: 'Balance',
            total: summary.netWorth,
            currency: currency,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          child: Icon(icon),
        ),
        title: Text(label),
        trailing: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _BalanceDetailRow {
  const _BalanceDetailRow(this.label, this.amount, {this.currency});

  final String label;
  final double amount;
  final String? currency;
}

List<_BalanceDetailRow> _assetRows(
  List<Map<String, dynamic>> accounts,
  FinanceSummary summary,
  String currency,
) {
  final rows = accounts
      .where((account) => !isCreditCardAccount(account))
      .map(
        (account) => _BalanceDetailRow(
          account['name'] as String? ?? 'Account',
          asDouble(account['balance']),
          currency: account['currency'] as String? ?? currency,
        ),
      )
      .toList();
  if (summary.portfolioValue != 0) {
    rows.add(_BalanceDetailRow('Stock portfolio', summary.portfolioValue));
  }
  rows.sort((a, b) => b.amount.compareTo(a.amount));
  return rows;
}

List<_BalanceDetailRow> _liabilityRows(
  List<Map<String, dynamic>> accounts,
  String currency,
) {
  return accounts
      .where(isCreditCardAccount)
      .map(
        (account) => _BalanceDetailRow(
          account['name'] as String? ?? 'Credit card',
          asDouble(account['balance']),
          currency: account['currency'] as String? ?? currency,
        ),
      )
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
}

void _showBalanceDetails(
  BuildContext context, {
  required String title,
  required List<_BalanceDetailRow> rows,
  required String totalLabel,
  required double total,
  required String currency,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('No rows to show.'),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        money(row.amount, currency: row.currency ?? currency),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    );
                  },
                ),
              ),
            const Divider(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                totalLabel,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              trailing: Text(
                money(total, currency: currency),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions(
    this.transactions, {
    required this.currency,
    this.onOpenTransactions,
  });

  final List<Map<String, dynamic>> transactions;
  final String currency;
  final VoidCallback? onOpenTransactions;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final recent = todayTransactions(transactions, today: today, limit: 8);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's transactions",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        if (recent.isEmpty)
          _TodayEmptyPanel(
            onOpenTransactions: onOpenTransactions,
          )
        else
          ...recent.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TransactionTile(
                row: row,
                currency: currency,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TransactionDetailsPage(
                      transactionId: row['id'] as String,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

List<Map<String, dynamic>> todayTransactions(
  List<Map<String, dynamic>> transactions, {
  required DateTime today,
  int limit = 8,
}) {
  final start = DateTime(today.year, today.month, today.day);
  final end = start.add(const Duration(days: 1));
  final rows = transactions.where((row) {
    final parsed = DateTime.tryParse(row['txn_date'] as String? ?? '');
    if (parsed == null) return false;
    final localDate = parsed.toLocal();
    return !localDate.isBefore(start) && localDate.isBefore(end);
  }).toList()
    ..sort((a, b) {
      final left = DateTime.tryParse(a['txn_date'] as String? ?? '');
      final right = DateTime.tryParse(b['txn_date'] as String? ?? '');
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
  return rows.take(limit).toList();
}

class _TodayEmptyPanel extends StatelessWidget {
  const _TodayEmptyPanel({this.onOpenTransactions});

  final VoidCallback? onOpenTransactions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.today_outlined, size: 36, color: scheme.primary),
            const SizedBox(height: 10),
            Text('No transactions today', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Open transactions to review older entries.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onOpenTransactions,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View all transactions'),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 36, color: scheme.primary),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
