import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../categories/categories_page.dart';

Future<void> showCreateTransactionSheet(
  BuildContext context, {
  Map<String, dynamic>? initial,
  String initialType = 'expense',
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) =>
          TransactionEntryPage(initial: initial, initialType: initialType),
    ),
  );
}

class TransactionEntryPage extends ConsumerStatefulWidget {
  const TransactionEntryPage({
    super.key,
    this.initial,
    this.initialType = 'expense',
  });

  final Map<String, dynamic>? initial;
  final String initialType;

  @override
  ConsumerState<TransactionEntryPage> createState() =>
      _TransactionEntryPageState();
}

class _TransactionEntryPageState extends ConsumerState<TransactionEntryPage> {
  final _note = TextEditingController();
  final _payee = TextEditingController();

  String _type = 'expense';
  String _amountText = '';
  String? _accountId;
  String? _transferAccountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  bool _busy = false;
  bool _initialized = false;
  bool _calculatorOpen = true;
  bool _noteOpen = false;

  @override
  void dispose() {
    _note.dispose();
    _payee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final accounts = snapshot?.accounts ?? [];
    final categories = (snapshot?.categories ?? [])
        .where((row) => row['type'] == _type)
        .toList();
    _initialize(accounts, categories);

    final selectedAccount = _rowById(accounts, _accountId);
    final transferAccount = _rowById(accounts, _transferAccountId);
    final selectedCategory = _rowById(categories, _categoryId);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: _TypeTabs(
          value: _type,
          onChanged: (value) {
            setState(() {
              _type = value;
              _categoryId = null;
            });
          },
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') _clear();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'clear', child: Text('Clear')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _AmountHeader(
                    amountText: _amountText,
                    type: _type,
                    calculatorOpen: _calculatorOpen,
                    onToggleCalculator: () {
                      setState(() => _calculatorOpen = !_calculatorOpen);
                    },
                  ),
                  _DateStrip(
                    date: _date,
                    onPrevious: () => setState(
                      () => _date = _date.subtract(const Duration(days: 1)),
                    ),
                    onNext: () => setState(
                      () => _date = _date.add(const Duration(days: 1)),
                    ),
                    onCalendar: _pickDate,
                  ),
                  if (_type != 'transfer')
                    _EntryRow(
                      label: 'Category:',
                      value: _categoryLabel(selectedCategory, categories),
                      icon: Icons.category_outlined,
                      highlight: selectedCategory != null,
                      onTap: _openCategoryManager,
                    ),
                  _EntryRow(
                    label: _type == 'transfer' ? 'From:' : 'Account:',
                    value:
                        selectedAccount?['name'] as String? ?? 'Select account',
                    icon: Icons.account_balance_wallet_outlined,
                    highlight: selectedAccount != null,
                    onTap: () => _pickAccount(accounts, destination: false),
                  ),
                  if (_type == 'transfer')
                    _EntryRow(
                      label: 'To:',
                      value:
                          transferAccount?['name'] as String? ??
                          'Select destination',
                      icon: Icons.move_down_outlined,
                      highlight: transferAccount != null,
                      onTap: () => _pickAccount(accounts, destination: true),
                    ),
                  _NoteSection(
                    controller: _note,
                    open: _noteOpen,
                    onToggle: () => setState(() => _noteOpen = !_noteOpen),
                    onChanged: () => setState(() {}),
                  ),
                ],
              ),
            ),
            if (_calculatorOpen)
              _Keypad(
                busy: _busy,
                onKey: _handleKey,
                onDelete: _deleteDigit,
                onClear: _clearAmount,
                onOk: _applyAmountAndCloseCalculator,
              )
            else
              _SaveBar(busy: _busy, onSave: _save),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(
    Map<String, dynamic>? selectedCategory,
    List<Map<String, dynamic>> categories,
  ) {
    if (selectedCategory == null) return 'Select category';
    final parentId = selectedCategory['parent_id'] as String?;
    if (parentId == null) {
      return selectedCategory['name'] as String? ?? 'Category';
    }
    final parent = _rowById(categories, parentId);
    final parentName = parent?['name'] as String? ?? 'Category';
    final childName = selectedCategory['name'] as String? ?? 'Subcategory';
    return '$parentName - $childName';
  }

  Future<void> _openCategoryManager() async {
    final picked = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => CategoriesPage(
          initialType: _type,
          selectedCategoryId: _categoryId,
          pickerMode: true,
        ),
      ),
    );
    final snapshot = ref.read(appControllerProvider).asData?.value;
    final categories = (snapshot?.categories ?? [])
        .where((row) => row['type'] == _type)
        .toList();
    if (!mounted) return;
    if (picked != null) {
      final pickedId = picked['id'] as String?;
      setState(() {
        _categoryId = pickedId;
        // Auto-fill the note from the most recent transaction in this category
        // so repeat entries (e.g. "Lunch", "Uber to office") need less typing.
        if (_note.text.trim().isEmpty && pickedId != null) {
          final recentNote = _recentNoteForCategory(pickedId);
          if (recentNote != null) {
            _note.text = recentNote;
            _noteOpen = true;
          }
        }
      });
      unawaited(ref.read(appControllerProvider.notifier).syncNow(silent: true));
      return;
    }
    if (_categoryId != null && _rowById(categories, _categoryId) == null) {
      setState(() => _categoryId = null);
    }
    unawaited(ref.read(appControllerProvider.notifier).syncNow(silent: true));
  }

  Future<void> _pickAccount(
    List<Map<String, dynamic>> accounts, {
    required bool destination,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: accounts.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final account = accounts[index];
            return ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(account['name'] as String? ?? 'Account'),
              subtitle: Text((account['type'] as String? ?? '').toUpperCase()),
              trailing: Text(
                money(
                  asDouble(account['balance']),
                  currency: account['currency'] as String? ?? 'BDT',
                ),
              ),
              onTap: () => Navigator.of(context).pop(account['id'] as String),
            );
          },
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (destination) {
        _transferAccountId = picked;
      } else {
        _accountId = picked;
      }
    });
  }

  void _handleKey(String key) {
    if ('0123456789'.contains(key)) {
      if (_amountText == '0') {
        setState(() => _amountText = key);
      } else {
        setState(() => _amountText += key);
      }
      return;
    }
    if (key == '.' && !_amountText.contains('.')) {
      setState(
        () => _amountText = _amountText.isEmpty ? '0.' : '$_amountText.',
      );
      return;
    }
    if ('+-x/'.contains(key)) {
      if (_amountText.isEmpty) return;
      final last = _amountText[_amountText.length - 1];
      if ('+-x/'.contains(last)) {
        setState(
          () => _amountText =
              '${_amountText.substring(0, _amountText.length - 1)}$key',
        );
      } else {
        setState(() => _amountText += key);
      }
    }
  }

  void _deleteDigit() {
    if (_amountText.isEmpty) return;
    setState(
      () => _amountText = _amountText.substring(0, _amountText.length - 1),
    );
  }

  void _clearAmount() => setState(() => _amountText = '');

  void _clear() {
    setState(() {
      _amountText = '';
      _categoryId = null;
      _note.clear();
      _payee.clear();
    });
  }

  void _applyAmountAndCloseCalculator() {
    final amount = _evaluateAmount(_amountText);
    if (amount == null || amount <= 0) {
      _showError('Enter a valid amount');
      return;
    }
    setState(() {
      _amountText = amount.toString();
      _calculatorOpen = false;
    });
  }

  Future<void> _save() async {
    final amount = _evaluateAmount(_amountText);
    if (amount == null || amount <= 0) {
      _showError('Enter a valid amount');
      return;
    }
    if (_accountId == null) {
      _showError('Select an account');
      return;
    }
    if (_type == 'transfer' &&
        (_transferAccountId == null || _transferAccountId == _accountId)) {
      _showError('Select two different accounts');
      return;
    }

    setState(() => _busy = true);
    final notifier = ref.read(appControllerProvider.notifier);
    final initial = widget.initial;
    try {
      if (_type == 'transfer' && initial == null) {
        await notifier.createTransfer(
          fromAccountId: _accountId!,
          toAccountId: _transferAccountId!,
          amount: amount,
          date: _date,
          notes: _note.text,
          isCardPayment: _isCreditCard(_transferAccountId),
        );
      } else if (initial == null) {
        await notifier.createTransaction(
          accountId: _accountId!,
          type: _type,
          amount: amount,
          date: _date,
          categoryId: _categoryId,
          merchantName: _payee.text,
          description: _note.text,
        );
      } else {
        await notifier.updateTransaction(
          id: initial['id'] as String,
          accountId: _accountId!,
          type: _type,
          amount: amount,
          date: _date,
          categoryId: _type == 'transfer' ? null : _categoryId,
          transferAccountId: _type == 'transfer' ? _transferAccountId : null,
          merchantName: _payee.text,
          description: _note.text,
        );
      }
      HapticFeedback.lightImpact();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showError(error.toString());
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      _transferAccountId = accounts.length > 1
          ? accounts[1]['id'] as String
          : null;
      _categoryId = categories.isNotEmpty
          ? categories.first['id'] as String
          : null;
      _initialized = true;
      return;
    }

    _type = initial['type'] as String? ?? 'expense';
    _accountId = initial['account_id'] as String?;
    _transferAccountId = initial['transfer_account_id'] as String?;
    _categoryId = initial['category_id'] as String?;
    _amountText = (initial['amount'] ?? '').toString();
    _payee.text = initial['merchant_name'] as String? ?? '';
    _note.text = initial['description'] as String? ?? '';
    _noteOpen = _note.text.trim().isNotEmpty;
    _date =
        DateTime.tryParse(initial['txn_date'] as String? ?? '') ??
        DateTime.now();
    _initialized = true;
  }

  double? _evaluateAmount(String input) {
    final tokens = RegExp(r'(\d+(?:\.\d+)?|[+\-x/])')
        .allMatches(input.replaceAll(' ', ''))
        .map((match) => match.group(0)!)
        .toList();
    if (tokens.isEmpty || '+-x/'.contains(tokens.last)) {
      return double.tryParse(input);
    }
    final first = double.tryParse(tokens.first);
    if (first == null) return null;
    var current = first;
    var index = 1;
    while (index < tokens.length - 1) {
      final operator = tokens[index];
      final next = double.tryParse(tokens[index + 1]);
      if (next == null) return null;
      if (operator == '+') current += next;
      if (operator == '-') current -= next;
      if (operator == 'x') current *= next;
      if (operator == '/') {
        if (next == 0) return null;
        current /= next;
      }
      index += 2;
    }
    return double.parse(current.toStringAsFixed(2));
  }

  bool _isCreditCard(String? accountId) {
    final accounts =
        ref.read(appControllerProvider).asData?.value.accounts ?? [];
    for (final account in accounts) {
      if (account['id'] == accountId) {
        final type = account['type'] as String? ?? '';
        return type == 'card' || type == 'credit_card';
      }
    }
    return false;
  }

  /// Most recent non-empty note used for [categoryId], or null if none exists.
  String? _recentNoteForCategory(String categoryId) {
    final transactions =
        ref.read(appControllerProvider).asData?.value.transactions ?? [];
    final matching =
        transactions
            .where((row) => row['category_id'] == categoryId)
            .toList()
          ..sort(
            (a, b) => (b['txn_date'] as String? ?? '').compareTo(
              a['txn_date'] as String? ?? '',
            ),
          );
    for (final row in matching) {
      final note = (row['description'] as String?)?.trim();
      if (note != null && note.isNotEmpty) return note;
    }
    return null;
  }

  Map<String, dynamic>? _rowById(List<Map<String, dynamic>> rows, String? id) {
    if (id == null) return null;
    for (final row in rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }
}

class _TypeTabs extends StatelessWidget {
  const _TypeTabs({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      initialIndex: switch (value) {
        'income' => 1,
        'transfer' => 2,
        _ => 0,
      },
      child: TabBar(
        onTap: (index) => onChanged(['expense', 'income', 'transfer'][index]),
        indicatorColor: scheme.primary,
        indicatorWeight: 3,
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        tabs: const [
          Tab(text: 'EXPENSE'),
          Tab(text: 'INCOME'),
          Tab(text: 'TRANSFER'),
        ],
      ),
    );
  }
}

class _AmountHeader extends StatelessWidget {
  const _AmountHeader({
    required this.amountText,
    required this.type,
    required this.calculatorOpen,
    required this.onToggleCalculator,
  });

  final String amountText;
  final String type;
  final bool calculatorOpen;
  final VoidCallback onToggleCalculator;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amountColor = type == 'transfer'
        ? scheme.primary
        : AppColors.amount(context, positive: type == 'income');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onToggleCalculator,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: calculatorOpen ? scheme.primary : scheme.outlineVariant,
              width: calculatorOpen ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Amount',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Flexible(
                flex: 2,
                child: Text(
                  amountText.isEmpty ? '0' : amountText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: amountColor,
                    fontSize: 40,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteSection extends StatelessWidget {
  const _NoteSection({
    required this.controller,
    required this.open,
    required this.onToggle,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final note = controller.text.trim();
    if (!open) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: OutlinedButton.icon(
          onPressed: onToggle,
          icon: const Icon(Icons.notes_outlined),
          label: Text(note.isEmpty ? 'Add note' : 'Note: $note'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: controller,
        minLines: 1,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Note',
          hintText: 'Add a short memo',
          prefixIcon: const Icon(Icons.notes_outlined),
          suffixIcon: IconButton(
            tooltip: 'Hide note',
            onPressed: onToggle,
            icon: const Icon(Icons.expand_less),
          ),
        ),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.busy, required this.onSave});

  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: busy ? null : onSave,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(busy ? 'Saving' : 'Save transaction'),
        ),
      ),
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onCalendar,
  });

  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onCalendar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: onPrevious,
              color: scheme.primary,
              icon: const Icon(Icons.chevron_left, size: 32),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    dayLabel(date),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} · ${TimeOfDay.fromDateTime(date).format(context)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onCalendar,
              color: scheme.primary,
              icon: const Icon(Icons.calendar_month_outlined),
            ),
            IconButton(
              onPressed: onNext,
              color: scheme.primary,
              icon: const Icon(Icons.chevron_right, size: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          children: [
            SizedBox(
              width: 108,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  color: highlight
                      ? Theme.of(context).colorScheme.primary
                      : null,
                  fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Icon(
              icon,
              color: highlight ? Theme.of(context).colorScheme.primary : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.busy,
    required this.onKey,
    required this.onDelete,
    required this.onClear,
    required this.onOk,
  });

  final bool busy;
  final ValueChanged<String> onKey;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
      height: 320,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _PadButton(
                  label: 'AC',
                  background: scheme.errorContainer,
                  foreground: scheme.onErrorContainer,
                  onTap: onClear,
                ),
                _PadButton(
                  label: 'DEL',
                  icon: Icons.backspace_outlined,
                  background: scheme.surface,
                  foreground: scheme.onSurfaceVariant,
                  onTap: onDelete,
                ),
                _PadButton(
                  label: busy ? '…' : 'OK',
                  background: scheme.primary,
                  foreground: scheme.onPrimary,
                  onTap: busy ? null : onOk,
                ),
              ],
            ),
          ),
          Expanded(child: _numberRow(context, ['7', '8', '9', '/'])),
          Expanded(child: _numberRow(context, ['4', '5', '6', 'x'])),
          Expanded(child: _numberRow(context, ['1', '2', '3', '-'])),
          Expanded(child: _numberRow(context, ['0', '.', '+'])),
        ],
      ),
    );
  }

  Widget _numberRow(BuildContext context, List<String> labels) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: labels.map((label) {
        final operator = '+-x/'.contains(label);
        final flex = label == '0' && labels.length == 3 ? 2 : 1;
        return _PadButton(
          label: label,
          flex: flex,
          background: operator ? scheme.primaryContainer : scheme.surface,
          foreground: operator ? scheme.onPrimaryContainer : scheme.onSurface,
          onTap: () => onKey(label),
        );
      }).toList(),
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
    this.icon,
    this.flex = 1,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;
  final IconData? icon;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: icon != null
                  ? Icon(icon, color: foreground, size: 24)
                  : Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
