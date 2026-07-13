import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance_summary.dart';
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/metric_grid.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/money_text.dart';
import '../../widgets/section_header.dart';
import '../../widgets/stat_card.dart';
import '../dashboard/dashboard_page.dart';
import '../transactions/transaction_details_page.dart';
import '../transactions/transaction_tile.dart';

class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const ListSkeleton();
    final accounts = snapshot.accounts;
    final currency = snapshot.session?.currency ?? 'BDT';
    final summary = buildAccountSummary(accounts);
    final groups = _groupAccounts(accounts);

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _AccountSummaryHeader(summary: summary, currency: currency),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showTransferSheet(context, ref),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Transfer'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showCreateAccountSheet(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Account'),
                ),
              ),
            ],
          ),
          if (accounts.isEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            const EmptyPanel(
              icon: Icons.account_balance_outlined,
              title: 'No accounts cached',
              body: 'Sync from the API to bring your accounts into SQLite.',
            ),
          ],
          for (final group in groups) ...[
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              group.label,
              subtitle:
                  '${group.accounts.length} account${group.accounts.length == 1 ? '' : 's'} · ${money(group.total, currency: currency)}',
            ),
            const SizedBox(height: AppSpacing.md),
            for (final account in group.accounts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _AccountRow(
                  account: account,
                  currency: currency,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AccountDetailsPage(accountId: account['id'] as String),
                    ),
                  ),
                  onLongPress: () => _archiveAccount(context, ref, account),
                ),
              ),
          ],
        ],
      ),
    );
  }

  List<_AccountGroup> _groupAccounts(List<Map<String, dynamic>> accounts) {
    const order = [
      ('cash', 'Cash'),
      ('bank', 'Bank'),
      ('mobile_banking', 'Mobile banking'),
      ('debit_card', 'Debit cards'),
      ('credit_card', 'Credit cards'),
      ('other', 'Other'),
    ];
    final buckets = <String, List<Map<String, dynamic>>>{};
    for (final account in accounts) {
      buckets.putIfAbsent(_groupKey(account), () => []).add(account);
    }
    final groups = <_AccountGroup>[];
    for (final entry in order) {
      final rows = buckets[entry.$1];
      if (rows == null || rows.isEmpty) continue;
      final total = rows.fold<double>(
        0,
        (sum, row) => sum + _accountValue(row),
      );
      groups.add(_AccountGroup(label: entry.$2, accounts: rows, total: total));
    }
    return groups;
  }

  String _groupKey(Map<String, dynamic> account) {
    if (isCreditCardAccount(account)) return 'credit_card';
    final type = (account['type'] as String? ?? '').toLowerCase();
    if (type == 'cash') return 'cash';
    if (type == 'bank') return 'bank';
    if (type == 'mobile_banking' || type.contains('mobile')) {
      return 'mobile_banking';
    }
    if (type == 'debit_card') return 'debit_card';
    return 'other';
  }

  Future<void> _archiveAccount(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> account,
  ) async {
    final name = account['name'] as String? ?? 'Account';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Archive account?',
      message: '"$name" will be removed from your active account lists.',
      confirmLabel: 'Archive',
      icon: Icons.archive_outlined,
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .archiveAccount(account['id'] as String);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _showCreateAccountSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateAccountSheet(),
    );
  }

  void _showTransferSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _TransferSheet(),
    );
  }
}

void _showEditAccountSheet(BuildContext context, Map<String, dynamic> account) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditAccountSheet(account: account),
  );
}

/// Full-screen view of a single account: a colorful balance header, an in/out
/// summary and every mirrored transaction that touches it. Opened by tapping an
/// account row.
class AccountDetailsPage extends ConsumerWidget {
  const AccountDetailsPage({super.key, required this.accountId});

  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final account = snapshot?.accounts.cast<Map<String, dynamic>?>().firstWhere(
      (a) => a?['id'] == accountId,
      orElse: () => null,
    );
    if (snapshot == null || account == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyPanel(
          icon: Icons.account_balance_outlined,
          title: 'Account unavailable',
          body: 'This account is no longer in the local data.',
        ),
      );
    }

    final currency =
        account['currency'] as String? ?? snapshot.session?.currency ?? 'BDT';
    final categoryById = {
      for (final c in snapshot.categories) c['id'] as String: c,
    };
    final accent = _accountColor(account['type'] as String?);

    final txns =
        snapshot.transactions
            .where(
              (row) =>
                  row['account_id'] == accountId ||
                  row['transfer_account_id'] == accountId,
            )
            .toList()
          ..sort((a, b) {
            final left = DateTime.tryParse(a['txn_date'] as String? ?? '');
            final right = DateTime.tryParse(b['txn_date'] as String? ?? '');
            if (left == null && right == null) return 0;
            if (left == null) return 1;
            if (right == null) return -1;
            return right.compareTo(left);
          });

    var moneyIn = 0.0;
    var moneyOut = 0.0;
    for (final row in txns) {
      final amount = asDouble(row['amount']);
      final fromThis = row['account_id'] == accountId;
      switch (row['type']) {
        case 'income':
          moneyIn += amount;
        case 'expense':
          moneyOut += amount;
        case 'transfer':
          if (fromThis) {
            moneyOut += amount;
          } else {
            moneyIn += amount;
          }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(account['name'] as String? ?? 'Account'),
        actions: [
          IconButton(
            tooltip: 'Edit account',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditAccountSheet(context, account),
          ),
          IconButton(
            tooltip: 'Archive account',
            icon: const Icon(Icons.archive_outlined),
            onPressed: () => _archive(context, ref, account),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            96,
          ),
          children: [
            _AccountHero(account: account, accent: accent, currency: currency),
            const SizedBox(height: AppSpacing.md),
            _InOutRow(
              moneyIn: moneyIn,
              moneyOut: moneyOut,
              count: txns.length,
              currency: currency,
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              'Transactions',
              subtitle: txns.isEmpty
                  ? 'None yet'
                  : '${txns.length} shown${txns.length >= 250 ? ' (recent)' : ''}',
            ),
            const SizedBox(height: AppSpacing.md),
            if (txns.isEmpty)
              const EmptyPanel(
                icon: Icons.receipt_long_outlined,
                title: 'No transactions',
                body: 'Money you move through this account will appear here.',
              )
            else
              ...txns.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: TransactionTile(
                    row: row,
                    currency: currency,
                    category: categoryById[row['category_id']],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TransactionDetailsPage(
                          transactionId: row['id'] as String,
                        ),
                      ),
                    ),
                    onDelete: () => _confirmDelete(context, ref, row),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _archive(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> account,
  ) async {
    final name = account['name'] as String? ?? 'Account';
    final confirmed = await showConfirmDialog(
      context,
      title: 'Archive account?',
      message: '"$name" will be removed from your active account lists.',
      confirmLabel: 'Archive',
      icon: Icons.archive_outlined,
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .archiveAccount(account['id'] as String);
      if (context.mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> row,
  ) async {
    final title =
        (row['merchant_name'] ?? row['description'] ?? 'transaction') as String;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete transaction?',
      message: 'Delete "$title" and refresh balances? This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref
          .read(appControllerProvider.notifier)
          .deleteTransaction(row['id'] as String);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

/// Colorful balance header for the account details page — mirrors the account's
/// accent color and shows the running balance (or card outstanding + credit
/// utilization).
class _AccountHero extends StatelessWidget {
  const _AccountHero({
    required this.account,
    required this.accent,
    required this.currency,
  });

  final Map<String, dynamic> account;
  final Color accent;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCard = isCreditCardAccount(account);
    final typeLabel = (account['type'] as String? ?? '')
        .replaceAll('_', ' ')
        .toUpperCase();
    final primaryAmount = isCard
        ? asDouble(account['current_outstanding'])
        : asDouble(account['balance']);
    final limit = asDouble(account['credit_limit']);
    final available = (limit - primaryAmount) > 0 ? limit - primaryAmount : 0.0;
    final utilization = limit > 0 ? primaryAmount / limit * 100 : 0.0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, Color.alphaBlend(Colors.black26, accent)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _accountIcon(account['type'] as String?),
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                typeLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            isCard ? 'OUTSTANDING' : 'BALANCE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          MoneyText(
            primaryAmount,
            currency: currency,
            autoFit: true,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          if (isCard && limit > 0) ...[
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: (utilization / 100).clamp(0, 1).toDouble(),
                minHeight: 6,
                backgroundColor: Colors.white.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${money(available, currency: currency)} available · '
              '${utilization.round()}% used',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Money-in / money-out / count summary for the account details page.
class _InOutRow extends StatelessWidget {
  const _InOutRow({
    required this.moneyIn,
    required this.moneyOut,
    required this.count,
    required this.currency,
  });

  final double moneyIn;
  final double moneyOut;
  final int count;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatCard(
            label: 'Money in',
            amount: moneyIn,
            currency: currency,
            icon: Icons.south_west,
            amountColor: AppColors.amount(context, positive: true),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: StatCard(
            label: 'Money out',
            amount: moneyOut,
            currency: currency,
            icon: Icons.north_east,
            amountColor: AppColors.amount(context, positive: false),
          ),
        ),
      ],
    );
  }
}

/// A credit card's contribution to a group total is its debt (shown as the
/// outstanding amount); every other account contributes its balance.
double _accountValue(Map<String, dynamic> account) {
  if (isCreditCardAccount(account)) {
    return asDouble(account['current_outstanding']);
  }
  return asDouble(account['balance']);
}

class _AccountGroup {
  const _AccountGroup({
    required this.label,
    required this.accounts,
    required this.total,
  });

  final String label;
  final List<Map<String, dynamic>> accounts;
  final double total;
}

class _AccountSummaryHeader extends StatelessWidget {
  const _AccountSummaryHeader({required this.summary, required this.currency});

  final AccountSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Column(
      children: [
        AppCard(
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
              SizedBox(
                width: double.infinity,
                child: MoneyText(
                  summary.netWorth,
                  currency: currency,
                  autoFit: true,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        MetricGrid(
          children: [
            StatCard(
              label: 'Assets',
              amount: summary.totalAssets,
              currency: currency,
              icon: Icons.account_balance_wallet_outlined,
              amountColor: AppColors.amount(context, positive: true),
            ),
            StatCard(
              label: 'Liabilities',
              amount: summary.liabilities,
              currency: currency,
              icon: Icons.credit_card_outlined,
              amountColor: summary.liabilities > 0
                  ? AppColors.amount(context, positive: false)
                  : null,
            ),
            StatCard(
              label: 'Cash',
              amount: summary.cashBalance,
              currency: currency,
              icon: Icons.payments_outlined,
            ),
            StatCard(
              label: 'Card debt',
              amount: summary.cardDebt,
              currency: currency,
              icon: Icons.credit_card,
              amountColor: summary.cardDebt > 0
                  ? AppColors.amount(context, positive: false)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.currency,
    this.onTap,
    this.onLongPress,
  });

  final Map<String, dynamic> account;
  final String currency;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final accountCurrency = account['currency'] as String? ?? currency;
    final isCard = isCreditCardAccount(account);
    final typeColor = _accountColor(account['type'] as String?);
    final avatar = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(
        _accountIcon(account['type'] as String?),
        size: 22,
        color: typeColor,
      ),
    );
    final typeLabel = (account['type'] as String? ?? '')
        .replaceAll('_', ' ')
        .toUpperCase();

    if (!isCard) {
      final balance = asDouble(account['balance']);
      return AppCard(
        onTap: onTap,
        onLongPress: onLongPress,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account['name'] as String? ?? 'Account',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    typeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: MoneyText(
                balance,
                currency: accountCurrency,
                autoFit: true,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                color: balance < 0
                    ? AppColors.amount(context, positive: false)
                    : null,
              ),
            ),
          ],
        ),
      );
    }

    final limit = asDouble(account['credit_limit']);
    final outstanding = asDouble(account['current_outstanding']);
    final available = (limit - outstanding) > 0 ? limit - outstanding : 0.0;
    final utilization = limit > 0 ? outstanding / limit * 100 : 0.0;
    final barColor = AppColors.utilization(context, utilization);
    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              avatar,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account['name'] as String? ?? 'Credit card',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'CREDIT CARD',
                      style: theme.textTheme.labelSmall?.copyWith(color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: MoneyText(
                  outstanding,
                  currency: accountCurrency,
                  autoFit: true,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  color: outstanding > 0
                      ? AppColors.amount(context, positive: false)
                      : null,
                ),
              ),
            ],
          ),
          if (limit > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: (utilization / 100).clamp(0, 1).toDouble(),
                minHeight: 6,
                backgroundColor: AppColors.border(context),
                valueColor: AlwaysStoppedAnimation(barColor),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${money(available, currency: accountCurrency)} available',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                Text(
                  '${utilization.round()}% used',
                  style: theme.textTheme.bodySmall?.copyWith(color: barColor),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

IconData _accountIcon(String? type) {
  final value = (type ?? '').toLowerCase();
  if (value.contains('mobile')) return Icons.phone_android;
  if (value.contains('credit')) return Icons.credit_card;
  if (value.contains('debit')) return Icons.credit_card_outlined;
  if (value.contains('card')) return Icons.credit_card;
  if (value.contains('bank')) return Icons.account_balance;
  if (value.contains('cash')) return Icons.payments_outlined;
  return Icons.wallet;
}

/// Distinct accent color per account type so the accounts list reads at a
/// glance, Wallet-style.
Color _accountColor(String? type) {
  final value = (type ?? '').toLowerCase();
  if (value.contains('mobile')) return const Color(0xFFEC4899); // pink
  if (value.contains('credit')) return const Color(0xFFEF4444); // red
  if (value.contains('debit')) return const Color(0xFF6366F1); // indigo
  if (value.contains('card')) return const Color(0xFFEF4444);
  if (value.contains('bank')) return const Color(0xFF3B82F6); // blue
  if (value.contains('cash')) return const Color(0xFF10B981); // emerald
  return const Color(0xFF8B5CF6); // violet
}

class _CreateAccountSheet extends ConsumerStatefulWidget {
  const _CreateAccountSheet();

  @override
  ConsumerState<_CreateAccountSheet> createState() => _CreateAccountSheetState();
}

class _CreateAccountSheetState extends ConsumerState<_CreateAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _openingBalance = TextEditingController(text: '0');
  final _color = TextEditingController();
  final _icon = TextEditingController();
  final _notes = TextEditingController();
  String _typeChoice = 'cash';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _openingBalance.dispose();
    _color.dispose();
    _icon.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency =
        ref.watch(appControllerProvider).asData?.value.session?.currency ?? 'BDT';
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'New account',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Enter account name' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _typeChoice,
                decoration: const InputDecoration(
                  labelText: 'Account type',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  DropdownMenuItem(value: 'credit_card', child: Text('Credit Card')),
                  DropdownMenuItem(value: 'bank:savings', child: Text('Savings')),
                  DropdownMenuItem(value: 'bank:investment', child: Text('Investment')),
                  DropdownMenuItem(value: 'credit_card:loan', child: Text('Loan')),
                  DropdownMenuItem(value: 'cash:other', child: Text('Other')),
                ],
                onChanged: (value) =>
                    setState(() => _typeChoice = value ?? _typeChoice),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _openingBalance,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Opening balance',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (value) =>
                    double.tryParse(value ?? '') == null ? 'Enter a valid amount' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _color,
                      decoration: const InputDecoration(labelText: 'Color'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _icon,
                      decoration: const InputDecoration(labelText: 'Icon'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : () => _save(currency),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Create account'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(String currency) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(appControllerProvider.notifier).createAccount(
            name: _name.text.trim(),
            type: _backendType,
            openingBalance: double.parse(_openingBalance.text),
            currency: currency,
            color: _color.text,
            icon: _icon.text,
            notes: _notes.text,
            accountSubtype: _accountSubtype,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String get _backendType => _typeChoice.split(':').first;

  String? get _accountSubtype {
    final parts = _typeChoice.split(':');
    return parts.length > 1 ? parts.last : null;
  }
}

class _EditAccountSheet extends ConsumerStatefulWidget {
  const _EditAccountSheet({required this.account});

  final Map<String, dynamic> account;

  @override
  ConsumerState<_EditAccountSheet> createState() => _EditAccountSheetState();
}

class _EditAccountSheetState extends ConsumerState<_EditAccountSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _openingBalance;
  late final TextEditingController _color;
  late final TextEditingController _icon;
  late String _type;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.account['name'] as String? ?? '');
    _openingBalance =
        TextEditingController(text: asDouble(widget.account['opening_balance']).toStringAsFixed(2));
    _color = TextEditingController(text: widget.account['color'] as String? ?? '');
    _icon = TextEditingController(text: widget.account['icon'] as String? ?? '');
    _type = widget.account['type'] as String? ?? 'cash';
  }

  @override
  void dispose() {
    _name.dispose();
    _openingBalance.dispose();
    _color.dispose();
    _icon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Edit account',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Account name',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Enter account name' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(
                labelText: 'Account type',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'bank', child: Text('Bank')),
                DropdownMenuItem(value: 'mobile_banking', child: Text('Mobile banking')),
                DropdownMenuItem(value: 'debit_card', child: Text('Debit card')),
                DropdownMenuItem(value: 'credit_card', child: Text('Credit card')),
              ],
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _openingBalance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Opening balance',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) =>
                  double.tryParse(value ?? '') == null ? 'Enter a valid amount' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _color,
                    decoration: const InputDecoration(labelText: 'Color'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _icon,
                    decoration: const InputDecoration(labelText: 'Icon'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Save account'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(appControllerProvider.notifier).updateAccount(
            id: widget.account['id'] as String,
            name: _name.text.trim(),
            type: _type,
            openingBalance: double.parse(_openingBalance.text),
            currency: widget.account['currency'] as String? ?? 'BDT',
            color: _color.text,
            icon: _icon.text,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _TransferSheet extends ConsumerStatefulWidget {
  const _TransferSheet();

  @override
  ConsumerState<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<_TransferSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _fromAccountId;
  String? _toAccountId;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(appControllerProvider).asData?.value.accounts ?? [];
    _fromAccountId ??= accounts.isNotEmpty ? accounts.first['id'] as String : null;
    _toAccountId ??= accounts.length > 1 ? accounts[1]['id'] as String : null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Transfer',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _AccountDropdown(
              label: 'From',
              value: _fromAccountId,
              accounts: accounts,
              onChanged: (value) => setState(() => _fromAccountId = value),
            ),
            const SizedBox(height: 12),
            _AccountDropdown(
              label: 'To',
              value: _toAccountId,
              accounts: accounts,
              onChanged: (value) => setState(() => _toAccountId = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                final amount = double.tryParse(value ?? '');
                if (amount == null || amount <= 0) return 'Enter a valid amount';
                if (_fromAccountId == _toAccountId) return 'Choose two different accounts';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz),
              label: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(appControllerProvider.notifier).createTransfer(
            fromAccountId: _fromAccountId!,
            toAccountId: _toAccountId!,
            amount: double.parse(_amount.text),
            date: DateTime.now(),
            notes: _note.text,
            isCardPayment: _isCreditCard(_toAccountId),
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  bool _isCreditCard(String? accountId) {
    final accounts = ref.read(appControllerProvider).asData?.value.accounts ?? [];
    for (final account in accounts) {
      if (account['id'] == accountId) {
        final type = account['type'] as String? ?? '';
        return type == 'card' || type == 'credit_card';
      }
    }
    return false;
  }
}

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.label,
    required this.value,
    required this.accounts,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<Map<String, dynamic>> accounts;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
      ),
      items: accounts
          .map(
            (row) => DropdownMenuItem<String>(
              value: row['id'] as String,
              child: Text(row['name'] as String),
            ),
          )
          .toList(),
      onChanged: onChanged,
      validator: (value) => value == null ? 'Choose an account' : null,
    );
  }
}
