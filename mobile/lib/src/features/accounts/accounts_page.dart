import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());
    final accounts = snapshot.accounts;

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: accounts.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                EmptyPanel(
                  icon: Icons.account_balance_outlined,
                  title: 'No accounts cached',
                  body: 'Sync from the API to bring your accounts into SQLite.',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: accounts.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => _showTransferSheet(context, ref),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Transfer'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showCreateAccountSheet(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Account'),
                        ),
                      ),
                    ],
                  );
                }
                final account = accounts[index - 1];
                final balance = asDouble(account['balance']);
                final currency = (account['currency'] ?? snapshot.session?.currency ?? 'BDT') as String;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE0F2FE),
                      foregroundColor: const Color(0xFF0369A1),
                      child: Icon(_accountIcon(account['type'] as String?)),
                    ),
                    title: Text(
                      account['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text((account['type'] as String).replaceAll('_', ' ').toUpperCase()),
                    trailing: Text(
                      money(balance, currency: currency),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onTap: () => _showEditAccountSheet(context, ref, account),
                    onLongPress: () => _archiveAccount(context, ref, account),
                  ),
                );
              },
            ),
    );
  }

  IconData _accountIcon(String? type) {
    final value = (type ?? '').toLowerCase();
    if (value.contains('card')) return Icons.credit_card;
    if (value.contains('bank')) return Icons.account_balance;
    if (value.contains('mobile')) return Icons.phone_android;
    return Icons.wallet;
  }

  Future<void> _archiveAccount(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> account,
  ) async {
    final name = account['name'] as String? ?? 'Account';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive account?'),
        content: Text('$name will be removed from active account lists.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .archiveAccount(account['id'] as String);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _showEditAccountSheet(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> account,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditAccountSheet(account: account),
    );
  }

  void _showCreateAccountSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateAccountSheet(),
    );
  }

  void _showTransferSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _TransferSheet(),
    );
  }
}

class _CreateAccountSheet extends ConsumerStatefulWidget {
  const _CreateAccountSheet();

  @override
  ConsumerState<_CreateAccountSheet> createState() => _CreateAccountSheetState();
}

class _CreateAccountSheetState extends ConsumerState<_CreateAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _openingBalance = TextEditingController(text: '0');
  final _color = TextEditingController();
  final _icon = TextEditingController();
  final _notes = TextEditingController();
  String _typeChoice = 'cash';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _openingBalance.dispose();
    _color.dispose();
    _icon.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        ref.watch(appControllerProvider).asData?.value.session?.currency ?? 'BDT';
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
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'New account',
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
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Enter account name' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _typeChoice,
                decoration: const InputDecoration(
                  labelText: 'Account type',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  DropdownMenuItem(value: 'credit_card', child: Text('Credit Card')),
                  DropdownMenuItem(value: 'bank:savings', child: Text('Savings')),
                  DropdownMenuItem(value: 'bank:investment', child: Text('Investment')),
                  DropdownMenuItem(value: 'credit_card:loan', child: Text('Loan')),
                  DropdownMenuItem(value: 'cash:other', child: Text('Other')),
                ],
                onChanged: (value) =>
                    setState(() => _typeChoice = value ?? _typeChoice),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _openingBalance,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Opening balance',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) =>
                    double.tryParse(value ?? '') == null ? 'Enter a valid amount' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _color,
                      decoration: const InputDecoration(labelText: 'Color'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _icon,
                      decoration: const InputDecoration(labelText: 'Icon'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : () => _save(currency),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(String currency) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    await ref.read(appControllerProvider.notifier).createAccount(
          name: _name.text.trim(),
          type: _backendType,
          openingBalance: double.parse(_openingBalance.text),
          currency: currency,
          color: _color.text,
          icon: _icon.text,
          notes: _notes.text,
          accountSubtype: _accountSubtype,
        );
    if (mounted) Navigator.of(context).pop();
  }

  String get _backendType => _typeChoice.split(':').first;

  String? get _accountSubtype {
    final parts = _typeChoice.split(':');
    return parts.length > 1 ? parts.last : null;
  }
}

class _EditAccountSheet extends ConsumerStatefulWidget {
  const _EditAccountSheet({required this.account});

  final Map<String, dynamic> account;

  @override
  ConsumerState<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends ConsumerState<_EditAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _openingBalance;
  late final TextEditingController _color;
  late final TextEditingController _icon;
  late String _type;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.account['name'] as String? ?? '');
    _openingBalance =
        TextEditingController(text: asDouble(widget.account['opening_balance']).toStringAsFixed(2));
    _color = TextEditingController(text: widget.account['color'] as String? ?? '');
    _icon = TextEditingController(text: widget.account['icon'] as String? ?? '');
    _type = widget.account['type'] as String? ?? 'cash';
  }

  @override
  void dispose() {
    _name.dispose();
    _openingBalance.dispose();
    _color.dispose();
    _icon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  'Edit account',
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
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Account name',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Enter account name' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Account type',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'bank', child: Text('Bank')),
                DropdownMenuItem(value: 'mobile_banking', child: Text('Mobile banking')),
                DropdownMenuItem(value: 'debit_card', child: Text('Debit card')),
                DropdownMenuItem(value: 'credit_card', child: Text('Credit card')),
              ],
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _openingBalance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Opening balance',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) =>
                  double.tryParse(value ?? '') == null ? 'Enter a valid amount' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _color,
                    decoration: const InputDecoration(labelText: 'Color'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _icon,
                    decoration: const InputDecoration(labelText: 'Icon'),
                  ),
                ),
              ],
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
              label: const Text('Save account'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    await ref.read(appControllerProvider.notifier).updateAccount(
          id: widget.account['id'] as String,
          name: _name.text.trim(),
          type: _type,
          openingBalance: double.parse(_openingBalance.text),
          currency: widget.account['currency'] as String? ?? 'BDT',
          color: _color.text,
          icon: _icon.text,
        );
    if (mounted) Navigator.of(context).pop();
  }
}

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet();

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _fromAccountId;
  String? _toAccountId;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(appControllerProvider).asData?.value.accounts ?? [];
    _fromAccountId ??= accounts.isNotEmpty ? accounts.first['id'] as String : null;
    _toAccountId ??= accounts.length > 1 ? accounts[1]['id'] as String : null;

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
                  'Transfer',
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
            _AccountDropdown(
              label: 'From',
              value: _fromAccountId,
              accounts: accounts,
              onChanged: (value) => setState(() => _fromAccountId = value),
            ),
            const SizedBox(height: 12),
            _AccountDropdown(
              label: 'To',
              value: _toAccountId,
              accounts: accounts,
              onChanged: (value) => setState(() => _toAccountId = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                if (amount == null || amount <= 0) return 'Enter a valid amount';
                if (_fromAccountId == _toAccountId) return 'Choose two different accounts';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
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
                  : const Icon(Icons.swap_horiz),
              label: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(appControllerProvider.notifier).createTransfer(
            fromAccountId: _fromAccountId!,
            toAccountId: _toAccountId!,
            amount: double.parse(_amount.text),
            date: DateTime.now(),
            notes: _note.text,
            isCardPayment: _isCreditCard(_toAccountId),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
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
}

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.label,
    required this.value,
    required this.accounts,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<Map<String, dynamic>> accounts;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
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
      onChanged: onChanged,
      validator: (value) => value == null ? 'Choose an account' : null,
    );
  }
}
