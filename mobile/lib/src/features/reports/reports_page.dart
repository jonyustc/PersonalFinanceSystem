import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance_summary.dart';
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';
import '../transactions/transaction_tile.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  String? _selectedCategoryId;

  @override
  Widget build(BuildContext context) {
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
    final categoryById = {
      for (final row in snapshot.categories) row['id'] as String: row,
    };
    final selectedTransactions = _transactionsForCategory(
      snapshot.transactions,
      snapshot.categories,
      _selectedCategoryId,
    );
    final selectedName = _selectedCategoryId == null
        ? null
        : categoryById[_selectedCategoryId]?['name'] as String? ?? 'Category';

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(
            title: Text('Reports'),
            pinned: true,
            automaticallyImplyLeading: false,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                if (snapshot.transactions.isEmpty)
                  const EmptyPanel(
                    icon: Icons.analytics_outlined,
                    title: 'No report data yet',
                    body: 'Add transactions or sync to build charts locally.',
                  )
                else ...[
                  _ReportHeader(
                    summary: summary,
                    currency: currency,
                    onExport: () => _copyCsv(context, summary, currency),
                  ),
                  const SizedBox(height: 16),
                  _InsightList(summary.insights),
                  const SizedBox(height: 16),
                  _ExpenseBreakdown(
                    summary: summary,
                    currency: currency,
                    selectedCategoryId: _selectedCategoryId,
                    onSelected: (categoryId) {
                      setState(() {
                        _selectedCategoryId =
                            _selectedCategoryId == categoryId ? null : categoryId;
                      });
                    },
                  ),
                  if (_selectedCategoryId != null) ...[
                    const SizedBox(height: 12),
                    _RelatedTransactions(
                      title: '$selectedName transactions',
                      rows: selectedTransactions,
                      currency: currency,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _IncomeExpenseTrend(summary.monthlyTrend),
                  const SizedBox(height: 16),
                  _BudgetActualChart(
                    budget: summary.totalBudget,
                    spent: summary.totalBudgetSpent,
                    currency: currency,
                  ),
                  const SizedBox(height: 16),
                  _AccountSpending(summary.accountSpending, currency: currency),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _transactionsForCategory(
    List<Map<String, dynamic>> transactions,
    List<Map<String, dynamic>> categories,
    String? categoryId,
  ) {
    if (categoryId == null) return const [];
    final childIds = categories
        .where((row) => row['parent_id'] == categoryId)
        .map((row) => row['id'] as String)
        .toSet();
    return transactions.where((row) {
      final rowCategory = row['category_id'] as String?;
      return rowCategory == categoryId || childIds.contains(rowCategory);
    }).toList();
  }

  Future<void> _copyCsv(
    BuildContext context,
    FinanceSummary summary,
    String currency,
  ) async {
    final rows = [
      'Metric,Value,Currency',
      'Net worth,${summary.netWorth.toStringAsFixed(2)},$currency',
      'Monthly income,${summary.monthlyIncome.toStringAsFixed(2)},$currency',
      'Monthly expense,${summary.monthlyExpense.toStringAsFixed(2)},$currency',
      'Cash flow,${summary.cashFlow.toStringAsFixed(2)},$currency',
      'Budget spent,${summary.totalBudgetSpent.toStringAsFixed(2)},$currency',
      'Portfolio value,${summary.portfolioValue.toStringAsFixed(2)},$currency',
      '',
      'Category,Amount,Currency',
      ...summary.topExpenseCategories.map(
        (row) => '${row.name},${row.amount.toStringAsFixed(2)},$currency',
      ),
    ];
    await Clipboard.setData(ClipboardData(text: rows.join('\n')));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV copied to clipboard')),
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.summary,
    required this.currency,
    required this.onExport,
  });

  final FinanceSummary summary;
  final String currency;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Financial report',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Export CSV',
                  onPressed: onExport,
                  icon: const Icon(Icons.download_outlined),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ReportMetric(
                    label: 'Income',
                    value: money(summary.monthlyIncome, currency: currency),
                  ),
                ),
                Expanded(
                  child: _ReportMetric(
                    label: 'Expense',
                    value: money(summary.monthlyExpense, currency: currency),
                    danger: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ReportMetric(
              label: 'Cash flow',
              value: money(summary.cashFlow, currency: currency),
              danger: summary.cashFlow < 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
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
                color: danger ? Colors.red.shade600 : null,
              ),
        ),
      ],
    );
  }
}

class _InsightList extends StatelessWidget {
  const _InsightList(this.insights);

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
              'Smart insights',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            ...insights.map(
              (row) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(row.title),
                subtitle: Text(row.body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseBreakdown extends StatelessWidget {
  const _ExpenseBreakdown({
    required this.summary,
    required this.currency,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  final FinanceSummary summary;
  final String currency;
  final String? selectedCategoryId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final rows = summary.topExpenseCategories.take(8).toList();
    if (rows.isEmpty) {
      return const EmptyPanel(
        icon: Icons.donut_large,
        title: 'No expenses to chart',
        body: 'Categorized expenses will appear here.',
      );
    }
    final total = rows.fold<double>(0, (sum, row) => sum + row.amount);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Expense breakdown',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 220,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 48,
                  pieTouchData: PieTouchData(
                    touchCallback: (_, response) {
                      final index = response?.touchedSection?.touchedSectionIndex;
                      if (index != null && index >= 0 && index < rows.length) {
                        onSelected(rows[index].categoryId);
                      }
                    },
                  ),
                  sections: List.generate(rows.length, (index) {
                    final row = rows[index];
                    final selected = selectedCategoryId == row.categoryId;
                    return PieChartSectionData(
                      value: row.amount,
                      title: total <= 0
                          ? ''
                          : '${(row.amount / total * 100).round()}%',
                      radius: selected ? 82 : 72,
                      color: _chartColors[index % _chartColors.length],
                      titleStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(rows.length, (index) {
              final row = rows[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 6,
                  backgroundColor: _chartColors[index % _chartColors.length],
                ),
                title: Text(row.name),
                trailing: Text(money(row.amount, currency: currency)),
                selected: selectedCategoryId == row.categoryId,
                onTap: () => onSelected(row.categoryId),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _RelatedTransactions extends StatelessWidget {
  const _RelatedTransactions({
    required this.title,
    required this.rows,
    required this.currency,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const Text('No matching transactions.')
            else
              ...rows.take(6).map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TransactionTile(row: row, currency: currency),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

class _IncomeExpenseTrend extends StatelessWidget {
  const _IncomeExpenseTrend(this.rows);

  final List<MonthlyTotal> rows;

  @override
  Widget build(BuildContext context) {
    final chartRows = rows.take(6).toList();
    if (chartRows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Income vs expense',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= chartRows.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(chartRows[index].label, style: const TextStyle(fontSize: 11));
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(chartRows.length, (index) {
                    final row = chartRows[index];
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: row.income,
                          color: const Color(0xFF16A34A),
                          width: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        BarChartRodData(
                          toY: row.expense,
                          color: const Color(0xFFDC2626),
                          width: 8,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetActualChart extends StatelessWidget {
  const _BudgetActualChart({
    required this.budget,
    required this.spent,
    required this.currency,
  });

  final double budget;
  final double spent;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final maxAmount = [budget, spent, 1].reduce((a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Budget vs actual',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  maxY: maxAmount * 1.2,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: budget,
                          color: const Color(0xFF2563EB),
                          width: 34,
                          borderRadius: BorderRadius.all(Radius.circular(6)),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: spent,
                          color: spent > budget ? const Color(0xFFDC2626) : const Color(0xFF0F766E),
                          width: 34,
                          borderRadius: const BorderRadius.all(Radius.circular(6)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                Expanded(child: Text('Budget ${money(budget, currency: currency)}')),
                Expanded(child: Text('Spent ${money(spent, currency: currency)}')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountSpending extends StatelessWidget {
  const _AccountSpending(this.rows, {required this.currency});

  final List<AccountTotal> rows;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyPanel(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No account spending',
        body: 'Expenses by account will show after transactions are added.',
      );
    }
    final maxAmount = rows.first.amount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Account-wise spending',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            ...rows.take(6).map(
                  (row) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(row.name)),
                            Text(money(row.amount, currency: currency)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          minHeight: 7,
                          value: maxAmount <= 0 ? 0 : row.amount / maxAmount,
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

const _chartColors = [
  Color(0xFF0F766E),
  Color(0xFF2563EB),
  Color(0xFFF59E0B),
  Color(0xFF7C3AED),
  Color(0xFFDB2777),
  Color(0xFF0891B2),
  Color(0xFF475569),
  Color(0xFF65A30D),
];
