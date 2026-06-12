import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance_summary.dart';
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/metric_grid.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';
import '../transactions/transaction_details_page.dart';
import '../transactions/transaction_tile.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key, this.onOpenTransactions});

  final VoidCallback? onOpenTransactions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currency = snapshot.session?.currency ?? 'BDT';
    final summary = buildFinanceSummary(
      accounts: snapshot.accounts,
      categories: snapshot.categories,
      transactions: snapshot.transactions,
      budgets: snapshot.budgets,
      stocks: snapshot.stocks,
      portfolioTransactions: snapshot.portfolioTransactions,
      portfolioSummary: snapshot.portfolioSummary,
    );
    final cards = _resolveCards(snapshot, summary);

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _NetWorthHero(
            summary: summary,
            currency: currency,
            accounts: snapshot.accounts,
          ),
          const SizedBox(height: AppSpacing.md),
          MetricGrid(
            children: [
              StatCard(
                label: 'Cash flow',
                amount: summary.cashFlow,
                currency: currency,
                icon: Icons.swap_vert,
                signed: true,
                amountColor: AppColors.amount(
                  context,
                  positive: summary.cashFlow >= 0,
                ),
                caption: 'Income − expense this month',
              ),
              StatCard(
                label: 'Spent this month',
                amount: summary.monthlyExpense,
                currency: currency,
                icon: Icons.trending_down,
                caption: 'Across all accounts',
              ),
              StatCard(
                label: 'Investments',
                amount: summary.portfolioValue,
                currency: currency,
                icon: Icons.show_chart,
                caption: summary.portfolioGain == 0
                    ? 'Portfolio value'
                    : '${summary.portfolioGain >= 0 ? '+' : ''}${money(summary.portfolioGain, currency: currency)} gain',
                amountColor: null,
              ),
              StatCard(
                label: 'Card outstanding',
                amount: summary.creditCardOutstanding,
                currency: currency,
                icon: Icons.credit_card_outlined,
                amountColor: summary.creditCardOutstanding > 0
                    ? AppColors.amount(context, positive: false)
                    : null,
                caption: 'Owed across cards',
              ),
            ],
          ),
          if (cards.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            const SectionHeader(
              'Credit cards',
              subtitle: 'Utilization this cycle',
            ),
            const SizedBox(height: AppSpacing.md),
            for (final card in cards)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _CardTile(card: card, currency: currency),
              ),
          ],
          const SizedBox(height: AppSpacing.xl),
          SectionHeader(
            "Today's activity",
            subtitle: compactDate(DateTime.now().toIso8601String()),
            action: onOpenTransactions == null
                ? null
                : TextButton(
                    onPressed: onOpenTransactions,
                    child: const Text('View all'),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          _TodayTransactions(
            snapshot.transactions,
            currency: currency,
            onOpenTransactions: onOpenTransactions,
          ),
        ],
      ),
    );
  }

  /// Prefer the authoritative backend `/dashboard/simple` card view when it
  /// has synced; otherwise fall back to the locally computed card rollups.
  List<CardSummary> _resolveCards(AppSnapshot snapshot, FinanceSummary summary) {
    final cardSection =
        snapshot.dashboardSummary?['card_summary'] as Map<String, dynamic>?;
    final backendCards = cardSection?['cards'] as List?;
    if (backendCards != null && backendCards.isNotEmpty) {
      return backendCards
          .whereType<Map>()
          .map((row) => CardSummary.fromBackend(row.cast<String, dynamic>()))
          .toList()
        ..sort((a, b) => b.outstanding.compareTo(a.outstanding));
    }
    return summary.creditCards;
  }
}

class _NetWorthHero extends StatelessWidget {
  const _NetWorthHero({
    required this.summary,
    required this.currency,
    required this.accounts,
  });

  final FinanceSummary summary;
  final String currency;
  final List<Map<String, dynamic>> accounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NET WORTH',
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          MoneyText(
            summary.netWorth,
            currency: currency,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _HeroSplit(
                  label: 'Assets',
                  amount: summary.assets,
                  currency: currency,
                  color: AppColors.amount(context, positive: true),
                  onTap: () => _showBalanceDetails(
                    context,
                    title: 'Assets',
                    rows: _assetRows(accounts, summary, currency),
                    totalLabel: 'Total assets',
                    total: summary.assets,
                    currency: currency,
                  ),
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: AppColors.border(context),
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              ),
              Expanded(
                child: _HeroSplit(
                  label: 'Liabilities',
                  amount: summary.liabilities,
                  currency: currency,
                  color: AppColors.amount(context, positive: false),
                  onTap: () => _showBalanceDetails(
                    context,
                    title: 'Liabilities',
                    rows: _liabilityRows(accounts, currency),
                    totalLabel: 'Total liabilities',
                    total: summary.liabilities,
                    currency: currency,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroSplit extends StatelessWidget {
  const _HeroSplit({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
    this.onTap,
  });

  final String label;
  final double amount;
  final String currency;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            MoneyText(
              amount,
              currency: currency,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.card, required this.currency});

  final CardSummary card;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final percent = card.utilization.clamp(0, 100).toDouble();
    final barColor = AppColors.utilization(context, card.utilization);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  card.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${card.utilization.round()}%',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: barColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              MoneyText(
                card.outstanding,
                currency: currency,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                card.creditLimit > 0
                    ? 'of ${money(card.creditLimit, currency: currency)}'
                    : 'no limit set',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: card.creditLimit > 0 ? percent / 100 : 0,
              minHeight: 6,
              backgroundColor: AppColors.border(context),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _CardMetric(label: 'Available', amount: card.available, currency: currency),
              _CardMetric(label: 'Spent', amount: card.monthlySpending, currency: currency),
              _CardMetric(label: 'Paid', amount: card.monthlyPayment, currency: currency),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardMetric extends StatelessWidget {
  const _CardMetric({
    required this.label,
    required this.amount,
    required this.currency,
  });

  final String label;
  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          MoneyText(
            amount,
            currency: currency,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceDetailRow {
  const _BalanceDetailRow(this.label, this.amount, {this.currency});

  final String label;
  final double amount;
  final String? currency;
}

List<_BalanceDetailRow> _assetRows(
  List<Map<String, dynamic>> accounts,
  FinanceSummary summary,
  String currency,
) {
  final rows = accounts
      .where(
        (account) =>
            !isCreditCardAccount(account) &&
            !isStockBrokerAccount(account) &&
            asDouble(account['balance']) > 0,
      )
      .map(
        (account) => _BalanceDetailRow(
          account['name'] as String? ?? 'Account',
          asDouble(account['balance']),
          currency: account['currency'] as String? ?? currency,
        ),
      )
      .toList();
  if (summary.portfolioValue != 0) {
    rows.add(_BalanceDetailRow('Stock portfolio', summary.portfolioValue));
  }
  rows.sort((a, b) => b.amount.compareTo(a.amount));
  return rows;
}

List<_BalanceDetailRow> _liabilityRows(
  List<Map<String, dynamic>> accounts,
  String currency,
) {
  final rows = <_BalanceDetailRow>[];
  for (final account in accounts) {
    final name = account['name'] as String? ?? 'Account';
    final accountCurrency = account['currency'] as String? ?? currency;
    if (isCreditCardAccount(account)) {
      final outstanding = asDouble(account['current_outstanding']);
      if (outstanding != 0) {
        rows.add(_BalanceDetailRow(name, outstanding, currency: accountCurrency));
      }
    } else if (!isStockBrokerAccount(account)) {
      final balance = asDouble(account['balance']);
      if (balance < 0) {
        rows.add(
          _BalanceDetailRow(name, balance.abs(), currency: accountCurrency),
        );
      }
    }
  }
  rows.sort((a, b) => b.amount.compareTo(a.amount));
  return rows;
}

void _showBalanceDetails(
  BuildContext context, {
  required String title,
  required List<_BalanceDetailRow> rows,
  required String totalLabel,
  required double total,
  required String currency,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Text('No rows to show.'),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        row.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: MoneyText(
                        row.amount,
                        currency: row.currency ?? currency,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    );
                  },
                ),
              ),
            const Divider(height: AppSpacing.xl),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                totalLabel,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: MoneyText(
                total,
                currency: currency,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TodayTransactions extends StatelessWidget {
  const _TodayTransactions(
    this.transactions, {
    required this.currency,
    this.onOpenTransactions,
  });

  final List<Map<String, dynamic>> transactions;
  final String currency;
  final VoidCallback? onOpenTransactions;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final recent = todayTransactions(transactions, today: today, limit: 8);
    if (recent.isEmpty) {
      return _TodayEmptyPanel(onOpenTransactions: onOpenTransactions);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in recent)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: TransactionTile(
              row: row,
              currency: currency,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      TransactionDetailsPage(transactionId: row['id'] as String),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

List<Map<String, dynamic>> todayTransactions(
  List<Map<String, dynamic>> transactions, {
  required DateTime today,
  int limit = 8,
}) {
  final start = DateTime(today.year, today.month, today.day);
  final end = start.add(const Duration(days: 1));
  final rows =
      transactions.where((row) {
        final parsed = DateTime.tryParse(row['txn_date'] as String? ?? '');
        if (parsed == null) return false;
        final localDate = parsed.toLocal();
        return !localDate.isBefore(start) && localDate.isBefore(end);
      }).toList()..sort((a, b) {
        final left = DateTime.tryParse(a['txn_date'] as String? ?? '');
        final right = DateTime.tryParse(b['txn_date'] as String? ?? '');
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
  return rows.take(limit).toList();
}

class _TodayEmptyPanel extends StatelessWidget {
  const _TodayEmptyPanel({this.onOpenTransactions});

  final VoidCallback? onOpenTransactions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Icon(Icons.today_outlined, size: 34, color: scheme.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No transactions today',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tap + to add one, or review older entries.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (onOpenTransactions != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onOpenTransactions,
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('View all transactions'),
            ),
          ],
        ],
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Icon(icon, size: 34, color: scheme.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
