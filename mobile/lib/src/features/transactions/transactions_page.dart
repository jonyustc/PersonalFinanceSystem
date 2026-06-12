import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/metric_grid.dart';
import '../../widgets/stat_card.dart';
import '../dashboard/dashboard_page.dart';
import 'transaction_details_page.dart';
import 'transaction_tile.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _searchController = TextEditingController();
  String _type = 'all';
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final currency = snapshot.session?.currency ?? 'BDT';
    final transactions = snapshot.transactions.where(_matchesFilters).toList()
      ..sort((a, b) {
        final left = DateTime.tryParse(a['txn_date'] as String? ?? '');
        final right = DateTime.tryParse(b['txn_date'] as String? ?? '');
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
    final sections = _groupByDate(transactions);
    double income = 0;
    double expense = 0;
    for (final row in transactions) {
      final amount = asDouble(row['amount']);
      switch (row['type']) {
        case 'income':
          income += amount;
        case 'expense':
          expense += amount;
      }
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          96,
        ),
        children: [
          MetricGrid(
            children: [
              StatCard(
                label: 'Income',
                amount: income,
                currency: currency,
                icon: Icons.south_west,
                amountColor: AppColors.amount(context, positive: true),
              ),
              StatCard(
                label: 'Expense',
                amount: expense,
                currency: currency,
                icon: Icons.north_east,
                amountColor: AppColors.amount(context, positive: false),
              ),
              StatCard(
                label: 'Net',
                amount: income - expense,
                currency: currency,
                icon: Icons.swap_vert,
                signed: true,
                amountColor: AppColors.amount(
                  context,
                  positive: income - expense >= 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _SearchAndFilters(
            controller: _searchController,
            query: _query,
            type: _type,
            resultCount: transactions.length,
            totalCount: snapshot.transactions.length,
            onQueryChanged: (value) => setState(() => _query = value),
            onTypeChanged: (value) => setState(() => _type = value),
            onClear: _hasFilters
                ? () => setState(() {
                      _query = '';
                      _type = 'all';
                      _searchController.clear();
                    })
                : null,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (transactions.isEmpty)
            const EmptyPanel(
              icon: Icons.receipt_long_outlined,
              title: 'No matching transactions',
              body: 'Pull to sync, add a transaction, or clear filters.',
            )
          else
            ...sections.map(
              (section) => _TransactionSection(
                title: section.title,
                rows: section.rows,
                currency: currency,
                onOpen: _openDetails,
                onDelete: _confirmDelete,
              ),
            ),
        ],
      ),
    );
  }

  bool get _hasFilters => _query.trim().isNotEmpty || _type != 'all';

  bool _matchesFilters(Map<String, dynamic> row) {
    final type = row['type'] as String? ?? 'expense';
    final typeMatch = _type == 'all' || type == _type;
    final haystack = [
      row['merchant_name'],
      row['description'],
      row['type'],
      row['transaction_status'],
    ].whereType<String>().join(' ').toLowerCase();
    final query = _query.trim().toLowerCase();
    return typeMatch && (query.isEmpty || haystack.contains(query));
  }

  List<_TransactionDateSection> _groupByDate(
    List<Map<String, dynamic>> transactions,
  ) {
    final sections = <_TransactionDateSection>[];
    String? currentTitle;
    for (final row in transactions) {
      final title = compactDate(row['txn_date'] as String? ?? '');
      if (title != currentTitle) {
        currentTitle = title;
        sections.add(_TransactionDateSection(title: title, rows: []));
      }
      sections.last.rows.add(row);
    }
    return sections;
  }

  void _openDetails(Map<String, dynamic> row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TransactionDetailsPage(
          transactionId: row['id'] as String,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final title =
        (row['merchant_name'] ?? row['description'] ?? 'transaction') as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text('Delete $title and refresh balances?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(appControllerProvider.notifier)
        .deleteTransaction(row['id'] as String);
  }
}

class _SearchAndFilters extends StatelessWidget {
  const _SearchAndFilters({
    required this.controller,
    required this.query,
    required this.type,
    required this.resultCount,
    required this.totalCount,
    required this.onQueryChanged,
    required this.onTypeChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String query;
  final String type;
  final int resultCount;
  final int totalCount;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            SearchBar(
              controller: controller,
              hintText: 'Search transactions',
              elevation: const WidgetStatePropertyAll(0),
              leading: const Icon(Icons.search),
              trailing: query.trim().isEmpty
                  ? null
                  : [
                      IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          controller.clear();
                          onQueryChanged('');
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
              onChanged: onQueryChanged,
            ),
            const SizedBox(height: AppSpacing.md),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _TypeChip(
                    label: 'All',
                    icon: Icons.list_alt,
                    selected: type == 'all',
                    onSelected: () => onTypeChanged('all'),
                  ),
                  _TypeChip(
                    label: 'Expense',
                    icon: Icons.arrow_upward,
                    selected: type == 'expense',
                    onSelected: () => onTypeChanged('expense'),
                  ),
                  _TypeChip(
                    label: 'Income',
                    icon: Icons.arrow_downward,
                    selected: type == 'income',
                    onSelected: () => onTypeChanged('income'),
                  ),
                  _TypeChip(
                    label: 'Transfer',
                    icon: Icons.swap_horiz,
                    selected: type == 'transfer',
                    onSelected: () => onTypeChanged('transfer'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$resultCount of $totalCount transactions',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (onClear != null)
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.filter_alt_off, size: 18),
                    label: const Text('Clear'),
                  ),
              ],
            ),
          ],
        ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        avatar: Icon(icon, size: 18),
        label: Text(label),
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _TransactionSection extends StatelessWidget {
  const _TransactionSection({
    required this.title,
    required this.rows,
    required this.currency,
    required this.onOpen,
    required this.onDelete,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final String currency;
  final ValueChanged<Map<String, dynamic>> onOpen;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    double dayExpense = 0;
    double dayIncome = 0;
    for (final row in rows) {
      final amount = asDouble(row['amount']);
      switch (row['type']) {
        case 'income':
          dayIncome += amount;
        case 'expense':
          dayExpense += amount;
      }
    }
    final parts = <String>[
      if (dayExpense > 0) '-${money(dayExpense, currency: currency)}',
      if (dayIncome > 0) '+${money(dayIncome, currency: currency)}',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.xs,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (parts.isNotEmpty)
                  Text(
                    parts.join('  '),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: TransactionTile(
                row: row,
                currency: currency,
                onTap: () => onOpen(row),
                onDelete: () => onDelete(row),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionDateSection {
  _TransactionDateSection({required this.title, required this.rows});

  final String title;
  final List<Map<String, dynamic>> rows;
}
