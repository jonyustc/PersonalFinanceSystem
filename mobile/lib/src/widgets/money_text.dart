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
  });

  final num amount;
  final String currency;
  final TextStyle? style;
  final Color? color;

  /// When true, prefixes a `+` for positive values (useful for deltas).
  final bool signed;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.titleMedium;
    final prefix = signed && amount > 0 ? '+' : '';
    return Text(
      '$prefix${money(amount, currency: currency)}',
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: (base ?? const TextStyle()).copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: base?.fontWeight ?? FontWeight.w700,
      ),
    );
  }
}
