import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';
import 'transaction_tile.dart';

class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final transactions = snapshot.transactions;
    final currency = snapshot.session?.currency ?? 'USD';

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: transactions.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                EmptyPanel(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions cached',
                  body: 'Pull to sync or add your first Android transaction.',
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: transactions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                return TransactionTile(
                  row: transactions[index],
                  currency: currency,
                );
              },
            ),
    );
  }
}
