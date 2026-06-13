import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/skeleton.dart';
import '../dashboard/dashboard_page.dart';
import 'transaction_details_page.dart';
import 'transaction_tile.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  DateTime _day = DateTime.now();
  String _type = 'all';

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) {
      return const ListSkeleton();
    }

    final currency = snapshot.session?.currency ?? 'BDT';
    final categoryById = {
      for (final c in snapshot.categories) c['id'] as String: c,
    };
    final dayRows =
        snapshot.transactions
            .where((row) => _isSameDay(row, _day))
            .where(_matchesType)
            .toList()
          ..sort((a, b) {
            final left = DateTime.tryParse(a['txn_date'] as String? ?? '');
            final right = DateTime.tryParse(b['txn_date'] as String? ?? '');
            if (left == null && right == null) return 0;
            if (left == null) return 1;
            if (right == null) return -1;
            return right.compareTo(left);
          });

    double income = 0;
    double expense = 0;
    for (final row in dayRows) {
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
          _DayNavigator(
            day: _day,
            income: income,
            expense: expense,
            count: dayRows.length,
            currency: currency,
            onPrevious: () => _changeDay(-1),
            onNext: _isToday(_day) ? null : () => _changeDay(1),
            onPickDate: _pickDate,
            onToday: _isToday(_day) ? null : _goToToday,
          ),
          const SizedBox(height: AppSpacing.md),
          _TypeFilterRow(
            type: _type,
            onChanged: (value) => setState(() => _type = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (dayRows.isEmpty)
            EmptyPanel(
              icon: Icons.receipt_long_outlined,
              title: 'Nothing on ${dayLabel(_day).toLowerCase()}',
              body:
                  'No ${_type == 'all' ? '' : '$_type '}transactions for this '
                  'day. Use the arrows to browse other days or add one with +.',
            )
          else
            ...dayRows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: TransactionTile(
                  row: row,
                  currency: currency,
                  category: categoryById[row['category_id']],
                  onTap: () => _openDetails(row),
                  onDelete: () => _confirmDelete(row),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isToday(DateTime day) => _isSameDayDate(day, DateTime.now());

  bool _isSameDay(Map<String, dynamic> row, DateTime day) {
    final date = DateTime.tryParse(row['txn_date'] as String? ?? '');
    if (date == null) return false;
    return _isSameDayDate(date.toLocal(), day);
  }

  bool _isSameDayDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _matchesType(Map<String, dynamic> row) {
    if (_type == 'all') return true;
    return (row['type'] as String? ?? 'expense') == _type;
  }

  void _changeDay(int deltaDays) {
    setState(() => _day = _day.add(Duration(days: deltaDays)));
  }

  void _goToToday() => setState(() => _day = DateTime.now());

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _day = picked);
  }

  void _openDetails(Map<String, dynamic> row) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TransactionDetailsPage(transactionId: row['id'] as String),
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final title =
        (row['merchant_name'] ?? row['description'] ?? 'transaction') as String;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete transaction?',
      message: 'Delete "$title" and refresh balances? This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (!confirmed) return;
    await ref
        .read(appControllerProvider.notifier)
        .deleteTransaction(row['id'] as String);
  }
}

/// Day picker header with a per-day income / expense / net summary.
class _DayNavigator extends StatelessWidget {
  const _DayNavigator({
    required this.day,
    required this.income,
    required this.expense,
    required this.count,
    required this.currency,
    required this.onPrevious,
    required this.onNext,
    required this.onPickDate,
    required this.onToday,
  });

  final DateTime day;
  final double income;
  final double expense;
  final int count;
  final String currency;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPickDate;
  final VoidCallback? onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final net = income - expense;
    final fullDate =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Previous day',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: onPickDate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        Text(
                          dayLabel(day),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          fullDate,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Next day',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (onToday != null)
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: onToday,
                icon: const Icon(Icons.today, size: 16),
                label: const Text('Jump to today'),
              ),
            ),
          const Divider(height: AppSpacing.xl),
          Row(
            children: [
              _DayMetric(
                label: 'Income',
                amount: income,
                currency: currency,
                color: AppColors.amount(context, positive: true),
              ),
              _DayMetric(
                label: 'Expense',
                amount: expense,
                currency: currency,
                color: AppColors.amount(context, positive: false),
              ),
              _DayMetric(
                label: 'Net',
                amount: net,
                currency: currency,
                signed: true,
                color: AppColors.amount(context, positive: net >= 0),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            count == 0
                ? 'No transactions'
                : '$count transaction${count == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayMetric extends StatelessWidget {
  const _DayMetric({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
    this.signed = false,
  });

  final String label;
  final double amount;
  final String currency;
  final Color color;
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefix = signed && amount > 0 ? '+' : '';
    return Expanded(
      child: Column(
        children: [
          Text(
            '$prefix${money(amount, currency: currency)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
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

class _TypeFilterRow extends StatelessWidget {
  const _TypeFilterRow({required this.type, required this.onChanged});

  final String type;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _TypeChip(
            label: 'All',
            icon: Icons.list_alt,
            selected: type == 'all',
            onSelected: () => onChanged('all'),
          ),
          _TypeChip(
            label: 'Expense',
            icon: Icons.north_east,
            selected: type == 'expense',
            onSelected: () => onChanged('expense'),
          ),
          _TypeChip(
            label: 'Income',
            icon: Icons.south_west,
            selected: type == 'income',
            onSelected: () => onChanged('income'),
          ),
          _TypeChip(
            label: 'Transfer',
            icon: Icons.swap_horiz,
            selected: type == 'transfer',
            onSelected: () => onChanged('transfer'),
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
