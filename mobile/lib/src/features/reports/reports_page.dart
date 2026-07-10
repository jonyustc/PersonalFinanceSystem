import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance_summary.dart' show countsInTotals;
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../theme/category_visuals.dart';
import '../../widgets/app_card.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/metric_grid.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';
import '../dashboard/dashboard_page.dart';
import '../transactions/transaction_tile.dart';

/// Whether a transaction counts as an expense for category reports. Mirrors the
/// backend report filter: `type == 'expense'` OR `transaction_type` is
/// CARD_SPENDING (`report.py`).
bool _isReportExpense(Map<String, dynamic> row) {
  if (row['type'] == 'expense') return true;
  return _reportTxnType(row) == 'CARD_SPENDING';
}

String? _reportTxnType(Map<String, dynamic> row) {
  final direct = row['transaction_type'];
  if (direct is String) return direct;
  final raw = row['raw_json'];
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded['transaction_type'] as String?;
    } catch (_) {
      return null;
    }
  }
  return null;
}

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  late DateTime _start;
  late DateTime _end;
  final Set<String> _categoryFilterIds = {};
  String? _parentId;
  String? _leafCategoryId;
  int _selectedIndex = 0;
  String _reportMode = 'expenses';
  String _period = 'month';
  Future<Map<String, dynamic>>? _cardReportFuture;
  String? _cardReportKey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month);
    _end = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) {
      return const ListSkeleton();
    }

    final expenseCategories = _mainExpenseCategories(snapshot.categories);
    final currency = snapshot.session?.currency ?? 'BDT';
    final rows = _buildRows(
      categories: snapshot.categories,
      transactions: snapshot.transactions,
      parentId: _parentId,
      categoryFilterIds: _categoryFilterIds,
    );
    final transactions = _leafCategoryId == null
        ? <Map<String, dynamic>>[]
        : _transactionsForCategory(snapshot.transactions, _leafCategoryId!);
    final total = rows.fold<double>(0, (sum, row) => sum + row.amount);
    final title = _leafCategoryId == null
        ? (_parentId == null
              ? 'Expense categories'
              : _categoryName(snapshot.categories, _parentId!) ??
                    'Subcategories')
        : _categoryName(snapshot.categories, _leafCategoryId!) ??
              'Transactions';

    final canGoBack = _parentId != null || _leafCategoryId != null;
    final atTopLevel = _parentId == null && _leafCategoryId == null;
    final income = _incomeInRange(snapshot.transactions);
    final previousSpent = _previousPeriodExpense(snapshot.transactions);
    final trend = _monthlyExpenseTrend(snapshot.transactions);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            _ReportModeSwitch(value: _reportMode, onChanged: _setReportMode),
            const SizedBox(height: AppSpacing.md),
            if (_reportMode == 'expenses') ...[
              if (atTopLevel) ...[
                _PeriodSwitch(value: _period, onChanged: _setPeriod),
                const SizedBox(height: AppSpacing.md),
              ],
              _ReportHeader(
                title: title,
                start: _start,
                end: _end,
                categories: expenseCategories,
                allCategories: snapshot.categories,
                selectedCategoryIds: _categoryFilterIds,
                canGoBack: canGoBack,
                onBack: _back,
                onCategoriesChanged: _setCategoryFilters,
                onPrevious: _previousRange,
                onNext: _nextRange,
                onPickRange: _pickRange,
              ),
              const SizedBox(height: 14),
              if (atTopLevel) ...[
                _SpendingSummary(
                  spent: total,
                  income: income,
                  previousSpent: previousSpent,
                  start: _start,
                  end: _end,
                  currency: currency,
                ),
                const SizedBox(height: 16),
                if (trend.any((point) => point.amount > 0)) ...[
                  _TrendChart(data: trend, currency: currency),
                  const SizedBox(height: 16),
                ],
              ],
              if (_leafCategoryId == null)
                if (rows.isEmpty)
                  const EmptyPanel(
                    icon: Icons.pie_chart_outline,
                    title: 'No expense data',
                    body:
                        'Add categorized expense transactions or choose a wider date range.',
                  )
                else ...[
                  _PieSummary(
                    rows: rows,
                    total: total,
                    currency: currency,
                    selectedIndex: _selectedIndex,
                    onSelected: (index) =>
                        setState(() => _selectedIndex = index),
                  ),
                  const SizedBox(height: 16),
                  _CategoryBreakdown(
                    rows: rows,
                    total: total,
                    currency: currency,
                    onSelected: (row) => _openRow(row, snapshot.categories),
                  ),
                ]
              else
                _TransactionList(
                  categoryName: title,
                  transactions: transactions,
                  categories: snapshot.categories,
                  currency: currency,
                ),
            ] else ...[
              _CardReportHeader(
                start: _start,
                end: _end,
                onPrevious: _previousRange,
                onNext: _nextRange,
                onPickRange: _pickRange,
              ),
              const SizedBox(height: 14),
              _CardReportSection(
                future: _cardReportFutureFor(ref),
                currency: currency,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _setReportMode(String value) {
    setState(() {
      _reportMode = value;
      _parentId = null;
      _leafCategoryId = null;
      _selectedIndex = 0;
    });
  }

  void _setPeriod(String period) {
    final now = DateTime.now();
    setState(() {
      _period = period;
      switch (period) {
        case 'week':
          final start = now.subtract(Duration(days: now.weekday - 1));
          _start = DateTime(start.year, start.month, start.day);
          _end = DateTime(_start.year, _start.month, _start.day + 6, 23, 59, 59);
        case 'year':
          _start = DateTime(now.year);
          _end = DateTime(now.year, 12, 31, 23, 59, 59);
        case 'month':
        default:
          _start = DateTime(now.year, now.month);
          _end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      }
      _parentId = null;
      _leafCategoryId = null;
      _selectedIndex = 0;
    });
  }

  /// Total income posted within the current range.
  double _incomeInRange(List<Map<String, dynamic>> transactions) {
    var total = 0.0;
    for (final row in transactions) {
      if (row['type'] != 'income') continue;
      if (!countsInTotals(row)) continue;
      if (!_isInRange(row)) continue;
      total += asDouble(row['amount']);
    }
    return total;
  }

  /// Total expense in the period immediately before the current one (same
  /// length), used for the period-over-period comparison.
  double _previousPeriodExpense(List<Map<String, dynamic>> transactions) {
    final spanDays = _end.difference(_start).inDays + 1;
    final prevEnd = _start.subtract(const Duration(seconds: 1));
    final prevStart = _start.subtract(Duration(days: spanDays));
    var total = 0.0;
    for (final row in transactions) {
      if (!_isReportExpense(row)) continue;
      if (!countsInTotals(row)) continue;
      final date = DateTime.tryParse(row['txn_date'] as String? ?? '');
      if (date == null) continue;
      if (date.isBefore(prevStart) || date.isAfter(prevEnd)) continue;
      total += asDouble(row['amount']);
    }
    return total;
  }

  /// Expense totals for the last 6 calendar months (oldest → newest).
  List<({String label, double amount})> _monthlyExpenseTrend(
    List<Map<String, dynamic>> transactions,
  ) {
    final now = DateTime.now();
    final months = List.generate(
      6,
      (i) => DateTime(now.year, now.month - (5 - i)),
    );
    final totals = {for (final m in months) '${m.year}-${m.month}': 0.0};
    for (final row in transactions) {
      if (!_isReportExpense(row)) continue;
      if (!countsInTotals(row)) continue;
      final date = DateTime.tryParse(row['txn_date'] as String? ?? '');
      if (date == null) continue;
      final key = '${date.year}-${date.month}';
      if (totals.containsKey(key)) {
        totals[key] = totals[key]! + asDouble(row['amount']);
      }
    }
    const labels = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return [
      for (final m in months)
        (label: labels[m.month - 1], amount: totals['${m.year}-${m.month}'] ?? 0),
    ];
  }

  void _back() {
    setState(() {
      if (_leafCategoryId != null) {
        _leafCategoryId = null;
      } else {
        _parentId = null;
      }
      _selectedIndex = 0;
    });
  }

  void _openRow(_ReportRow row, List<Map<String, dynamic>> categories) {
    // When already drilled into this category, the tapped row is the parent's
    // own direct-spend bucket — show those transactions instead of re-drilling
    // into the same subcategory level (which looked like "nothing happens").
    if (row.categoryId == _parentId) {
      setState(() {
        _leafCategoryId = row.categoryId;
        _selectedIndex = 0;
      });
      return;
    }
    final hasChildren = categories.any(
      (category) => category['parent_id'] == row.categoryId,
    );
    setState(() {
      if (hasChildren) {
        _parentId = row.categoryId;
        _leafCategoryId = null;
      } else {
        _leafCategoryId = row.categoryId;
      }
      _selectedIndex = 0;
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _start, end: _end),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _start = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _end = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
        23,
        59,
        59,
      );
      _parentId = null;
      _leafCategoryId = null;
      _selectedIndex = 0;
    });
  }

  void _previousRange() {
    final days = _end.difference(_start).inDays + 1;
    setState(() {
      _start = _start.subtract(Duration(days: days));
      _end = _end.subtract(Duration(days: days));
      _parentId = null;
      _leafCategoryId = null;
      _selectedIndex = 0;
    });
  }

  void _nextRange() {
    final days = _end.difference(_start).inDays + 1;
    setState(() {
      _start = _start.add(Duration(days: days));
      _end = _end.add(Duration(days: days));
      _parentId = null;
      _leafCategoryId = null;
      _selectedIndex = 0;
    });
  }

  void _setCategoryFilters(Set<String> categoryIds) {
    setState(() {
      _categoryFilterIds
        ..clear()
        ..addAll(categoryIds);
      _parentId = null;
      _leafCategoryId = null;
      _selectedIndex = 0;
    });
  }

  List<_ReportRow> _buildRows({
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> transactions,
    required String? parentId,
    required Set<String> categoryFilterIds,
  }) {
    final categoryById = {
      for (final row in categories) row['id'] as String: row,
    };
    final totals = <String, double>{};
    final names = <String, String>{};

    for (final transaction in transactions) {
      if (!_isReportExpense(transaction)) continue;
      if (!countsInTotals(transaction)) continue;
      if (!_isInRange(transaction)) continue;
      final rawCategoryId = transaction['category_id'] as String?;
      if (rawCategoryId == null) continue;
      final category = categoryById[rawCategoryId];
      if (category == null) continue;
      final categoryParentId = category['parent_id'] as String?;
      final mainCategoryId = categoryParentId ?? rawCategoryId;
      if (categoryFilterIds.isNotEmpty &&
          !_matchesCategoryFilter(
            rawCategoryId,
            categoryById,
            categoryFilterIds,
          )) {
        continue;
      }

      final bucketId = parentId == null
          ? mainCategoryId
          : categoryParentId == parentId
          ? rawCategoryId
          : rawCategoryId == parentId
          ? rawCategoryId
          : null;
      if (bucketId == null) continue;
      final bucketCategory = categoryById[bucketId];
      names[bucketId] = bucketCategory?['name'] as String? ?? 'Category';
      totals[bucketId] =
          (totals[bucketId] ?? 0) + asDouble(transaction['amount']);
    }

    return totals.entries
        .map(
          (entry) => _ReportRow(
            categoryId: entry.key,
            name: names[entry.key] ?? 'Category',
            amount: entry.value,
          ),
        )
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
  }

  List<Map<String, dynamic>> _transactionsForCategory(
    List<Map<String, dynamic>> transactions,
    String categoryId,
  ) {
    return transactions
        .where(
          (transaction) =>
              _isReportExpense(transaction) &&
              transaction['category_id'] == categoryId &&
              _isInRange(transaction),
        )
        .toList()
      ..sort(
        (a, b) => (b['txn_date'] as String? ?? '').compareTo(
          a['txn_date'] as String? ?? '',
        ),
      );
  }

  bool _isInRange(Map<String, dynamic> transaction) {
    final date = DateTime.tryParse(transaction['txn_date'] as String? ?? '');
    if (date == null) return false;
    return !date.isBefore(_start) && !date.isAfter(_end);
  }

  String? _categoryName(List<Map<String, dynamic>> categories, String id) {
    for (final row in categories) {
      if (row['id'] == id) return row['name'] as String?;
    }
    return null;
  }

  bool _matchesCategoryFilter(
    String categoryId,
    Map<String, Map<String, dynamic>> categoryById,
    Set<String> filterIds,
  ) {
    if (filterIds.contains(categoryId)) return true;
    var current = categoryById[categoryId];
    while (current != null) {
      final parentId = current['parent_id'] as String?;
      if (parentId == null) return false;
      if (filterIds.contains(parentId)) return true;
      current = categoryById[parentId];
    }
    return false;
  }

  /// Top-level expense categories only. Selecting one filters that category
  /// plus all of its subcategories (see [_matchesCategoryFilter]), so the
  /// picker stays simple instead of mixing parents and children together.
  List<Map<String, dynamic>> _mainExpenseCategories(
    List<Map<String, dynamic>> categories,
  ) {
    final rows = categories
        .where(
          (category) =>
              category['type'] == 'expense' && category['parent_id'] == null,
        )
        .toList()
      ..sort(
        (a, b) => (a['name'] as String? ?? '').compareTo(
          b['name'] as String? ?? '',
        ),
      );
    return rows;
  }

  Future<Map<String, dynamic>> _cardReportFutureFor(WidgetRef ref) {
    final fromDate = _date(_start);
    final toDate = _date(_end);
    final key = '$fromDate:$toDate';
    if (_cardReportFuture == null || _cardReportKey != key) {
      _cardReportKey = key;
      _cardReportFuture = ref
          .read(apiClientProvider)
          .getCardReport(fromDate: fromDate, toDate: toDate);
    }
    return _cardReportFuture!;
  }
}

class _ReportRow {
  const _ReportRow({
    required this.categoryId,
    required this.name,
    required this.amount,
  });

  final String categoryId;
  final String name;
  final double amount;
}

class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: 'week', label: Text('Week')),
        ButtonSegment(value: 'month', label: Text('Month')),
        ButtonSegment(value: 'year', label: Text('Year')),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

/// Headline spend card: big total, period-over-period change, and a row of
/// income / net / daily-average metrics. The expense-tracking centerpiece.
class _SpendingSummary extends StatelessWidget {
  const _SpendingSummary({
    required this.spent,
    required this.income,
    required this.previousSpent,
    required this.start,
    required this.end,
    required this.currency,
  });

  final double spent;
  final double income;
  final double previousSpent;
  final DateTime start;
  final DateTime end;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final net = income - spent;
    final now = DateTime.now();
    final cappedEnd = end.isAfter(now) ? now : end;
    final elapsedDays = (cappedEnd.difference(start).inDays + 1).clamp(1, 100000);
    final dailyAvg = spent / elapsedDays;
    final hasPrevious = previousSpent > 0;
    final changePercent = hasPrevious
        ? (spent - previousSpent) / previousSpent * 100
        : 0.0;
    final spendingUp = changePercent >= 0;
    final changeColor = AppColors.amount(context, positive: !spendingUp);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SPENT',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: MoneyText(
              spent,
              currency: currency,
              autoFit: true,
              color: AppColors.amount(context, positive: false),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
          ),
          if (hasPrevious) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(
                  spendingUp ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 16,
                  color: changeColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${changePercent.abs().toStringAsFixed(0)}% vs previous period',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: changeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: AppSpacing.xl),
          Row(
            children: [
              _SummaryMetric(
                label: 'Income',
                amount: income,
                currency: currency,
                color: AppColors.amount(context, positive: true),
              ),
              _SummaryMetric(
                label: 'Net',
                amount: net,
                currency: currency,
                signed: true,
                color: AppColors.amount(context, positive: net >= 0),
              ),
              _SummaryMetric(
                label: 'Daily avg',
                amount: dailyAvg,
                currency: currency,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.amount,
    required this.currency,
    this.color,
    this.signed = false,
  });

  final String label;
  final double amount;
  final String currency;
  final Color? color;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MoneyText(
            amount,
            currency: currency,
            signed: signed,
            color: color,
            autoFit: true,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 6-month expense bar chart so the user can see whether spending is trending
/// up or down at a glance.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.data, required this.currency});

  final List<({String label, double amount})> data;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    var maxValue = 0.0;
    for (final point in data) {
      if (point.amount > maxValue) maxValue = point.amount;
    }
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.25;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Spending trend', subtitle: 'Last 6 months'),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                maxY: maxY,
                alignment: BarChartAlignment.spaceAround,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                      money(rod.toY, currency: currency),
                      TextStyle(
                        color: scheme.onInverseSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= data.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            data[index].label,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < data.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: data[i].amount,
                          width: 18,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(6),
                          ),
                          color: i == data.length - 1
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.35),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportModeSwitch extends StatelessWidget {
  const _ReportModeSwitch({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment<String>(
          value: 'expenses',
          icon: Icon(Icons.pie_chart_outline),
          label: Text('Expenses'),
        ),
        ButtonSegment<String>(
          value: 'cards',
          icon: Icon(Icons.credit_card_outlined),
          label: Text('Cards'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _CardReportHeader extends StatelessWidget {
  const _CardReportHeader({
    required this.start,
    required this.end,
    required this.onPrevious,
    required this.onNext,
    required this.onPickRange,
  });

  final DateTime start;
  final DateTime end;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(
            'Card spend & payments',
            subtitle: 'Authoritative figures from the server',
          ),
          const SizedBox(height: AppSpacing.md),
          _RangeNav(
            start: start,
            end: end,
            onPrevious: onPrevious,
            onNext: onNext,
            onPickRange: onPickRange,
          ),
        ],
      ),
    );
  }
}

/// Shared previous / range-picker / next control used by both report headers.
class _RangeNav extends StatelessWidget {
  const _RangeNav({
    required this.start,
    required this.end,
    required this.onPrevious,
    required this.onNext,
    required this.onPickRange,
  });

  final DateTime start;
  final DateTime end;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'Previous range',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onPickRange,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              '${_date(start)} → ${_date(end)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Next range',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.title,
    required this.start,
    required this.end,
    required this.categories,
    required this.allCategories,
    required this.selectedCategoryIds,
    required this.canGoBack,
    required this.onBack,
    required this.onCategoriesChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onPickRange,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> allCategories;
  final Set<String> selectedCategoryIds;
  final bool canGoBack;
  final VoidCallback onBack;
  final ValueChanged<Set<String>> onCategoriesChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = _categoryFilterLabel(
      categories,
      allCategories,
      selectedCategoryIds,
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (canGoBack)
                IconButton(
                  tooltip: 'Back',
                  visualDensity: VisualDensity.compact,
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => _showMainCategoryPicker(context),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Categories',
                isDense: true,
                prefixIcon: Icon(Icons.filter_list),
                suffixIcon: Icon(Icons.expand_more),
              ),
              child: Text(
                selectedLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
          if (selectedCategoryIds.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: categories
                  .where(
                    (category) =>
                        selectedCategoryIds.contains(category['id'] as String),
                  )
                  .map(
                    (category) => InputChip(
                      label: Text(_categoryDisplayName(category, allCategories)),
                      onDeleted: () {
                        final next = Set<String>.from(selectedCategoryIds)
                          ..remove(category['id'] as String);
                        onCategoriesChanged(next);
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _RangeNav(
            start: start,
            end: end,
            onPrevious: onPrevious,
            onNext: onNext,
            onPickRange: onPickRange,
          ),
        ],
      ),
    );
  }

  Future<void> _showMainCategoryPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _MainCategoryPickerSheet(
        categories: categories,
        allCategories: allCategories,
        selectedIds: selectedCategoryIds,
      ),
    );
    if (picked == null) return;
    onCategoriesChanged(picked);
  }
}

class _CardReportSection extends StatelessWidget {
  const _CardReportSection({required this.future, required this.currency});

  final Future<Map<String, dynamic>> future;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppCard(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return AppCard(
            child: Text(
              'Card report unavailable. Pull to sync or try again.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          );
        }

        final report = snapshot.data ?? {};
        final cards = (report['cards'] as List? ?? [])
            .whereType<Map>()
            .map((row) => row.cast<String, dynamic>())
            .toList();
        final spentHistory = (report['spent_history'] as List? ?? [])
            .whereType<Map>()
            .map((row) => row.cast<String, dynamic>())
            .toList();
        final paymentHistory = (report['payment_history'] as List? ?? [])
            .whereType<Map>()
            .map((row) => row.cast<String, dynamic>())
            .toList();

        return Column(
          children: [
            MetricGrid(
              children: [
                StatCard(
                  label: 'Spent',
                  amount: asDouble(report['total_spent']),
                  currency: currency,
                  icon: Icons.shopping_bag_outlined,
                  amountColor: AppColors.amount(context, positive: false),
                ),
                StatCard(
                  label: 'Paid',
                  amount: asDouble(report['total_paid']),
                  currency: currency,
                  icon: Icons.payments_outlined,
                  amountColor: AppColors.amount(context, positive: true),
                ),
                StatCard(
                  label: 'Outstanding',
                  amount: asDouble(report['total_outstanding']),
                  currency: currency,
                  icon: Icons.credit_card_outlined,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader('Cards'),
                  const SizedBox(height: AppSpacing.md),
                  if (cards.isEmpty)
                    Text(
                      'No credit cards found.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    ...cards.map(
                      (card) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _CardReportCardRow(
                          card: card,
                          currency: currency,
                        ),
                      ),
                    ),
                  const Divider(height: AppSpacing.xl),
                  _CardHistoryList(
                    title: 'Payment history',
                    emptyText: 'No card payments in this range.',
                    rows: paymentHistory,
                    currency: currency,
                    icon: Icons.payments_outlined,
                    color: AppColors.amount(context, positive: true),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _CardHistoryList(
                    title: 'Spent history',
                    emptyText: 'No card spending in this range.',
                    rows: spentHistory,
                    currency: currency,
                    icon: Icons.shopping_bag_outlined,
                    color: AppColors.amount(context, positive: false),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CardReportCardRow extends StatelessWidget {
  const _CardReportCardRow({required this.card, required this.currency});

  final Map<String, dynamic> card;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final spent = asDouble(card['spent']);
    final paid = asDouble(card['paid']);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            const Icon(Icons.credit_card, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card['name'] as String? ?? 'Card',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Spent ${money(spent, currency: currency)} - Paid ${money(paid, currency: currency)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              money(asDouble(card['current_outstanding']), currency: currency),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardHistoryList extends StatelessWidget {
  const _CardHistoryList({
    required this.title,
    required this.emptyText,
    required this.rows,
    required this.currency,
    required this.icon,
    required this.color,
  });

  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> rows;
  final String currency;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (visibleRows.isEmpty)
          Text(
            emptyText,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          ...visibleRows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: color.withValues(alpha: 0.12),
                    foregroundColor: color,
                    child: Icon(icon, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['merchant_name'] as String? ??
                              row['description'] as String? ??
                              row['card_name'] as String? ??
                              'Card transaction',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          [
                            row['txn_date'] as String? ?? '',
                            row['card_name'] as String? ?? '',
                            if ((row['account_name'] as String? ?? '')
                                .isNotEmpty)
                              row['account_name'] as String,
                          ].where((value) => value.isNotEmpty).join(' - '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    money(asDouble(row['amount']), currency: currency),
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MainCategoryPickerSheet extends StatefulWidget {
  const _MainCategoryPickerSheet({
    required this.categories,
    required this.allCategories,
    required this.selectedIds,
  });

  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> allCategories;
  final Set<String> selectedIds;

  @override
  State<_MainCategoryPickerSheet> createState() =>
      _MainCategoryPickerSheetState();
}

class _MainCategoryPickerSheetState extends State<_MainCategoryPickerSheet> {
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.selectedIds);
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.68,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Categories',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selectedIds.isEmpty,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('All categories'),
              onChanged: (_) => setState(_selectedIds.clear),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: widget.categories.map((category) {
                  final id = category['id'] as String;
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selectedIds.contains(id),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      _categoryDisplayName(category, widget.allCategories),
                    ),
                    onChanged: (selected) {
                      setState(() {
                        if (selected == true) {
                          _selectedIds.add(id);
                        } else {
                          _selectedIds.remove(id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(_selectedIds.clear),
                  child: const Text('Clear'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(_selectedIds),
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PieSummary extends StatelessWidget {
  const _PieSummary({
    required this.rows,
    required this.total,
    required this.currency,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_ReportRow> rows;
  final double total;
  final String currency;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1.25,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 58,
                  pieTouchData: PieTouchData(
                    touchCallback: (_, response) {
                      final index =
                          response?.touchedSection?.touchedSectionIndex;
                      if (index == null || index < 0 || index >= rows.length) {
                        return;
                      }
                      onSelected(index);
                    },
                  ),
                  sections: List.generate(rows.length, (index) {
                    final row = rows[index];
                    final selected = index == selectedIndex;
                    final percent = total <= 0 ? 0 : row.amount / total * 100;
                    final color = _chartColors[index % _chartColors.length];
                    return PieChartSectionData(
                      value: row.amount,
                      color: color,
                      radius: selected ? 78 : 68,
                      title: '${_chartLabel(row.name)}\n${percent.round()}%',
                      titlePositionPercentageOffset: 0.62,
                      titleStyle: TextStyle(
                        color: _textOnColor(color),
                        fontSize: selected ? 12 : 10,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              money(total, currency: currency),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            Text(
              'Total expense',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.rows,
    required this.total,
    required this.currency,
    required this.onSelected,
  });

  final List<_ReportRow> rows;
  final double total;
  final String currency;
  final ValueChanged<_ReportRow> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: List.generate(rows.length, (index) {
          final row = rows[index];
          final percent = total <= 0 ? 0.0 : row.amount / total;
          final color = _chartColors[index % _chartColors.length];
          return InkWell(
            onTap: () => onSelected(row),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      categoryVisual(name: row.name).icon,
                      size: 19,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              money(row.amount, currency: currency),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: LinearProgressIndicator(
                            value: percent.clamp(0, 1).toDouble(),
                            minHeight: 5,
                            backgroundColor: AppColors.border(context),
                            valueColor: AlwaysStoppedAnimation(color),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${(percent * 100).round()}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.categoryName,
    required this.transactions,
    required this.categories,
    required this.currency,
  });

  final String categoryName;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> categories;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final categoryById = {
      for (final c in categories) c['id'] as String: c,
    };
    // Excluded rows remain visible in the list below but don't count in the
    // category header total.
    final total = transactions.fold<double>(
      0,
      (sum, transaction) =>
          sum + (countsInTotals(transaction) ? asDouble(transaction['amount']) : 0),
    );
    if (transactions.isEmpty) {
      return const EmptyPanel(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions',
        body: 'No expense transactions are available for this category.',
      );
    }
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      categoryName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${transactions.length} transactions',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              MoneyText(
                total,
                currency: currency,
                color: AppColors.amount(context, positive: false),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        ...transactions.map(
          (transaction) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: TransactionTile(
              row: transaction,
              currency: currency,
              category: categoryById[transaction['category_id']],
            ),
          ),
        ),
      ],
    );
  }
}

String _date(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

String _categoryFilterLabel(
  List<Map<String, dynamic>> categories,
  List<Map<String, dynamic>> allCategories,
  Set<String> selectedIds,
) {
  if (selectedIds.isEmpty) return 'All categories';
  final names = categories
      .where((category) => selectedIds.contains(category['id'] as String))
      .map((category) => _categoryDisplayName(category, allCategories))
      .toList();
  if (names.length <= 2) return names.join(', ');
  return '${names.take(2).join(', ')} +${names.length - 2}';
}

String _categoryDisplayName(
  Map<String, dynamic> category,
  List<Map<String, dynamic>> categories,
) {
  final name = category['name'] as String? ?? 'Category';
  final parentId = category['parent_id'] as String?;
  if (parentId == null) return name;
  for (final parent in categories) {
    if (parent['id'] == parentId) {
      return '${parent['name'] as String? ?? 'Category'} - $name';
    }
  }
  return name;
}

const _chartColors = [
  Color(0xFF0F766E),
  Color(0xFF2563EB),
  Color(0xFFF59E0B),
  Color(0xFFDC2626),
  Color(0xFF7C3AED),
  Color(0xFF0891B2),
  Color(0xFF16A34A),
  Color(0xFFDB2777),
];

String _chartLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.length <= 9) return trimmed;
  return '${trimmed.substring(0, 8)}…';
}

Color _textOnColor(Color color) {
  return color.computeLuminance() > 0.45 ? Colors.black87 : Colors.white;
}
