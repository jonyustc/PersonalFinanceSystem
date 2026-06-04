import 'package:flutter/material.dart';

import '../../core/formatters.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.row,
    required this.currency,
  });

  final Map<String, dynamic> row;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final type = (row['type'] ?? 'expense') as String;
    final isIncome = type == 'income';
    final isPending = row['is_pending'] == 1;
    final amount = asDouble(row['amount']);
    final title = (row['merchant_name'] ?? row['description'] ?? type) as String;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isIncome ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
          foregroundColor:
              isIncome ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
          child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${compactDate(row['txn_date'] as String? ?? '')}${isPending ? ' - pending sync' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          '${isIncome ? '+' : '-'}${money(amount, currency: currency)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color:
                isIncome ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
          ),
        ),
      ),
    );
  }
}
