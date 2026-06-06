import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';

class BudgetsPage extends ConsumerStatefulWidget {
  const BudgetsPage({super.key});

  @override
  ConsumerState<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends ConsumerState<BudgetsPage> {
  final _income = TextEditingController();
  final _openingBalance = TextEditingController();
  final _drafts = <String, TextEditingController>{};
  final _budgetIds = <String, String>{};
  final _spentByCategory = <String, double>{};
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _income.dispose();
    _openingBalance.dispose();
    for (final controller in _drafts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currency = snapshot.session?.currency ?? 'BDT';
    final categories =
        snapshot.categories
            .where(
              (row) => row['type'] == 'expense' && row['parent_id'] == null,
            )
            .toList()
          ..sort(
            (a, b) => (a['name'] as String? ?? '').compareTo(
              b['name'] as String? ?? '',
            ),
          );
    _ensureDrafts(categories);

    final totalIncome = _number(_income.text);
    final openingBalance = _number(_openingBalance.text);
    final totalBalance = totalIncome + openingBalance;
    final totalCost = categories.fold<double>(
      0,
      (sum, category) => sum + _number(_drafts[category['id']]?.text),
    );
    final totalSpent = categories.fold<double>(
      0,
      (sum, category) => sum + (_spentByCategory[category['id']] ?? 0),
    );
    final planBalance = totalBalance - totalCost;
    final actualBalance = totalBalance - totalSpent;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          _MonthNavigator(
            label: _monthLabel(_month),
            onPrevious: () => _changeMonth(-1),
            onCurrent: () => _setMonth(DateTime.now()),
            onNext: () => _changeMonth(1),
          ),
          const SizedBox(height: 16),
          _PlanCard(
            monthLabel: _monthLabel(_month),
            income: _income,
            openingBalance: _openingBalance,
            totalBalance: totalBalance,
            totalCost: totalCost,
            planBalance: planBalance,
            actualBalance: actualBalance,
            currency: currency,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Category budgets',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                '${categories.length} categories',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            ...List.generate(
              4,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: _BudgetSkeleton(),
              ),
            )
          else if (categories.isEmpty)
            const EmptyPanel(
              icon: Icons.pie_chart_outline,
              title: 'No expense categories',
              body: 'Create parent expense categories before planning budgets.',
            )
          else
            ...categories.map((category) {
              final id = category['id'] as String;
              final planned = _number(_drafts[id]?.text);
              final spent = _spentByCategory[id] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _CategoryBudgetCard(
                  title: category['name'] as String? ?? 'Category',
                  amount: _drafts[id]!,
                  spent: spent,
                  planned: planned,
                  currency: currency,
                  onChanged: () => setState(() {}),
                ),
              );
            }),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(categories),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save monthly budget'),
          ),
        ],
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    final month = _monthKey(_month);
    try {
      final results = await Future.wait([
        api.getBudgets(month),
        api.getBudgetSummary(month),
        api.getMonthlyIncome(month),
      ]);
      final budgets = (results[0] as List<Map<String, dynamic>>);
      final summary = results[1] as Map<String, dynamic>;
      final income = results[2] as Map<String, dynamic>;

      _budgetIds.clear();
      for (final budget in budgets) {
        final categoryId = budget['category_id']?.toString();
        if (categoryId == null) continue;
        _budgetIds[categoryId] = budget['id'].toString();
        _setDraft(categoryId, asDouble(budget['amount']).toStringAsFixed(0));
      }

      _spentByCategory
        ..clear()
        ..addEntries(
          (summary['categories'] as List? ?? []).whereType<Map>().map(
            (row) =>
                MapEntry(row['category_id'].toString(), asDouble(row['spent'])),
          ),
        );
      _income.text = asDouble(income['amount']).toStringAsFixed(0);
      _openingBalance.text = asDouble(
        income['opening_balance'],
      ).toStringAsFixed(0);
    } catch (_) {
      _loadFallback();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Using cached budget data')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadFallback() {
    final snapshot = ref.read(appControllerProvider).asData?.value;
    final budgets = (snapshot?.budgets ?? [])
        .where(
          (row) => row['month'] == _month.month && row['year'] == _month.year,
        )
        .toList();
    _budgetIds.clear();
    _spentByCategory.clear();
    for (final budget in budgets) {
      final categoryId = budget['category_id']?.toString();
      if (categoryId == null) continue;
      _budgetIds[categoryId] = budget['id'].toString();
      _setDraft(categoryId, asDouble(budget['amount']).toStringAsFixed(0));
      _spentByCategory[categoryId] = asDouble(budget['spent']);
    }
  }

  Future<void> _save(List<Map<String, dynamic>> categories) async {
    setState(() => _saving = true);
    final api = ref.read(apiClientProvider);
    final month = _monthKey(_month);
    try {
      await api.saveMonthlyIncome({
        'month': month,
        'amount': _number(_income.text),
        'opening_balance': _number(_openingBalance.text),
      });

      for (final category in categories) {
        final id = category['id'] as String;
        final amount = _number(_drafts[id]?.text);
        final existingId = _budgetIds[id];
        if (amount > 0) {
          await api.upsertBudget({
            'category_id': id,
            'month': month,
            'amount': amount,
          });
        } else if (existingId != null) {
          await api.deleteBudget(existingId);
        }
      }

      await ref.read(appControllerProvider.notifier).syncNow(silent: true);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Monthly budget saved')));
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _ensureDrafts(List<Map<String, dynamic>> categories) {
    for (final category in categories) {
      final id = category['id'] as String;
      _drafts.putIfAbsent(id, () => TextEditingController());
    }
  }

  void _setDraft(String categoryId, String value) {
    final controller = _drafts.putIfAbsent(
      categoryId,
      () => TextEditingController(),
    );
    controller.text = value == '0' ? '' : value;
  }

  Future<void> _changeMonth(int offset) async {
    final next = DateTime(_month.year, _month.month + offset);
    await _setMonth(next);
  }

  Future<void> _setMonth(DateTime value) async {
    setState(() {
      _month = DateTime(value.year, value.month);
      _loading = true;
      _budgetIds.clear();
      _spentByCategory.clear();
      for (final controller in _drafts.values) {
        controller.clear();
      }
    });
    await _load();
  }
}

class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({
    required this.label,
    required this.onPrevious,
    required this.onCurrent,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onCurrent;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.outlined(
          tooltip: 'Previous month',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onCurrent,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.outlined(
          tooltip: 'Next month',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.monthLabel,
    required this.income,
    required this.openingBalance,
    required this.totalBalance,
    required this.totalCost,
    required this.planBalance,
    required this.actualBalance,
    required this.currency,
    required this.onChanged,
  });

  final String monthLabel;
  final TextEditingController income;
  final TextEditingController openingBalance;
  final double totalBalance;
  final double totalCost;
  final double planBalance;
  final double actualBalance;
  final String currency;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MONTHLY BUDGET PLAN',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Budget $monthLabel',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Plan category cost, then compare with real expense in reports.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _MoneyField(
              label: 'Total income',
              controller: income,
              onChanged: onChanged,
            ),
            const SizedBox(height: 12),
            _MoneyField(
              label: 'Last month balance',
              controller: openingBalance,
              onChanged: onChanged,
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 2.1,
              children: [
                _PlanMetric(
                  label: 'Total balance',
                  value: money(totalBalance, currency: currency),
                ),
                _PlanMetric(
                  label: 'Total cost',
                  value: money(totalCost, currency: currency),
                ),
                _PlanMetric(
                  label: 'Plan balance',
                  value: money(planBalance, currency: currency),
                  danger: planBalance < 0,
                ),
                _PlanMetric(
                  label: 'Actual balance',
                  value: money(actualBalance, currency: currency),
                  danger: actualBalance < 0,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      style: const TextStyle(fontWeight: FontWeight.w800),
      onChanged: (_) => onChanged(),
    );
  }
}

class _PlanMetric extends StatelessWidget {
  const _PlanMetric({
    required this.label,
    required this.value,
    this.danger = false,
  });

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: danger
            ? Colors.red.withValues(alpha: 0.08)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: danger ? Colors.red.shade700 : null,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryBudgetCard extends StatelessWidget {
  const _CategoryBudgetCard({
    required this.title,
    required this.amount,
    required this.spent,
    required this.planned,
    required this.currency,
    required this.onChanged,
  });

  final String title;
  final TextEditingController amount;
  final double spent;
  final double planned;
  final String currency;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final percent = planned <= 0 ? 0.0 : spent / planned * 100;
    final over = planned > 0 && spent > planned;
    final remaining = planned - spent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Spent ${money(spent, currency: currency)} of ${money(planned, currency: currency)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 132,
                  child: TextField(
                    controller: amount,
                    textAlign: TextAlign.right,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 9,
                value: (percent / 100).clamp(0, 1).toDouble(),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                color: over
                    ? Colors.red.shade600
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${percent.toStringAsFixed(0)}% used',
                  style: TextStyle(
                    color: over
                        ? Colors.red.shade700
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    'Remaining ${money(remaining, currency: currency)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: over
                          ? Colors.red.shade700
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: over ? FontWeight.w800 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetSkeleton extends StatelessWidget {
  const _BudgetSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 130,
        child: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

String _monthKey(DateTime value) {
  return '${value.year}-${value.month.toString().padLeft(2, '0')}';
}

String _monthLabel(DateTime value) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${names[value.month - 1]} ${value.year}';
}

double _number(String? value) {
  final normalized = value?.replaceAll(',', '').trim();
  if (normalized == null || normalized.isEmpty) return 0;
  return double.tryParse(normalized) ?? 0;
}
