import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../transactions/transaction_tile.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final currency = snapshot.session?.currency ?? 'USD';
    final accounts = snapshot.accounts;
    final transactions = snapshot.transactions;
    final cash = accounts.fold<double>(
      0,
      (sum, row) => sum + asDouble(row['balance']),
    );
    final thisMonth = DateTime.now();
    final monthlyExpense = transactions
        .where((row) {
          final date = DateTime.tryParse(row['txn_date'] as String? ?? '');
          return row['type'] == 'expense' &&
              date != null &&
              date.month == thisMonth.month &&
              date.year == thisMonth.year;
        })
        .fold<double>(0, (sum, row) => sum + asDouble(row['amount']));
    final monthlyIncome = transactions
        .where((row) {
          final date = DateTime.tryParse(row['txn_date'] as String? ?? '');
          return row['type'] == 'income' &&
              date != null &&
              date.month == thisMonth.month &&
              date.year == thisMonth.year;
        })
        .fold<double>(0, (sum, row) => sum + asDouble(row['amount']));

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Hi, ${snapshot.session?.userName ?? 'there'}',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            syncTime(snapshot.lastSyncAt),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.blueGrey.shade700,
                ),
          ),
          if (snapshot.notice != null) ...[
            const SizedBox(height: 12),
            _Notice(text: snapshot.notice!),
          ],
          const SizedBox(height: 18),
          _MetricGrid(
            metrics: [
              Metric('Total balance', money(cash, currency: currency), Icons.savings_outlined),
              Metric('Income', money(monthlyIncome, currency: currency), Icons.trending_up),
              Metric('Expense', money(monthlyExpense, currency: currency), Icons.trending_down),
              Metric(
                'Cashflow',
                money(monthlyIncome - monthlyExpense, currency: currency),
                Icons.swap_vert,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent activity',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              Text('${transactions.length} cached'),
            ],
          ),
          const SizedBox(height: 10),
          if (transactions.isEmpty)
            const EmptyPanel(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet',
              body: 'Sync from the API or add a transaction locally.',
            )
          else
            ...transactions.take(8).map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TransactionTile(row: row, currency: currency),
                  ),
                ),
        ],
      ),
    );
  }
}

class Metric {
  const Metric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: metrics.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(metric.icon, color: Theme.of(context).colorScheme.primary),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    Text(metric.label, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 36, color: Colors.blueGrey),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey.shade700),
            ),
          ],
        ),
      ),
    );
  }
}
