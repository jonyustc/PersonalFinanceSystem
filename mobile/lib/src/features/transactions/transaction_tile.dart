import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../theme/app_spacing.dart';
import '../../theme/category_visuals.dart';
import '../../widgets/app_card.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.row,
    required this.currency,
    this.category,
    this.onTap,
    this.onDelete,
  });

  final Map<String, dynamic> row;
  final String currency;

  /// The transaction's category (looked up by the parent), used to render a
  /// colorful, recognizable icon. Null for transfers or uncategorized rows.
  final Map<String, dynamic>? category;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = (row['type'] ?? 'expense') as String;
    final isIncome = type == 'income';
    final isTransfer = type == 'transfer';
    final isPending = row['is_pending'] == 1;
    final amount = asDouble(row['amount']);
    final title = (row['merchant_name'] ?? row['description'] ?? type) as String;
    final color = isTransfer
        ? theme.colorScheme.primary
        : AppColors.amount(context, positive: isIncome);
    final sign = isIncome
        ? '+'
        : isTransfer
        ? ''
        : '-';

    // Colorful per-category avatar; fall back to a type glyph when there is no
    // category (transfers, uncategorized income/expense).
    final visual = isTransfer || category == null
        ? null
        : categoryVisual(
            name: category!['name'] as String?,
            color: category!['color'] as String?,
          );
    final avatarColor = visual?.color ?? color;
    final avatarIcon =
        visual?.icon ??
        (isTransfer
            ? Icons.swap_horiz
            : isIncome
            ? Icons.south_west
            : Icons.north_east);
    final categoryName = category?['name'] as String?;
    final subtitle = [
      if (categoryName != null && categoryName.isNotEmpty) categoryName,
      compactDate(row['txn_date'] as String? ?? ''),
    ].join(' · ');

    final tile = AppCard(
      onTap: onTap,
      onLongPress: onDelete,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: avatarColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(avatarIcon, color: avatarColor, size: 21),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (isPending) ...[
                      const SizedBox(width: AppSpacing.sm),
                      _PendingBadge(),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$sign${money(amount, currency: currency)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.amount(context, positive: false),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: tile,
    );
  }
}

class _PendingBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'SYNCING',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.tertiary,
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
