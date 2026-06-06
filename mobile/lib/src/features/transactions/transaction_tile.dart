import 'package:flutter/material.dart';

import '../../core/formatters.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.row,
    required this.currency,
    this.onTap,
    this.onDelete,
  });

  final Map<String, dynamic> row;
  final String currency;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final type = (row['type'] ?? 'expense') as String;
    final isIncome = type == 'income';
    final isTransfer = type == 'transfer';
    final isPending = row['is_pending'] == 1;
    final amount = asDouble(row['amount']);
    final title = (row['merchant_name'] ?? row['description'] ?? type) as String;
    final color = isTransfer
        ? Theme.of(context).colorScheme.primary
        : isIncome
            ? const Color(0xFF15803D)
            : const Color(0xFFB91C1C);
    final backgroundColor = isTransfer
        ? Theme.of(context).colorScheme.primaryContainer
        : isIncome
            ? const Color(0xFFDCFCE7)
            : const Color(0xFFFEE2E2);
    final sign = isIncome
        ? '+'
        : isTransfer
            ? ''
            : '-';

    final tile = Card(
      child: ListTile(
        onTap: onTap,
        onLongPress: onDelete,
        leading: CircleAvatar(
          backgroundColor: backgroundColor,
          foregroundColor: color,
          child: Icon(
            isTransfer
                ? Icons.swap_horiz
                : isIncome
                    ? Icons.arrow_downward
                    : Icons.arrow_upward,
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            compactDate(row['txn_date'] as String? ?? ''),
            type.toUpperCase(),
            if (isPending) 'PENDING SYNC',
          ].join(' - '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                '$sign${money(amount, currency: currency)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w800, color: color),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
    if (onDelete == null) return tile;
    return Dismissible(
      key: ValueKey(row['id']),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete?.call();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade600,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: tile,
    );
  }
}
