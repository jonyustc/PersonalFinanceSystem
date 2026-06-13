import 'package:flutter/material.dart';

import '../core/formatters.dart';

/// A money amount rendered with tabular figures so columns of numbers stay
/// vertically aligned. Reuses [money] for currency formatting.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.currency = 'BDT',
    this.style,
    this.color,
    this.signed = false,
    this.maxLines = 1,
    this.autoFit = false,
  });

  final num amount;
  final String currency;
  final TextStyle? style;
  final Color? color;

  /// When true, prefixes a `+` for positive values (useful for deltas).
  final bool signed;
  final int maxLines;

  /// When true (default), the amount shrinks to fit its width instead of being
  /// truncated with an ellipsis — so large values like "BDT 3,61,000.00" stay
  /// fully readable in narrow metric tiles.
  final bool autoFit;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.titleMedium;
    final prefix = signed && amount > 0 ? '+' : '';
    final text = Text(
      '$prefix${money(amount, currency: currency)}',
      maxLines: maxLines,
      softWrap: !autoFit,
      overflow: TextOverflow.ellipsis,
      style: (base ?? const TextStyle()).copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: base?.fontWeight ?? FontWeight.w700,
      ),
    );
    if (!autoFit) return text;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: text,
    );
  }
}
