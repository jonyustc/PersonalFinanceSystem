import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';

class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final currency = snapshot.session?.currency ?? 'BDT';
    final categories = {
      for (final row in snapshot.categories) row['id'] as String: row,
    };
    final expenseByCategory = <String, double>{};
    final monthlyCashflow = <String, double>{};

    for (final row in snapshot.transactions) {
      final amount = asDouble(row['amount']);
      final type = row['type'] as String? ?? 'expense';
      final date = DateTime.tryParse(row['txn_date'] as String? ?? '');
      if (date != null) {
        final key = '${date.month}/${date.year.toString().substring(2)}';
        monthlyCashflow[key] = (monthlyCashflow[key] ?? 0) +
            (type == 'income' ? amount : -amount);
      }
      if (type == 'expense') {
        final categoryId = row['category_id'] as String?;
        final name = categories[categoryId]?['name'] as String? ?? 'Uncategorized';
        expenseByCategory[name] = (expenseByCategory[name] ?? 0) + amount;
      }
    }

    final sortedCategories = expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sortedMonths = monthlyCashflow.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Expense mix',
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
                                centerSpaceRadius: 44,
                                sections: sortedCategories.take(6).map((entry) {
                                  final index = sortedCategories.indexOf(entry);
                                  return PieChartSectionData(
                                    value: entry.value,
                                    title: '${index + 1}',
                                    radius: 72,
                                    color: _chartColors[index % _chartColors.length],
                                    titleStyle: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...sortedCategories.take(6).map((entry) {
                            final index = sortedCategories.indexOf(entry);
                            return _LegendRow(
                              color: _chartColors[index % _chartColors.length],
                              label: entry.key,
                              value: money(entry.value, currency: currency),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Cashflow trend',
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
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  leftTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        final index = value.toInt();
                                        if (index < 0 || index >= sortedMonths.length) {
                                          return const SizedBox.shrink();
                                        }
                                        return Text(
                                          sortedMonths[index].key,
                                          style: const TextStyle(fontSize: 11),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                barGroups: List.generate(sortedMonths.length, (index) {
                                  final value = sortedMonths[index].value;
                                  return BarChartGroupData(
                                    x: index,
                                    barRods: [
                                      BarChartRodData(
                                        toY: value.abs(),
                                        color: value >= 0
                                            ? const Color(0xFF16A34A)
                                            : const Color(0xFFDC2626),
                                        borderRadius: BorderRadius.circular(6),
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
                  ),
                ],
              ],
            ),
          ),
        ],
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
];

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
