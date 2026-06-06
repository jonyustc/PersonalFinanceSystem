import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import 'create_transaction_sheet.dart';

class TransactionDetailsPage extends ConsumerWidget {
  const TransactionDetailsPage({super.key, required this.transactionId});

  final String transactionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final row = _findById(snapshot?.transactions ?? const [], transactionId);
    final currency = snapshot?.session?.currency ?? 'BDT';

    if (snapshot == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (row == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transaction')),
        body: const Center(child: Text('Transaction not found')),
      );
    }

    final type = row['type'] as String? ?? 'expense';
    final isIncome = type == 'income';
    final amount = asDouble(row['amount']);
    final title = (row['merchant_name'] ?? row['description'] ?? type) as String;
    final account = _findById(snapshot.accounts, row['account_id'] as String?);
    final transferAccount = _findById(
      snapshot.accounts,
      row['transfer_account_id'] as String?,
    );
    final category = _findById(snapshot.categories, row['category_id'] as String?);
    final amountColor = type == 'transfer'
        ? Theme.of(context).colorScheme.primary
        : isIncome
            ? const Color(0xFF15803D)
            : const Color(0xFFB91C1C);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction details'),
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () => showCreateTransactionSheet(context, initial: row),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, ref, row),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${isIncome ? '+' : type == 'transfer' ? '' : '-'}${money(amount, currency: currency)}',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: amountColor,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _DetailRow(label: 'Type', value: type.toUpperCase()),
          _DetailRow(
            label: type == 'transfer' ? 'From account' : 'Account',
            value: account?['name'] as String? ?? 'Unknown',
          ),
          if (type == 'transfer')
            _DetailRow(
              label: 'To account',
              value: transferAccount?['name'] as String? ?? 'Unknown',
            ),
          if (type != 'transfer')
            _DetailRow(
              label: 'Category',
              value: category?['name'] as String? ?? 'Uncategorized',
            ),
          _DetailRow(label: 'Date', value: compactDate(row['txn_date'] as String? ?? '')),
          _DetailRow(
            label: 'Status',
            value: row['is_pending'] == 1 ? 'Pending sync' : 'Synced',
          ),
          if ((row['description'] as String? ?? '').trim().isNotEmpty)
            _DetailRow(label: 'Note', value: row['description'] as String),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> row,
  ) async {
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
    if (confirmed != true || !context.mounted) return;
    await ref
        .read(appControllerProvider.notifier)
        .deleteTransaction(row['id'] as String);
    if (context.mounted) Navigator.of(context).pop();
  }

  Map<String, dynamic>? _findById(List<Map<String, dynamic>> rows, String? id) {
    if (id == null) return null;
    for (final row in rows) {
      if (row['id'] == id) return row;
    }
    return null;
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
