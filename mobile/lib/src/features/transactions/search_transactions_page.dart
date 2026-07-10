import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance_summary.dart' show countsInTotals;
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../dashboard/dashboard_page.dart';
import 'transaction_details_page.dart';
import 'transaction_tile.dart';

/// Full-history search across all transactions with text, type, category,
/// account and date-range filters.
class SearchTransactionsPage extends ConsumerStatefulWidget {
  const SearchTransactionsPage({super.key});

  @override
  ConsumerState<SearchTransactionsPage> createState() =>
      _SearchTransactionsPageState();
}

class _SearchTransactionsPageState
    extends ConsumerState<SearchTransactionsPage> {
  final _controller = TextEditingController();
  String _query = '';
  String _type = 'all';
  String? _categoryId;
  String? _accountId;
  DateTimeRange? _range;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    final currency = snapshot?.session?.currency ?? 'BDT';
    final categories = snapshot?.categories ?? const [];
    final accounts = snapshot?.accounts ?? const [];
    final categoryById = {
      for (final c in categories) c['id'] as String: c,
    };
    final accountById = {
      for (final a in accounts) a['id'] as String: a,
    };

    final results = (snapshot?.transactions ?? const [])
        .where(_matches)
        .toList()
      ..sort(
        (a, b) => (b['txn_date'] as String? ?? '').compareTo(
          a['txn_date'] as String? ?? '',
        ),
      );

    double total = 0;
    for (final row in results) {
      // Excluded rows stay in the results list but don't count in the total.
      if (!countsInTotals(row)) continue;
      final amount = asDouble(row['amount']);
      final type = row['type'] as String? ?? 'expense';
      total += type == 'income' ? amount : -amount;
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search all transactions',
            border: InputBorder.none,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final entry in const {
                        'all': 'All',
                        'expense': 'Expense',
                        'income': 'Income',
                        'transfer': 'Transfer',
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(entry.value),
                            selected: _type == entry.key,
                            onSelected: (_) =>
                                setState(() => _type = entry.key),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _FilterButton(
                        icon: Icons.date_range,
                        label: _range == null
                            ? 'Any date'
                            : '${compactDate(_range!.start.toIso8601String())} → ${compactDate(_range!.end.toIso8601String())}',
                        active: _range != null,
                        onTap: _pickRange,
                        onClear: _range == null
                            ? null
                            : () => setState(() => _range = null),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _FilterButton(
                        icon: Icons.category_outlined,
                        label: _categoryId == null
                            ? 'Any category'
                            : (categoryById[_categoryId]?['name'] as String? ??
                                  'Category'),
                        active: _categoryId != null,
                        onTap: () => _pickCategory(categories),
                        onClear: _categoryId == null
                            ? null
                            : () => setState(() => _categoryId = null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                _FilterButton(
                  icon: Icons.account_balance_wallet_outlined,
                  label: _accountId == null
                      ? 'Any account'
                      : (accountById[_accountId]?['name'] as String? ??
                            'Account'),
                  active: _accountId != null,
                  onTap: () => _pickAccount(accounts),
                  onClear: _accountId == null
                      ? null
                      : () => setState(() => _accountId = null),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${results.length} result${results.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (results.isNotEmpty)
                  Text(
                    'Net ${total >= 0 ? '+' : ''}${money(total, currency: currency)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.amount(context, positive: total >= 0),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? const EmptyPanel(
                    icon: Icons.search_off,
                    title: 'No matches',
                    body: 'Try different keywords or clear some filters.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.xl,
                    ),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final row = results[index];
                      return Padding(
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
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  bool _matches(Map<String, dynamic> row) {
    final type = row['type'] as String? ?? 'expense';
    if (_type != 'all' && type != _type) return false;
    if (_categoryId != null && row['category_id'] != _categoryId) return false;
    if (_accountId != null &&
        row['account_id'] != _accountId &&
        row['transfer_account_id'] != _accountId) {
      return false;
    }
    if (_range != null) {
      final date = DateTime.tryParse(row['txn_date'] as String? ?? '');
      if (date == null) return false;
      final local = date.toLocal();
      final start = DateTime(
        _range!.start.year,
        _range!.start.month,
        _range!.start.day,
      );
      final end = DateTime(
        _range!.end.year,
        _range!.end.month,
        _range!.end.day,
        23,
        59,
        59,
      );
      if (local.isBefore(start) || local.isAfter(end)) return false;
    }
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      row['merchant_name'],
      row['description'],
      row['type'],
      asDouble(row['amount']).toStringAsFixed(2),
    ].whereType<Object>().join(' ').toLowerCase();
    return haystack.contains(query);
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _range,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _pickCategory(List<Map<String, dynamic>> categories) async {
    final picked = await _pickFromList(
      title: 'Filter by category',
      items: categories,
    );
    if (picked != null) setState(() => _categoryId = picked);
  }

  Future<void> _pickAccount(List<Map<String, dynamic>> accounts) async {
    final picked = await _pickFromList(
      title: 'Filter by account',
      items: accounts,
    );
    if (picked != null) setState(() => _accountId = picked);
  }

  Future<String?> _pickFromList({
    required String title,
    required List<Map<String, dynamic>> items,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            for (final item in items)
              ListTile(
                title: Text(item['name'] as String? ?? '—'),
                onTap: () => Navigator.of(context).pop(item['id'] as String?),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? scheme.primary.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: active ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? scheme.primary : null,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: scheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}
