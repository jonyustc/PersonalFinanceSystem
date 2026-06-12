import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Lays out metric tiles in a responsive grid, choosing the column count from
/// the available width so tiles stay a comfortable size on any screen.
class MetricGrid extends StatelessWidget {
  const MetricGrid({
    super.key,
    required this.children,
    this.spacing = AppSpacing.md,
    this.minTileWidth = 158,
  });

  final List<Widget> children;
  final double spacing;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        var columns = (maxWidth / minTileWidth).floor().clamp(1, 4);
        if (columns > children.length) columns = children.length;
        final tileWidth = columns <= 1
            ? maxWidth
            : (maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: tileWidth, child: child),
          ],
        );
      },
    );
  }
}
