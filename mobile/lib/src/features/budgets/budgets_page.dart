import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';

class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final now = DateTime.now();
    final budgets = snapshot.budgets
        .where((row) => row['month'] == now.month && row['year'] == now.year)
        .toList();
    final categories = {
      for (final row in snapshot.categories) row['id'] as String: row,
    };
    final currency = snapshot.session?.currency ?? 'BDT';
    final totalBudget =
        budgets.fold<double>(0, (sum, row) => sum + asDouble(row['amount']));
    final totalSpent =
        budgets.fold<double>(0, (sum, row) => sum + asDouble(row['spent']));
    final progress = totalBudget <= 0 ? 0.0 : (totalSpent / totalBudget);

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(
            title: Text('Budgets'),
            pinned: true,
            automaticallyImplyLeading: false,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This month',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 12,
                            value: progress.clamp(0, 1),
                            backgroundColor: const Color(0xFFE2E8F0),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _BudgetMetric(
                                label: 'Budget',
                                value: money(totalBudget, currency: currency),
                              ),
                            ),
                            Expanded(
                              child: _BudgetMetric(
                                label: 'Spent',
                                value: money(totalSpent, currency: currency),
                                danger: totalSpent > totalBudget && totalBudget > 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (budgets.isEmpty)
                  const EmptyPanel(
                    icon: Icons.pie_chart_outline,
                    title: 'No budgets cached',
                    body: 'Sync from the web app to review monthly budget limits here.',
                  )
                else
                  ...budgets.map((row) {
                    final amount = asDouble(row['amount']);
                    final spent = asDouble(row['spent']);
                    final rowProgress = amount <= 0 ? 0.0 : spent / amount;
                    final category = categories[row['category_id']];
                    final over = rowProgress > 1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: over
                                        ? const Color(0xFFFEE2E2)
                                        : const Color(0xFFE0F2FE),
                                    foregroundColor: over
                                        ? const Color(0xFFB91C1C)
                                        : const Color(0xFF0369A1),
                                    child: Icon(over
                                        ? Icons.warning_amber
                                        : Icons.category_outlined),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      category?['name'] as String? ?? 'Category',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${(rowProgress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: over ? Colors.red.shade700 : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  minHeight: 9,
                                  value: rowProgress.clamp(0, 1),
                                  backgroundColor: const Color(0xFFE2E8F0),
                                  color: over
                                      ? Colors.red.shade600
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${money(spent, currency: currency)} of ${money(amount, currency: currency)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetMetric extends StatelessWidget {
  const _BudgetMetric({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: danger ? Colors.red.shade700 : null,
              ),
        ),
      ],
    );
  }
}
