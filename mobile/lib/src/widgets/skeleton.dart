import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_card.dart';

/// A pulsing placeholder block used while data loads, for a more premium feel
/// than a bare spinner.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 16, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = AppColors.border(context);
    final highlight = Theme.of(context).colorScheme.surfaceContainerHighest;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = (math.sin(_controller.value * 2 * math.pi) + 1) / 2;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(base, highlight, t),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// Loading placeholder that mirrors the dashboard layout (hero + metric tiles).
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const AppCard(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(width: 80, height: 12),
              SizedBox(height: AppSpacing.md),
              Skeleton(width: 180, height: 30),
              SizedBox(height: AppSpacing.lg),
              Skeleton(height: 14),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: const [
            Expanded(child: _TileSkeleton()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: _TileSkeleton()),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: const [
            Expanded(child: _TileSkeleton()),
            SizedBox(width: AppSpacing.md),
            Expanded(child: _TileSkeleton()),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const ListSkeleton(rows: 4),
      ],
    );
  }
}

class _TileSkeleton extends StatelessWidget {
  const _TileSkeleton();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 38, height: 38, radius: 12),
          SizedBox(height: AppSpacing.md),
          Skeleton(width: 70, height: 10),
          SizedBox(height: AppSpacing.sm),
          Skeleton(width: 110, height: 20),
        ],
      ),
    );
  }
}

/// A simple list of card-shaped skeleton rows, for list screens.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({super.key, this.rows = 6, this.padding});

  final int rows;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      itemCount: rows,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, _) => const AppCard(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Skeleton(width: 42, height: 42, radius: 21),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 140, height: 12),
                  SizedBox(height: AppSpacing.sm),
                  Skeleton(width: 90, height: 10),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.md),
            Skeleton(width: 60, height: 14),
          ],
        ),
      ),
    );
  }
}
