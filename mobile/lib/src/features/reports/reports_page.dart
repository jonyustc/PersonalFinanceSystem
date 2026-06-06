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
  final Set<String> _mainCategoryFilterIds = {};
  String? _parentId;
  String? _leafCategoryId;
  int _selectedIndex = 0;
  String _reportMode = 'expenses';
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
      return const Center(child: CircularProgressIndicator());
    }

    final mainCategories = _mainExpenseCategories(snapshot.categories);
    final currency = snapshot.session?.currency ?? 'BDT';
    final rows = _buildRows(
      categories: snapshot.categories,
      transactions: snapshot.transactions,
      parentId: _parentId,
      mainCategoryFilterIds: _mainCategoryFilterIds,
    );
    final transactions = _leafCategoryId == null
        ? <Map<String, dynamic>>[]
        : _transactionsForCategory(snapshot.transactions, _leafCategoryId!);
    final total = rows.fold<double>(0, (sum, row) => sum + row.amount);
    final selected = rows.isEmpty
        ? null
        : rows[_selectedIndex.clamp(0, rows.length - 1).toInt()];
    final title = _leafCategoryId == null
        ? (_parentId == null
              ? 'Expense categories'
              : _categoryName(snapshot.categories, _parentId!) ??
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
            _ReportModeSwitch(
              value: _reportMode,
              onChanged: _setReportMode,
            ),
            const SizedBox(height: 14),
            if (_reportMode == 'expenses') ...[
              _ReportHeader(
                title: title,
                start: _start,
                end: _end,
                mainCategories: mainCategories,
                selectedMainCategoryIds: _mainCategoryFilterIds,
                canGoBack: canGoBack,
                onBack: _back,
                onMainCategoriesChanged: _setMainCategoryFilters,
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
                    onSelected: (index) =>
                        setState(() => _selectedIndex = index),
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

  void _setMainCategoryFilters(Set<String> categoryIds) {
    setState(() {
      _mainCategoryFilterIds
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
    required Set<String> mainCategoryFilterIds,
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
      final mainCategoryId = categoryParentId ?? rawCategoryId;
      if (mainCategoryFilterIds.isNotEmpty &&
          !mainCategoryFilterIds.contains(mainCategoryId)) {
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

class _ReportModeSwitch extends StatelessWidget {
  const _ReportModeSwitch({
    required this.value,
    required this.onChanged,
  });

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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.credit_card_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Card spent and payments',
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

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.title,
    required this.start,
    required this.end,
    required this.mainCategories,
    required this.selectedMainCategoryIds,
    required this.canGoBack,
    required this.onBack,
    required this.onMainCategoriesChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onPickRange,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final List<Map<String, dynamic>> mainCategories;
  final Set<String> selectedMainCategoryIds;
  final bool canGoBack;
  final VoidCallback onBack;
  final ValueChanged<Set<String>> onMainCategoriesChanged;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = _categoryFilterLabel(
      mainCategories,
      selectedMainCategoryIds,
    );
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
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showMainCategoryPicker(context),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Main categories',
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
            if (selectedMainCategoryIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: mainCategories
                    .where(
                      (category) => selectedMainCategoryIds.contains(
                        category['id'] as String,
                      ),
                    )
                    .map(
                      (category) => InputChip(
                        label: Text(category['name'] as String? ?? 'Category'),
                        onDeleted: () {
                          final next = Set<String>.from(
                            selectedMainCategoryIds,
                          )..remove(category['id'] as String);
                          onMainCategoriesChanged(next);
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
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

  Future<void> _showMainCategoryPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _MainCategoryPickerSheet(
        categories: mainCategories,
        selectedIds: selectedMainCategoryIds,
      ),
    );
    if (picked == null) return;
    onMainCategoriesChanged(picked);
  }
}

class _CardReportSection extends StatelessWidget {
  const _CardReportSection({
    required this.future,
    required this.currency,
  });

  final Future<Map<String, dynamic>> future;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Card report unavailable. Pull to sync or try again.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.credit_card_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Cards',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _CardReportMetric(
                        label: 'Spent',
                        value: money(
                          asDouble(report['total_spent']),
                          currency: currency,
                        ),
                        color: const Color(0xFFB91C1C),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CardReportMetric(
                        label: 'Paid',
                        value: money(
                          asDouble(report['total_paid']),
                          currency: currency,
                        ),
                        color: const Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CardReportMetric(
                  label: 'Outstanding',
                  value: money(
                    asDouble(report['total_outstanding']),
                    currency: currency,
                  ),
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
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
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CardReportCardRow(card: card, currency: currency),
                    ),
                  ),
                const Divider(height: 22),
                _CardHistoryList(
                  title: 'Payment history',
                  emptyText: 'No card payments in this range.',
                  rows: paymentHistory,
                  currency: currency,
                  icon: Icons.payments_outlined,
                  color: const Color(0xFF15803D),
                ),
                const SizedBox(height: 12),
                _CardHistoryList(
                  title: 'Spent history',
                  emptyText: 'No card spending in this range.',
                  rows: spentHistory,
                  currency: currency,
                  icon: Icons.shopping_bag_outlined,
                  color: const Color(0xFFB91C1C),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CardReportMetric extends StatelessWidget {
  const _CardReportMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardReportCardRow extends StatelessWidget {
  const _CardReportCardRow({
    required this.card,
    required this.currency,
  });

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
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
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
                            if ((row['account_name'] as String? ?? '').isNotEmpty)
                              row['account_name'] as String,
                          ].where((value) => value.isNotEmpty).join(' - '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    money(asDouble(row['amount']), currency: currency),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
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
    required this.selectedIds,
  });

  final List<Map<String, dynamic>> categories;
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
              'Main categories',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selectedIds.isEmpty,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('All main categories'),
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
                    title: Text(category['name'] as String? ?? 'Category'),
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

String _categoryFilterLabel(
  List<Map<String, dynamic>> categories,
  Set<String> selectedIds,
) {
  if (selectedIds.isEmpty) return 'All main categories';
  final names = categories
      .where((category) => selectedIds.contains(category['id'] as String))
      .map((category) => category['name'] as String? ?? 'Category')
      .toList();
  if (names.length <= 2) return names.join(', ');
  return '${names.take(2).join(', ')} +${names.length - 2}';
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
