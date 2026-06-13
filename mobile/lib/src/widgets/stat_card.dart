import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_card.dart';
import 'money_text.dart';

/// The core "modern minimal" metric tile: a small muted label, a large
/// number-focused amount, and an optional caption. Used in metric grids and
/// as full-width hero stats.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.amount,
    this.currency = 'BDT',
    this.caption,
    this.icon,
    this.accent,
    this.amountColor,
    this.signed = false,
    this.hero = false,
    this.onTap,
  });

  final String label;
  final double amount;
  final String currency;
  final String? caption;
  final IconData? icon;
  final Color? accent;
  final Color? amountColor;

  /// Prefix positive amounts with `+` (useful for deltas like cash flow).
  final bool signed;

  /// Hero stats use a larger amount style (for a single headline metric).
  final bool hero;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final chipColor = accent ?? theme.colorScheme.primary;
    final amountStyle =
        (hero ? theme.textTheme.headlineMedium : theme.textTheme.titleLarge)
            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: chipColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 20, color: chipColor),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Full-width so the amount can scale to fit the tile instead of
          // being cut off.
          SizedBox(
            width: double.infinity,
            child: MoneyText(
              amount,
              currency: currency,
              color: amountColor,
              signed: signed,
              style: amountStyle,
              autoFit: true,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ],
      ),
    );
  }
}
