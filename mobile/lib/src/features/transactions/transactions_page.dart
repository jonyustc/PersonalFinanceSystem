import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';
import 'transaction_tile.dart';

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  String _type = 'all';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final currency = snapshot.session?.currency ?? 'BDT';
    final transactions = snapshot.transactions.where((row) {
      final typeMatch = _type == 'all' || row['type'] == _type;
      final haystack = [
        row['merchant_name'],
        row['description'],
        row['type'],
      ].whereType<String>().join(' ').toLowerCase();
      final queryMatch = _query.trim().isEmpty ||
          haystack.contains(_query.trim().toLowerCase());
      return typeMatch && queryMatch;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  SearchBar(
                    hintText: 'Search merchant or note',
                    leading: const Icon(Icons.search),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _TypeChip(
                        label: 'All',
                        selected: _type == 'all',
                        onSelected: () => setState(() => _type = 'all'),
                      ),
                      _TypeChip(
                        label: 'Expense',
                        selected: _type == 'expense',
                        onSelected: () => setState(() => _type = 'expense'),
                      ),
                      _TypeChip(
                        label: 'Income',
                        selected: _type == 'income',
                        onSelected: () => setState(() => _type = 'income'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (transactions.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: EmptyPanel(
                  icon: Icons.receipt_long_outlined,
                  title: 'No matching transactions',
                  body: 'Pull to sync, add a transaction, or clear filters.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              sliver: SliverList.separated(
                itemCount: transactions.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  return TransactionTile(
                    row: transactions[index],
                    currency: currency,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => onSelected(),
      ),
    );
  }
}
