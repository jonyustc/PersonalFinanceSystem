import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  late DateTime _start;
  late DateTime _end;
  String? _mainCategoryFilterId;
  String? _parentId;
  String? _leafCategoryId;
  int _selectedIndex = 0;

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
      return const Center(child: CircularProgressIndicator());
    }

    final mainCategories = _mainExpenseCategories(snapshot.categories);
    final effectiveParentId = _parentId ?? _mainCategoryFilterId;
    final currency = snapshot.session?.currency ?? 'BDT';
    final rows = _buildRows(
      categories: snapshot.categories,
      transactions: snapshot.transactions,
      parentId: effectiveParentId,
    );
    final transactions = _leafCategoryId == null
        ? <Map<String, dynamic>>[]
        : _transactionsForCategory(snapshot.transactions, _leafCategoryId!);
    final total = rows.fold<double>(0, (sum, row) => sum + row.amount);
    final selected = rows.isEmpty
        ? null
        : rows[_selectedIndex.clamp(0, rows.length - 1).toInt()];
    final title = _leafCategoryId == null
        ? (effectiveParentId == null
              ? 'Expense categories'
              : _categoryName(snapshot.categories, effectiveParentId) ??
                    'Subcategories')
        : _categoryName(snapshot.categories, _leafCategoryId!) ??
              'Transactions';

    final canGoBack = _parentId != null || _leafCategoryId != null;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _ReportHeader(
              title: title,
              start: _start,
              end: _end,
              mainCategories: mainCategories,
              selectedMainCategoryId: _mainCategoryFilterId,
              canGoBack: canGoBack,
              onBack: _back,
              onMainCategoryChanged: _setMainCategoryFilter,
              onPrevious: _previousRange,
              onNext: _nextRange,
              onPickRange: _pickRange,
            ),
            const SizedBox(height: 14),
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
                  onSelected: (index) => setState(() => _selectedIndex = index),
                ),
                const SizedBox(height: 16),
                _CategoryBreakdown(
                  rows: rows,
                  total: total,
                  currency: currency,
                  selectedId: selected?.categoryId,
                  onSelected: (row) => _openRow(row, snapshot.categories),
                ),
              ]
            else
              _TransactionList(
                categoryName: title,
                transactions: transactions,
                currency: currency,
              ),
          ],
        ),
      ),
    );
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
    final hasChildren = categories.any(
      (category) => category['parent_id'] == row.categoryId,
    );
    setState(() {
      if (_mainCategoryFilterId == null && _parentId == null && hasChildren) {
        _parentId = row.categoryId;
        _leafCategoryId = null;
      } else if (_parentId != row.categoryId &&
          _mainCategoryFilterId != row.categoryId &&
          hasChildren) {
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

  void _setMainCategoryFilter(String? categoryId) {
    setState(() {
      _mainCategoryFilterId = categoryId;
      _parentId = null;
      _leafCategoryId = null;
      _selectedIndex = 0;
    });
  }

  List<_ReportRow> _buildRows({
    required List<Map<String, dynamic>> categories,
    required List<Map<String, dynamic>> transactions,
    required String? parentId,
  }) {
    final categoryById = {
      for (final row in categories) row['id'] as String: row,
    };
    final totals = <String, double>{};
    final names = <String, String>{};

    for (final transaction in transactions) {
      if (transaction['type'] != 'expense') continue;
      if (!_isInRange(transaction)) continue;
      final rawCategoryId = transaction['category_id'] as String?;
      if (rawCategoryId == null) continue;
      final category = categoryById[rawCategoryId];
      if (category == null) continue;
      final categoryParentId = category['parent_id'] as String?;

      final bucketId = parentId == null
          ? categoryParentId ?? rawCategoryId
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
              transaction['type'] == 'expense' &&
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

  List<Map<String, dynamic>> _mainExpenseCategories(
    List<Map<String, dynamic>> categories,
  ) {
    return categories
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

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.title,
    required this.start,
    required this.end,
    required this.mainCategories,
    required this.selectedMainCategoryId,
    required this.canGoBack,
    required this.onBack,
    required this.onMainCategoryChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onPickRange,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final List<Map<String, dynamic>> mainCategories;
  final String? selectedMainCategoryId;
  final bool canGoBack;
  final VoidCallback onBack;
  final ValueChanged<String?> onMainCategoryChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (canGoBack)
                  IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                  )
                else
                  const Icon(Icons.pie_chart_outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedMainCategoryId ?? '',
              decoration: const InputDecoration(
                labelText: 'Main category',
                prefixIcon: Icon(Icons.filter_list),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('All main categories'),
                ),
                ...mainCategories.map(
                  (category) => DropdownMenuItem<String>(
                    value: category['id'] as String,
                    child: Text(category['name'] as String? ?? 'Category'),
                  ),
                ),
              ],
              onChanged: (value) =>
                  onMainCategoryChanged(value == '' ? null : value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Previous range',
                  onPressed: onPrevious,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onPickRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      '${_date(start)} - ${_date(end)}',
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
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
            const SizedBox(height: 8),
            Text(
              money(-total, currency: currency),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              'Total expense',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({
    required this.rows,
    required this.total,
    required this.currency,
    required this.selectedId,
    required this.onSelected,
  });

  final List<_ReportRow> rows;
  final double total;
  final String currency;
  final String? selectedId;
  final ValueChanged<_ReportRow> onSelected;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows.length,
        separatorBuilder: (_, _) => Divider(
          height: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        itemBuilder: (context, index) {
          final row = rows[index];
          final percent = total <= 0 ? 0 : row.amount / total;
          final selected = row.categoryId == selectedId;
          return ListTile(
            selected: selected,
            leading: CircleAvatar(
              backgroundColor: _chartColors[index % _chartColors.length],
              child: Text(
                '${(percent * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            title: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: LinearProgressIndicator(
              value: percent.clamp(0, 1).toDouble(),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  money(-row.amount, currency: currency),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () => onSelected(row),
          );
        },
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.categoryName,
    required this.transactions,
    required this.currency,
  });

  final String categoryName;
  final List<Map<String, dynamic>> transactions;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final total = transactions.fold<double>(
      0,
      (sum, transaction) => sum + asDouble(transaction['amount']),
    );
    if (transactions.isEmpty) {
      return const EmptyPanel(
        icon: Icons.receipt_long_outlined,
        title: 'No transactions',
        body: 'No expense transactions are available for this category.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(
              categoryName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text('${transactions.length} transactions'),
            trailing: Text(
              money(-total, currency: currency),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...transactions.map(
          (transaction) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TransactionTile(row: transaction, currency: currency),
          ),
        ),
      ],
    );
  }
}

String _date(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
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
