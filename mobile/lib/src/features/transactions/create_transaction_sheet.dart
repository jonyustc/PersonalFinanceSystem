import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';

void showCreateTransactionSheet(
  BuildContext context, {
  Map<String, dynamic>? initial,
  String initialType = 'expense',
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CreateTransactionSheet(
      initial: initial,
      initialType: initialType,
    ),
  );
}

class CreateTransactionSheet extends ConsumerStatefulWidget {
  const CreateTransactionSheet({
    super.key,
    this.initial,
    this.initialType = 'expense',
  });

  final Map<String, dynamic>? initial;
  final String initialType;

  @override
  ConsumerState<CreateTransactionSheet> createState() =>
      _CreateTransactionSheetState();
}

class _CreateTransactionSheetState extends ConsumerState<CreateTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _merchant = TextEditingController();
  final _description = TextEditingController();

  String _type = 'expense';
  String? _accountId;
  String? _transferAccountId;
  String? _parentCategoryId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _busy = false;
  bool _initialized = false;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final accounts = snapshot?.accounts ?? [];
    final categories = (snapshot?.categories ?? [])
        .where((row) => row['type'] == _type)
        .toList();
    final parentCategories =
        categories.where((row) => row['parent_id'] == null).toList();
    final recentAccounts = accounts.take(4).toList();
    final recentCategories = parentCategories.take(4).toList();
    final subcategories = _parentCategoryId == null
        ? <Map<String, dynamic>>[]
        : categories
            .where((row) => row['parent_id'] == _parentCategoryId)
            .toList();

    _initialize(accounts, categories);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.initial == null ? 'New transaction' : 'Edit transaction',
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
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'expense',
                    label: Text('Expense'),
                    icon: Icon(Icons.north_east),
                  ),
                  ButtonSegment(
                    value: 'income',
                    label: Text('Income'),
                    icon: Icon(Icons.south_west),
                  ),
                  ButtonSegment(
                    value: 'transfer',
                    label: Text('Transfer'),
                    icon: Icon(Icons.swap_horiz),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (value) {
                  setState(() {
                    _type = value.first;
                    _parentCategoryId = null;
                    _categoryId = null;
                  });
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) {
                  final amount = double.tryParse(value ?? '');
                  return amount == null || amount <= 0
                      ? 'Enter a valid amount'
                      : null;
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [100, 500, 1000, 5000]
                    .map(
                      (amount) => ActionChip(
                        label: Text('$amount'),
                        onPressed: () =>
                            setState(() => _amount.text = '$amount'),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                decoration: InputDecoration(
                  labelText: _type == 'transfer' ? 'Source account' : 'Account',
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                ),
                items: accounts
                    .map(
                      (row) => DropdownMenuItem<String>(
                        value: row['id'] as String,
                        child: Text(row['name'] as String),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _accountId = value),
                validator: (value) =>
                    value == null ? 'Sync or create an account first' : null,
              ),
              if (recentAccounts.length > 1) ...[
                const SizedBox(height: 8),
                _QuickSelectRow(
                  rows: recentAccounts,
                  selectedId: _accountId,
                  onSelected: (value) => setState(() => _accountId = value),
                ),
              ],
              if (_type == 'transfer')
                _TransferFields(
                  accounts: accounts,
                  value: _transferAccountId,
                  sourceAccountId: _accountId,
                  onChanged: (value) => setState(() => _transferAccountId = value),
                )
              else
                _CategoryFields(
                  parentCategories: parentCategories,
                  recentCategories: recentCategories,
                  subcategories: subcategories,
                  parentCategoryId: _parentCategoryId,
                  categoryId: _categoryId,
                  onParentChanged: (value) => setState(() {
                    _parentCategoryId = value;
                    _categoryId = value;
                  }),
                  onCategoryChanged: (value) => setState(
                    () => _categoryId =
                        value == null || value.isEmpty ? _parentCategoryId : value,
                  ),
                  onCreateParent: () => _createCategory(),
                  onCreateChild: _parentCategoryId == null
                      ? null
                      : () => _createCategory(parentId: _parentCategoryId),
                ),
              if (_type != 'transfer') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _merchant,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Merchant',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(_dateLabel),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_type == 'transfer' ? 'Transfer' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _dateLabel {
    return '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final notifier = ref.read(appControllerProvider.notifier);
    final initial = widget.initial;
    try {
      if (_type == 'transfer') {
        await notifier.createTransfer(
          fromAccountId: _accountId!,
          toAccountId: _transferAccountId!,
          amount: double.parse(_amount.text),
          date: _date,
          notes: _description.text,
          isCardPayment: _isCreditCard(_transferAccountId),
        );
      } else if (initial == null) {
        await notifier.createTransaction(
          accountId: _accountId!,
          type: _type,
          amount: double.parse(_amount.text),
          date: _date,
          categoryId: _categoryId,
          merchantName: _merchant.text,
          description: _description.text,
        );
      } else {
        await notifier.updateTransaction(
          id: initial['id'] as String,
          accountId: _accountId!,
          type: _type,
          amount: double.parse(_amount.text),
          date: _date,
          categoryId: _categoryId,
          merchantName: _merchant.text,
          description: _description.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _initialize(
    List<Map<String, dynamic>> accounts,
    List<Map<String, dynamic>> categories,
  ) {
    if (_initialized) return;
    final initial = widget.initial;
    if (initial == null) {
      _type = widget.initialType;
      _accountId = accounts.isNotEmpty ? accounts.first['id'] as String : null;
      _transferAccountId = accounts.length > 1 ? accounts[1]['id'] as String : null;
      _initialized = true;
      return;
    }

    _type = initial['type'] as String? ?? 'expense';
    _accountId = initial['account_id'] as String?;
    _transferAccountId = initial['transfer_account_id'] as String?;
    _categoryId = initial['category_id'] as String?;
    _parentCategoryId = _categoryId;
    for (final row in categories) {
      if (row['id'] == _categoryId && row['parent_id'] != null) {
        _parentCategoryId = row['parent_id'] as String?;
        break;
      }
    }
    _amount.text = (initial['amount'] ?? '').toString();
    _merchant.text = initial['merchant_name'] as String? ?? '';
    _description.text = initial['description'] as String? ?? '';
    _date = DateTime.tryParse(initial['txn_date'] as String? ?? '') ?? DateTime.now();
    _initialized = true;
  }

  bool _isCreditCard(String? accountId) {
    final accounts = ref.read(appControllerProvider).asData?.value.accounts ?? [];
    for (final account in accounts) {
      if (account['id'] == accountId) {
        final type = account['type'] as String? ?? '';
        return type == 'card' || type == 'credit_card';
      }
    }
    return false;
  }

  Future<void> _createCategory({String? parentId}) async {
    final name = await _promptForName(
      parentId == null ? 'New category' : 'New subcategory',
    );
    if (name == null || name.trim().isEmpty) return;
    final created = await ref.read(appControllerProvider.notifier).createCategory(
          name: name.trim(),
          type: _type == 'income' ? 'income' : 'expense',
          parentId: parentId,
        );
    final id = created['id']?.toString();
    if (id == null) return;
    setState(() {
      if (parentId == null) {
        _parentCategoryId = id;
        _categoryId = id;
      } else {
        _parentCategoryId = parentId;
        _categoryId = id;
      }
    });
  }

  Future<String?> _promptForName(String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _TransferFields extends StatelessWidget {
  const _TransferFields({
    required this.accounts,
    required this.value,
    required this.sourceAccountId,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> accounts;
  final String? value;
  final String? sourceAccountId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: const InputDecoration(
          labelText: 'Destination account',
          prefixIcon: Icon(Icons.move_down_outlined),
        ),
        items: accounts
            .map(
              (row) => DropdownMenuItem<String>(
                value: row['id'] as String,
                child: Text(row['name'] as String),
              ),
            )
            .toList(),
        onChanged: onChanged,
        validator: (value) {
          if (value == null) return 'Choose destination account';
          if (value == sourceAccountId) return 'Choose two different accounts';
          return null;
        },
      ),
    );
  }
}

class _CategoryFields extends StatelessWidget {
  const _CategoryFields({
    required this.parentCategories,
    required this.recentCategories,
    required this.subcategories,
    required this.parentCategoryId,
    required this.categoryId,
    required this.onParentChanged,
    required this.onCategoryChanged,
    required this.onCreateParent,
    this.onCreateChild,
  });

  final List<Map<String, dynamic>> parentCategories;
  final List<Map<String, dynamic>> recentCategories;
  final List<Map<String, dynamic>> subcategories;
  final String? parentCategoryId;
  final String? categoryId;
  final ValueChanged<String?> onParentChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onCreateParent;
  final VoidCallback? onCreateChild;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: parentCategoryId,
          decoration: const InputDecoration(
            labelText: 'Category',
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: parentCategories
              .map(
                (row) => DropdownMenuItem<String>(
                  value: row['id'] as String,
                  child: Text(row['name'] as String),
                ),
              )
              .toList(),
          onChanged: onParentChanged,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onCreateParent,
            icon: const Icon(Icons.add),
            label: const Text('Create New Category'),
          ),
        ),
        if (recentCategories.isNotEmpty) ...[
          const SizedBox(height: 8),
          _QuickSelectRow(
            rows: recentCategories,
            selectedId: parentCategoryId,
            onSelected: onParentChanged,
          ),
        ],
        if (parentCategoryId != null && subcategories.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: subcategories.any((row) => row['id'] == categoryId)
                ? categoryId
                : '',
            decoration: const InputDecoration(
              labelText: 'Subcategory',
              prefixIcon: Icon(Icons.sell_outlined),
            ),
            items: [
              const DropdownMenuItem<String>(
                value: '',
                child: Text('No subcategory'),
              ),
              ...subcategories.map(
                (row) => DropdownMenuItem<String>(
                  value: row['id'] as String,
                  child: Text(row['name'] as String),
                ),
              ),
            ],
            onChanged: onCategoryChanged,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onCreateChild,
              icon: const Icon(Icons.add),
              label: const Text('Create New Subcategory'),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuickSelectRow extends StatelessWidget {
  const _QuickSelectRow({
    required this.rows,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Map<String, dynamic>> rows;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: rows.map((row) {
        final id = row['id'] as String;
        return ChoiceChip(
          selected: selectedId == id,
          label: Text(row['name'] as String? ?? 'Item'),
          onSelected: (_) => onSelected(id),
        );
      }).toList(),
    );
  }
}
