import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final expense = snapshot.categories
        .where((row) => row['type'] == 'expense')
        .toList();
    final income = snapshot.categories
        .where((row) => row['type'] == 'income')
        .toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(
            title: Text('Categories'),
            pinned: true,
            automaticallyImplyLeading: false,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                _CategorySection(
                  title: 'Expense categories',
                  icon: Icons.north_east,
                  rows: _roots(expense),
                  allRows: expense,
                  tone: const Color(0xFFFEE2E2),
                ),
                const SizedBox(height: 16),
                _CategorySection(
                  title: 'Income categories',
                  icon: Icons.south_west,
                  rows: _roots(income),
                  allRows: income,
                  tone: const Color(0xFFDCFCE7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _roots(List<Map<String, dynamic>> rows) {
    return rows.where((row) => row['parent_id'] == null).toList();
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.icon,
    required this.rows,
    required this.allRows,
    required this.tone,
  });

  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> allRows;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return EmptyPanel(
        icon: icon,
        title: title,
        body: 'No categories cached for this group yet.',
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: tone,
                  foregroundColor: Colors.black87,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...rows.map((row) {
              final children = allRows
                  .where((child) => child['parent_id'] == row['id'])
                  .toList();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InputChip(
                      avatar: Icon(icon, size: 16),
                      label: Text(row['name'] as String? ?? 'Category'),
                    ),
                    if (children.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 28, top: 6),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: children
                              .map(
                                (child) => Chip(
                                  label: Text(
                                    child['name'] as String? ?? 'Subcategory',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
