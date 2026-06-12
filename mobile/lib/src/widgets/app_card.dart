import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Minimal elevated surface: a hairline-bordered, lightly rounded container
/// with consistent padding. Replaces ad-hoc [Card] + [ListTile] combos so
/// every page shares one surface treatment.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.onLongPress,
    this.accentColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Optional left accent stripe used to tag a card by category/type.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: BorderSide(color: AppColors.border(context)),
    );
    Widget content = Padding(padding: padding, child: child);
    if (accentColor != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 3, color: accentColor),
          Expanded(child: content),
        ],
      );
    }
    return Material(
      color: AppColors.surface(context),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null && onLongPress == null
          ? content
          : InkWell(onTap: onTap, onLongPress: onLongPress, child: content),
    );
  }
}
