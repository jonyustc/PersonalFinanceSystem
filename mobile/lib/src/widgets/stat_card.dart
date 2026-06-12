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
    final amountStyle = (hero ? theme.textTheme.headlineMedium : theme.textTheme.titleLarge)
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (icon != null)
                Icon(
                  icon,
                  size: 18,
                  color: accent ?? theme.colorScheme.primary,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          MoneyText(
            amount,
            currency: currency,
            color: amountColor,
            signed: signed,
            style: amountStyle,
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
