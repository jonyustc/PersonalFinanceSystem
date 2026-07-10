import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance_summary.dart'
    show DebtPersonSummary, buildDebtSummaries, debtSign, debtTypeLabels;
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../theme/category_visuals.dart';
import '../../widgets/app_card.dart';
import '../../widgets/metric_grid.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stat_card.dart';
import '../dashboard/dashboard_page.dart' show EmptyPanel;

/// Loans / IOU overview: per-person balances computed locally from the
/// mirrored transactions that carry a `debt_type`, so it works offline like
/// every other read in the app.
class DebtsPage extends ConsumerWidget {
  const DebtsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const ListSkeleton();

    final theme = Theme.of(context);
    final currency = snapshot.session?.currency ?? 'BDT';
    final people = buildDebtSummaries(snapshot.transactions);
    double theyOweMe = 0;
    double iOwe = 0;
    for (final person in people) {
      if (person.net > 0) theyOweMe += person.net;
      if (person.net < 0) iOwe += person.net.abs();
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          96,
        ),
        children: [
          MetricGrid(
            children: [
              StatCard(
                label: 'They owe you',
                amount: theyOweMe,
                currency: currency,
                icon: Icons.call_received,
                accent: AppColors.amount(context, positive: true),
                amountColor: AppColors.amount(context, positive: true),
              ),
              StatCard(
                label: 'You owe',
                amount: iOwe,
                currency: currency,
                icon: Icons.call_made,
                accent: AppColors.amount(context, positive: false),
                amountColor: AppColors.amount(context, positive: false),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (people.isEmpty)
            const EmptyPanel(
              icon: Icons.handshake_outlined,
              title: 'No loans tracked',
              body:
                  'Tag a transaction as "Loan / IOU" when adding it to track '
                  'money you lend or borrow, person by person.',
            )
          else
            ...people.map(
              (person) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _PersonCard(
                  person: person,
                  currency: currency,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PersonDebtsPage(name: person.name),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Based on recent synced transactions',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.person,
    required this.currency,
    required this.onTap,
  });

  final DebtPersonSummary person;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = categoryVisual(name: person.name).color;
    final settled = person.net.abs() < 0.005;
    final positive = person.net > 0;
    final trailing = settled
        ? Text(
            'Settled',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          )
        : Text(
            '${positive ? '+' : '-'}${money(person.net.abs(), currency: currency)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.amount(context, positive: positive),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              person.name.characters.first.toUpperCase(),
              style: theme.textTheme.titleMedium?.copyWith(
                color: tint,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${person.transactionCount} transaction'
                  '${person.transactionCount == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          trailing,
        ],
      ),
    );
  }
}

/// All mirrored loan/IOU transactions with one person, newest first, with the
/// debt-type label and the signed effect on their balance.
class PersonDebtsPage extends ConsumerWidget {
  const PersonDebtsPage({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final theme = Theme.of(context);
    final currency = snapshot?.session?.currency ?? 'BDT';
    final rows =
        (snapshot?.transactions ?? const [])
            .where(
              (row) =>
                  (row['debt_type'] as String?)?.isNotEmpty == true &&
                  ((row['counterparty_name'] as String?)?.trim() ?? '') == name,
            )
            .toList()
          ..sort(
            (a, b) => (b['txn_date'] as String? ?? '').compareTo(
              a['txn_date'] as String? ?? '',
            ),
          );

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: rows.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: EmptyPanel(
                  icon: Icons.handshake_outlined,
                  title: 'No loans tracked',
                  body: 'No loan transactions with this person are synced.',
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = rows[index];
                final debtType = row['debt_type'] as String? ?? '';
                final sign = debtSign(debtType);
                final amount = asDouble(row['amount']);
                final note = (row['description'] as String?)?.trim();
                return ListTile(
                  dense: true,
                  leading: Icon(
                    sign >= 0 ? Icons.call_received : Icons.call_made,
                    color: AppColors.amount(context, positive: sign >= 0),
                  ),
                  title: Text(debtTypeLabels[debtType] ?? debtType),
                  subtitle: Text(
                    [
                      compactDate(row['txn_date'] as String? ?? ''),
                      if (note != null && note.isNotEmpty) note,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    '${sign >= 0 ? '+' : '-'}${money(amount, currency: currency)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.amount(context, positive: sign >= 0),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
