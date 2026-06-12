import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/metric_grid.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';
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
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          _MonthNavigator(
            label: _monthLabel(_month),
            onPrevious: () => _changeMonth(-1),
            onCurrent: () => _setMonth(DateTime.now()),
            onNext: () => _changeMonth(1),
          ),
          const SizedBox(height: AppSpacing.lg),
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
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            'Category budgets',
            subtitle:
                '${categories.length} categor${categories.length == 1 ? 'y' : 'ies'}',
          ),
          const SizedBox(height: AppSpacing.md),
          if (_loading)
            ...List.generate(
              4,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
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
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
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
          const SizedBox(height: AppSpacing.sm),
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
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: onCurrent,
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BUDGET PLAN · ${monthLabel.toUpperCase()}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: muted,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _MoneyField(
                      label: 'Income',
                      controller: income,
                      onChanged: onChanged,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _MoneyField(
                      label: 'Last month balance',
                      controller: openingBalance,
                      onChanged: onChanged,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        MetricGrid(
          children: [
            StatCard(
              label: 'Total balance',
              amount: totalBalance,
              currency: currency,
            ),
            StatCard(
              label: 'Planned cost',
              amount: totalCost,
              currency: currency,
            ),
            StatCard(
              label: 'Plan balance',
              amount: planBalance,
              currency: currency,
              signed: true,
              amountColor: planBalance < 0
                  ? AppColors.amount(context, positive: false)
                  : null,
            ),
            StatCard(
              label: 'Actual balance',
              amount: actualBalance,
              currency: currency,
              signed: true,
              amountColor: actualBalance < 0
                  ? AppColors.amount(context, positive: false)
                  : null,
            ),
          ],
        ),
      ],
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
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
      ),
      style: const TextStyle(fontWeight: FontWeight.w700),
      onChanged: (_) => onChanged(),
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
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final percent = planned <= 0 ? 0.0 : spent / planned * 100;
    final over = planned > 0 && spent > planned;
    final remaining = planned - spent;
    final barColor = planned <= 0
        ? muted
        : AppColors.utilization(context, percent);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Spent ${money(spent, currency: currency)} of ${money(planned, currency: currency)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 116,
                child: TextField(
                  controller: amount,
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '0',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (percent / 100).clamp(0, 1).toDouble(),
              backgroundColor: AppColors.border(context),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                '${percent.toStringAsFixed(0)}% used',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: over ? barColor : muted,
                  fontWeight: over ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  '${over ? 'Over by' : 'Remaining'} ${money(remaining.abs(), currency: currency)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: over
                        ? AppColors.amount(context, positive: false)
                        : muted,
                    fontWeight: over ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BudgetSkeleton extends StatelessWidget {
  const _BudgetSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: SizedBox(
        height: 96,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
