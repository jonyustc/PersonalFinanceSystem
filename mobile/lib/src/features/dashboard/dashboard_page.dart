import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance_summary.dart';
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../transactions/transaction_details_page.dart';
import '../transactions/transaction_tile.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

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
          _BalanceSummary(summary: summary, currency: currency),
          const SizedBox(height: 18),
          _RecentTransactions(snapshot.transactions, currency: currency),
        ],
      ),
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary({required this.summary, required this.currency});

  final FinanceSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SummaryCard(
          label: 'Total assets',
          value: money(summary.assets, currency: currency),
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFF15803D),
        ),
        const SizedBox(height: 10),
        _SummaryCard(
          label: 'Total liabilities',
          value: money(summary.creditCardOutstanding, currency: currency),
          icon: Icons.credit_card_outlined,
          color: const Color(0xFFB91C1C),
        ),
        const SizedBox(height: 10),
        _SummaryCard(
          label: 'Balance',
          value: money(summary.netWorth, currency: currency),
          icon: Icons.balance_outlined,
          color: Theme.of(context).colorScheme.primary,
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
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
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

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions(this.transactions, {required this.currency});

  final List<Map<String, dynamic>> transactions;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final recent = transactions.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent transactions',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        if (recent.isEmpty)
          const EmptyPanel(
            icon: Icons.receipt_long_outlined,
            title: 'No transactions yet',
            body: 'Add an expense, income, or transfer to start tracking.',
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
