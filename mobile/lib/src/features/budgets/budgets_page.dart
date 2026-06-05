import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';

class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final now = DateTime.now();
    final budgets = snapshot.budgets
        .where((row) => row['month'] == now.month && row['year'] == now.year)
        .toList();
    final categories = {
      for (final row in snapshot.categories) row['id'] as String: row,
    };
    final currency = snapshot.session?.currency ?? 'BDT';
    final totalBudget =
        budgets.fold<double>(0, (sum, row) => sum + asDouble(row['amount']));
    final totalSpent =
        budgets.fold<double>(0, (sum, row) => sum + asDouble(row['spent']));
    final progress = totalBudget <= 0 ? 0.0 : (totalSpent / totalBudget);

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(
            title: Text('Budgets'),
            pinned: true,
            automaticallyImplyLeading: false,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'This month',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 12,
                            value: progress.clamp(0, 1),
                            backgroundColor: const Color(0xFFE2E8F0),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _BudgetMetric(
                                label: 'Budget',
                                value: money(totalBudget, currency: currency),
                              ),
                            ),
                            Expanded(
                              child: _BudgetMetric(
                                label: 'Spent',
                                value: money(totalSpent, currency: currency),
                                danger: totalSpent > totalBudget && totalBudget > 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _showBudgetSheet(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Add budget'),
                ),
                const SizedBox(height: 16),
                if (budgets.isEmpty)
                  const EmptyPanel(
                    icon: Icons.pie_chart_outline,
                    title: 'No budgets cached',
                    body: 'Sync from the web app to review monthly budget limits here.',
                  )
                else
                  ...budgets.map((row) {
                    final amount = asDouble(row['amount']);
                    final spent = asDouble(row['spent']);
                    final rowProgress = amount <= 0 ? 0.0 : spent / amount;
                    final category = categories[row['category_id']];
                    final over = rowProgress > 1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: InkWell(
                          onTap: () => _showBudgetSheet(context, ref, row: row),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: over
                                        ? const Color(0xFFFEE2E2)
                                        : const Color(0xFFE0F2FE),
                                    foregroundColor: over
                                        ? const Color(0xFFB91C1C)
                                        : const Color(0xFF0369A1),
                                    child: Icon(over
                                        ? Icons.warning_amber
                                        : Icons.category_outlined),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      category?['name'] as String? ?? 'Category',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${(rowProgress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: over ? Colors.red.shade700 : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  minHeight: 9,
                                  value: rowProgress.clamp(0, 1),
                                  backgroundColor: const Color(0xFFE2E8F0),
                                  color: over
                                      ? Colors.red.shade600
                                      : Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${money(spent, currency: currency)} of ${money(amount, currency: currency)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showBudgetSheet(
    BuildContext context,
    WidgetRef ref, {
    Map<String, dynamic>? row,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BudgetSheet(initial: row),
    );
  }
}

class _BudgetMetric extends StatelessWidget {
  const _BudgetMetric({
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
                color: danger ? Colors.red.shade700 : null,
              ),
        ),
      ],
    );
  }
}

class _BudgetSheet extends ConsumerStatefulWidget {
  const _BudgetSheet({this.initial});

  final Map<String, dynamic>? initial;

  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  String? _categoryId;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _amount.text = asDouble(initial['amount']).toStringAsFixed(2);
      _categoryId = initial['category_id'] as String?;
      _month = DateTime(
        initial['year'] as int? ?? DateTime.now().year,
        initial['month'] as int? ?? DateTime.now().month,
      );
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(appControllerProvider).asData?.value.categories ?? [])
        .where((row) => row['type'] == 'expense')
        .toList();
    _categoryId ??= categories.isNotEmpty ? categories.first['id'] as String : null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.initial == null ? 'Add budget' : 'Edit budget',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: categories
                  .map(
                    (row) => DropdownMenuItem<String>(
                      value: row['id'] as String,
                      child: Text(row['name'] as String),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _categoryId = value),
              validator: (value) => value == null ? 'Choose a category' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Budget amount',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                return amount == null || amount <= 0 ? 'Enter a valid amount' : null;
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickMonth,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(_monthKey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Save budget'),
            ),
          ],
        ),
      ),
    );
  }

  String get _monthKey =>
      '${_month.year}-${_month.month.toString().padLeft(2, '0')}';

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final initial = widget.initial;
    final amount = double.parse(_amount.text);
    if (initial == null) {
      await ref.read(appControllerProvider.notifier).upsertBudget(
            categoryId: _categoryId!,
            month: _monthKey,
            amount: amount,
          );
    } else {
      await ref.read(appControllerProvider.notifier).updateBudget(
            id: initial['id'] as String,
            amount: amount,
          );
    }
    if (mounted) Navigator.of(context).pop();
  }
}
