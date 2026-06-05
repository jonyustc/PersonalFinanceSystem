import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance_summary.dart';
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../transactions/transaction_tile.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({
    super.key,
    this.onAddExpense,
    this.onAddIncome,
    this.onTransfer,
    this.onAddBudget,
    this.onAddStock,
  });

  final VoidCallback? onAddExpense;
  final VoidCallback? onAddIncome;
  final VoidCallback? onTransfer;
  final VoidCallback? onAddBudget;
  final VoidCallback? onAddStock;

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
          _HeroNetWorthCard(
            summary: summary,
            currency: currency,
            accountCount: snapshot.accounts.length,
            lastSyncAt: snapshot.lastSyncAt,
            userName: snapshot.session?.userName ?? 'there',
          ),
          if (snapshot.notice != null) ...[
            const SizedBox(height: 12),
            NoticePanel(text: snapshot.notice!),
          ],
          const SizedBox(height: 14),
          _QuickActions(
            onAddExpense: onAddExpense,
            onAddIncome: onAddIncome,
            onTransfer: onTransfer,
            onAddBudget: onAddBudget,
            onAddStock: onAddStock,
          ),
          const SizedBox(height: 16),
          _MetricGrid(
            metrics: [
              Metric('Income', money(summary.monthlyIncome, currency: currency),
                  Icons.trending_up, const Color(0xFF16A34A)),
              Metric('Expense', money(summary.monthlyExpense, currency: currency),
                  Icons.trending_down, const Color(0xFFDC2626)),
              Metric('Cash flow', money(summary.cashFlow, currency: currency),
                  Icons.swap_vert, Theme.of(context).colorScheme.primary),
              Metric(
                'Card debt',
                money(summary.creditCardOutstanding, currency: currency),
                Icons.credit_card,
                const Color(0xFFF59E0B),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _BudgetPortfolioRow(summary: summary, currency: currency),
          const SizedBox(height: 16),
          _InsightsPanel(summary.insights),
          const SizedBox(height: 16),
          _TopCategories(summary: summary, currency: currency),
          const SizedBox(height: 16),
          _RecentTransactions(snapshot.transactions, currency: currency),
        ],
      ),
    );
  }
}

class _HeroNetWorthCard extends StatelessWidget {
  const _HeroNetWorthCard({
    required this.summary,
    required this.currency,
    required this.accountCount,
    required this.lastSyncAt,
    required this.userName,
  });

  final FinanceSummary summary;
  final String currency;
  final int accountCount;
  final String? lastSyncAt;
  final String userName;

  @override
  Widget build(BuildContext context) {
    final savingsRate = summary.savingsRate.clamp(0, 1).toDouble();
    return Card(
      color: Theme.of(context).colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hi, $userName',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              money(summary.netWorth, currency: currency),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Net worth - $accountCount accounts - ${syncTime(lastSyncAt)}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: savingsRate,
                backgroundColor: Colors.white24,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Savings rate ${(summary.savingsRate * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    this.onAddExpense,
    this.onAddIncome,
    this.onTransfer,
    this.onAddBudget,
    this.onAddStock,
  });

  final VoidCallback? onAddExpense;
  final VoidCallback? onAddIncome;
  final VoidCallback? onTransfer;
  final VoidCallback? onAddBudget;
  final VoidCallback? onAddStock;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction('Expense', Icons.north_east, onAddExpense),
      _QuickAction('Income', Icons.south_west, onAddIncome),
      _QuickAction('Transfer', Icons.swap_horiz, onTransfer),
      _QuickAction('Budget', Icons.pie_chart_outline, onAddBudget),
      _QuickAction('Stock', Icons.show_chart, onAddStock),
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final action = actions[index];
          return ActionChip(
            avatar: Icon(action.icon, size: 18),
            label: Text(action.label),
            onPressed: action.onPressed,
          );
        },
      ),
    );
  }
}

class _QuickAction {
  const _QuickAction(this.label, this.icon, this.onPressed);

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

class Metric {
  const Metric(this.label, this.value, this.icon, this.color);

  final String label;
  final String value;
  final IconData icon;
  final Color color;
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
        childAspectRatio: 1.45,
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
                Icon(metric.icon, color: metric.color),
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

class _BudgetPortfolioRow extends StatelessWidget {
  const _BudgetPortfolioRow({required this.summary, required this.currency});

  final FinanceSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ProgressCard(
            title: 'Budget',
            value: money(summary.totalBudgetSpent, currency: currency),
            subtitle: 'of ${money(summary.totalBudget, currency: currency)}',
            progress: summary.budgetUsage,
            icon: Icons.pie_chart_outline,
            danger: summary.budgetUsage > 1,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ProgressCard(
            title: 'Portfolio',
            value: money(summary.portfolioValue, currency: currency),
            subtitle: 'P/L ${money(summary.portfolioGain, currency: currency)}',
            progress: summary.portfolioCost <= 0
                ? 0
                : (summary.portfolioValue / summary.portfolioCost).clamp(0, 1.5) / 1.5,
            icon: Icons.show_chart,
            danger: summary.portfolioGain < 0,
          ),
        ),
      ],
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.progress,
    required this.icon,
    this.danger = false,
  });

  final String title;
  final String value;
  final String subtitle;
  final double progress;
  final IconData icon;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.red.shade600 : Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: danger ? color : null,
                  ),
            ),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              minHeight: 8,
              value: progress.clamp(0, 1).toDouble(),
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightsPanel extends StatelessWidget {
  const _InsightsPanel(this.insights);

  final List<FinanceInsight> insights;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Insights',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            ...insights.map(
              (insight) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_insightIcon(insight.severity), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(insight.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(insight.body),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _insightIcon(InsightSeverity severity) {
    return switch (severity) {
      InsightSeverity.warning => Icons.warning_amber_outlined,
      InsightSeverity.positive => Icons.check_circle_outline,
      InsightSeverity.info => Icons.lightbulb_outline,
    };
  }
}

class _TopCategories extends StatelessWidget {
  const _TopCategories({required this.summary, required this.currency});

  final FinanceSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final categories = summary.topExpenseCategories.take(5).toList();
    if (categories.isEmpty) {
      return const EmptyPanel(
        icon: Icons.category_outlined,
        title: 'No spending categories yet',
        body: 'Add expenses with categories to see where money is going.',
      );
    }
    final maxAmount = categories.first.amount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top spending',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            ...categories.map(
              (category) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(category.name)),
                        Text(money(category.amount, currency: currency)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      minHeight: 7,
                      value: maxAmount <= 0 ? 0 : category.amount / maxAmount,
                    ),
                  ],
                ),
              ),
            ),
          ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent activity',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            Text('${transactions.length} cached'),
          ],
        ),
        const SizedBox(height: 10),
        if (transactions.isEmpty)
          const EmptyPanel(
            icon: Icons.receipt_long_outlined,
            title: 'No transactions yet',
            body: 'Add an expense, income, or transfer to start tracking.',
          )
        else
          ...transactions.take(8).map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TransactionTile(row: row, currency: currency),
                ),
              ),
      ],
    );
  }
}

class NoticePanel extends StatelessWidget {
  const NoticePanel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
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
