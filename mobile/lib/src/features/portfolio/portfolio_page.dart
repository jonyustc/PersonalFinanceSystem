import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/finance_summary.dart';
import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';

class PortfolioPage extends ConsumerWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final holdings = buildPortfolioHoldings(
      snapshot.stocks,
      snapshot.portfolioTransactions,
    );
    final currency = snapshot.session?.currency ?? 'BDT';
    final backendSummary = snapshot.portfolioSummary;
    final equityValue =
        asDouble(backendSummary?['current_equity_value']) > 0
            ? asDouble(backendSummary?['current_equity_value'])
            : holdings.fold<double>(0, (sum, row) => sum + row.marketValue);
    final costBasis = asDouble(backendSummary?['active_cost_basis']) > 0
        ? asDouble(backendSummary?['active_cost_basis'])
        : holdings.fold<double>(0, (sum, row) => sum + row.cost);
    final dividend = asDouble(backendSummary?['dividend_income']);
    final returnPercent = asDouble(backendSummary?['return_percent']);
    final cash = snapshot.accounts
        .where(_isBrokerAccount)
        .fold<double>(0, (sum, row) => sum + asDouble(row['balance']));
    final total = equityValue + cash;
    final cashPercent = total <= 0 ? 0.0 : cash / total;
    final equityPercent = total <= 0 ? 0.0 : equityValue / total;

    return RefreshIndicator(
      onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(
            title: Text('Portfolio'),
            pinned: true,
            automaticallyImplyLeading: false,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList.list(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Allocation',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _PortfolioMetric(
                                label: 'Stocks',
                                value: _percent(equityPercent),
                                subValue: money(equityValue, currency: currency),
                              ),
                            ),
                            Expanded(
                              child: _PortfolioMetric(
                                label: 'Cash',
                                value: _percent(cashPercent),
                                subValue: money(cash, currency: currency),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _PortfolioMetric(
                                label: 'Cost',
                                value: money(costBasis, currency: currency),
                              ),
                            ),
                            Expanded(
                              child: _PortfolioMetric(
                                label: 'Dividend',
                                value: money(dividend, currency: currency),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Row(
                            children: [
                              Expanded(
                                flex: (equityPercent * 100).round().clamp(1, 100).toInt(),
                                child: Container(
                                  height: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              Expanded(
                                flex: (cashPercent * 100).round().clamp(1, 100).toInt(),
                                child: Container(
                                  height: 12,
                                  color: Theme.of(context).colorScheme.tertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          money(total, currency: currency),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        Text('Total portfolio value',
                            style: Theme.of(context).textTheme.bodySmall),
                        if (returnPercent != 0)
                          Text('Return ${returnPercent.toStringAsFixed(1)}%',
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _showAddHoldingSheet(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add holding'),
                ),
                const SizedBox(height: 16),
                if (holdings.isEmpty)
                  const EmptyPanel(
                    icon: Icons.show_chart,
                    title: 'No holdings cached',
                    body: 'Sync stock transactions from the web app to review portfolio weight here.',
                  )
                else
                  ...holdings.map((holding) {
                    final weight = equityValue <= 0
                        ? 0.0
                        : holding.marketValue / (equityValue + cash);
                    final gain = holding.marketValue - holding.cost;
                    final gainPercent = holding.cost <= 0 ? 0.0 : gain / holding.cost;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFFE0F2FE),
                                    foregroundColor: const Color(0xFF0369A1),
                                    child: Text(
                                      holding.symbol.characters.first.toUpperCase(),
                                      style: const TextStyle(fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          holding.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                        ),
                                        Text('${holding.quantity.toStringAsFixed(2)} shares'),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        money(holding.marketValue,
                                            currency: holding.currency),
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      Text(_percent(weight)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  minHeight: 9,
                                  value: weight.clamp(0, 1),
                                  backgroundColor: const Color(0xFFE2E8F0),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _PortfolioMetric(
                                      label: 'Cost',
                                      value: money(holding.cost,
                                          currency: holding.currency),
                                    ),
                                  ),
                                  Expanded(
                                    child: _PortfolioMetric(
                                      label: 'Gain',
                                      value: _percent(gainPercent),
                                      danger: gain < 0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddHoldingSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddHoldingSheet(),
    );
  }
}

class _AddHoldingSheet extends ConsumerStatefulWidget {
  const _AddHoldingSheet();

  @override
  ConsumerState<_AddHoldingSheet> createState() => _AddHoldingSheetState();
}

class _AddHoldingSheetState extends ConsumerState<_AddHoldingSheet> {
  final _formKey = GlobalKey<FormState>();
  final _symbol = TextEditingController();
  final _name = TextEditingController();
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _symbol.dispose();
    _name.dispose();
    _quantity.dispose();
    _price.dispose();
    _notes.dispose();
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add holding',
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
                controller: _symbol,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Symbol',
                  prefixIcon: Icon(Icons.tag_outlined),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Enter symbol' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Company name',
                  prefixIcon: Icon(Icons.business_outlined),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Enter company name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  prefixIcon: Icon(Icons.format_list_numbered),
                ),
                validator: _positiveNumber,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Buy price',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: _positiveNumber,
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
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: const Text('Save holding'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _positiveNumber(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || parsed <= 0 ? 'Enter a valid amount' : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    await ref.read(appControllerProvider.notifier).addStockHolding(
          symbol: _symbol.text.trim(),
          name: _name.text.trim(),
          quantity: double.parse(_quantity.text),
          price: double.parse(_price.text),
          notes: _notes.text,
        );
    if (mounted) Navigator.of(context).pop();
  }
}

bool _isBrokerAccount(Map<String, dynamic> row) {
  final raw = row['raw_json'] as String? ?? '';
  return raw.contains('"account_subtype":"stock_broker"') ||
      raw.contains('"account_subtype": "stock_broker"');
}

String _percent(double value) => '${(value * 100).toStringAsFixed(1)}%';

class _PortfolioMetric extends StatelessWidget {
  const _PortfolioMetric({
    required this.label,
    required this.value,
    this.subValue,
    this.danger = false,
  });

  final String label;
  final String value;
  final String? subValue;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: danger ? Colors.red.shade700 : null,
              ),
        ),
        if (subValue != null) Text(subValue!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
