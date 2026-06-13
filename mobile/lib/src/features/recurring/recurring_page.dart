import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../theme/category_visuals.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../dashboard/dashboard_page.dart';

class RecurringPage extends ConsumerStatefulWidget {
  const RecurringPage({super.key});

  @override
  ConsumerState<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends ConsumerState<RecurringPage> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(appControllerProvider.notifier).recurringRules();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final currency = snapshot?.session?.currency ?? 'BDT';
    final categoryById = {
      for (final c in snapshot?.categories ?? const [])
        c['id'] as String: c,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.add),
        label: const Text('New rule'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rules = snap.data ?? const [];
          if (rules.isEmpty) {
            return const EmptyPanel(
              icon: Icons.event_repeat_outlined,
              title: 'No recurring rules',
              body:
                  'Add rent, salary, subscriptions and other repeating entries. '
                  'They are created automatically when due.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              96,
            ),
            itemCount: rules.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _RuleCard(
                rule: rules[index],
                currency: currency,
                category:
                    categoryById[rules[index]['category_id']],
                onEdit: () => _openEditor(rule: rules[index]),
                onDelete: () => _delete(rules[index]),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor({Map<String, dynamic>? rule}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _RecurringEditorPage(rule: rule)),
    );
    if (changed == true) setState(_reload);
  }

  Future<void> _delete(Map<String, dynamic> rule) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete recurring rule?',
      message:
          'Stop auto-creating "${rule['description'] ?? rule['merchant_name'] ?? 'this entry'}"? '
          'Already-created transactions are kept.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (!confirmed) return;
    await ref
        .read(appControllerProvider.notifier)
        .deleteRecurringRule(rule['id'] as String);
    if (mounted) setState(_reload);
  }
}

String _frequencyLabel(String frequency, int interval) {
  final unit = switch (frequency) {
    'daily' => 'day',
    'weekly' => 'week',
    'yearly' => 'year',
    _ => 'month',
  };
  return interval <= 1 ? 'Every $unit' : 'Every $interval ${unit}s';
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.currency,
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> rule;
  final String currency;
  final Map<String, dynamic>? category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = rule['type'] as String? ?? 'expense';
    final amount = asDouble(rule['amount']);
    final title =
        (rule['description'] ?? rule['merchant_name'] ?? type) as String;
    final visual = type == 'transfer'
        ? null
        : categoryVisual(
            name: category?['name'] as String?,
            color: category?['color'] as String?,
          );
    final color = visual?.color ?? theme.colorScheme.primary;
    final nextRun = DateTime.tryParse(rule['next_run'] as String? ?? '');

    return AppCard(
      onTap: onEdit,
      onLongPress: onDelete,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              visual?.icon ?? Icons.event_repeat,
              color: color,
              size: 21,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_frequencyLabel(rule['frequency'] as String? ?? 'monthly', (rule['interval_count'] as int?) ?? 1)}'
                  '${nextRun == null ? '' : ' · next ${dayLabel(nextRun)}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            money(amount, currency: currency),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecurringEditorPage extends ConsumerStatefulWidget {
  const _RecurringEditorPage({this.rule});

  final Map<String, dynamic>? rule;

  @override
  ConsumerState<_RecurringEditorPage> createState() =>
      _RecurringEditorPageState();
}

class _RecurringEditorPageState extends ConsumerState<_RecurringEditorPage> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _interval = TextEditingController(text: '1');

  String _type = 'expense';
  String? _accountId;
  String? _transferAccountId;
  String? _categoryId;
  String _frequency = 'monthly';
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _busy = false;
  bool _initialized = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _interval.dispose();
    super.dispose();
  }

  void _initialize() {
    if (_initialized) return;
    final rule = widget.rule;
    if (rule != null) {
      _type = rule['type'] as String? ?? 'expense';
      _accountId = rule['account_id'] as String?;
      _transferAccountId = rule['transfer_account_id'] as String?;
      _categoryId = rule['category_id'] as String?;
      _amount.text = asDouble(rule['amount']).toString();
      _note.text = rule['description'] as String? ?? '';
      _frequency = rule['frequency'] as String? ?? 'monthly';
      _interval.text = ((rule['interval_count'] as int?) ?? 1).toString();
      _startDate =
          DateTime.tryParse(rule['next_run'] as String? ?? '') ??
          DateTime.now();
      final end = rule['end_date'] as String?;
      _endDate = end == null ? null : DateTime.tryParse(end);
    }
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    _initialize();
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final accounts = snapshot?.accounts ?? const [];
    final categories = (snapshot?.categories ?? const [])
        .where((c) => c['type'] == _type)
        .toList();
    _accountId ??= accounts.isNotEmpty ? accounts.first['id'] as String : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule == null ? 'New recurring' : 'Edit recurring'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'expense', label: Text('Expense')),
              ButtonSegment(value: 'income', label: Text('Income')),
              ButtonSegment(value: 'transfer', label: Text('Transfer')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _AccountDropdown(
            label: _type == 'transfer' ? 'From account' : 'Account',
            accounts: accounts,
            value: _accountId,
            onChanged: (v) => setState(() => _accountId = v),
          ),
          if (_type == 'transfer') ...[
            const SizedBox(height: AppSpacing.md),
            _AccountDropdown(
              label: 'To account',
              accounts: accounts,
              value: _transferAccountId,
              onChanged: (v) => setState(() => _transferAccountId = v),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _categoryId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('None')),
                for (final c in categories)
                  DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text(c['name'] as String? ?? 'Category'),
                  ),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Note / name',
              hintText: 'e.g. Rent, Salary, Netflix',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _frequency,
                  decoration: const InputDecoration(labelText: 'Repeat'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                  ],
                  onChanged: (v) =>
                      setState(() => _frequency = v ?? 'monthly'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Every'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _DateField(
            label: 'Starts',
            value: _startDate,
            onPick: (d) => setState(() => _startDate = d),
          ),
          const SizedBox(height: AppSpacing.md),
          _DateField(
            label: 'Ends (optional)',
            value: _endDate,
            onPick: (d) => setState(() => _endDate = d),
            onClear: () => setState(() => _endDate = null),
          ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: const Text('Save rule'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      _error('Enter a valid amount');
      return;
    }
    if (_accountId == null) {
      _error('Select an account');
      return;
    }
    if (_type == 'transfer' &&
        (_transferAccountId == null || _transferAccountId == _accountId)) {
      _error('Select two different accounts');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(appControllerProvider.notifier).saveRecurringRule(
            id: widget.rule?['id'] as String?,
            type: _type,
            accountId: _accountId!,
            transferAccountId: _type == 'transfer' ? _transferAccountId : null,
            categoryId: _type == 'transfer' ? null : _categoryId,
            amount: amount,
            description: _note.text,
            frequency: _frequency,
            intervalCount: int.tryParse(_interval.text.trim()) ?? 1,
            startDate: _startDate,
            endDate: _endDate,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _error(error.toString());
    }
  }

  void _error(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.label,
    required this.accounts,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<Map<String, dynamic>> accounts;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
      ),
      items: [
        for (final a in accounts)
          DropdownMenuItem(
            value: a['id'] as String,
            child: Text(a['name'] as String? ?? 'Account'),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_outlined),
          suffixIcon: value != null && onClear != null
              ? IconButton(icon: const Icon(Icons.close), onPressed: onClear)
              : null,
        ),
        child: Text(
          value == null
              ? 'Not set'
              : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-${value!.day.toString().padLeft(2, '0')}',
        ),
      ),
    );
  }
}
