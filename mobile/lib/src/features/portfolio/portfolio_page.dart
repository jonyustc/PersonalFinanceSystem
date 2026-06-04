import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../dashboard/dashboard_page.dart';

class PortfolioPage extends ConsumerWidget {
  const PortfolioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) return const Center(child: CircularProgressIndicator());

    final holdings = _buildHoldings(snapshot);
    final currency = snapshot.session?.currency ?? 'BDT';
    final equityValue =
        holdings.fold<double>(0, (sum, row) => sum + row.marketValue);
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
                      ],
                    ),
                  ),
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
}

class _Holding {
  _Holding({
    required this.id,
    required this.symbol,
    required this.name,
    required this.currency,
    required this.lastPrice,
  });

  final String id;
  final String symbol;
  final String name;
  final String currency;
  final double lastPrice;
  double quantity = 0;
  double cost = 0;

  double get marketValue => quantity * lastPrice;
}

List<_Holding> _buildHoldings(AppSnapshot snapshot) {
  final byId = <String, _Holding>{
    for (final stock in snapshot.stocks)
      stock['id'] as String: _Holding(
        id: stock['id'] as String,
        symbol: stock['symbol'] as String? ?? 'S',
        name: stock['name'] as String? ?? 'Stock',
        currency: stock['currency'] as String? ?? 'BDT',
        lastPrice: asDouble(stock['last_price']),
      ),
  };

  for (final row in snapshot.portfolioTransactions) {
    final stockId = row['stock_id'] as String?;
    if (stockId == null) continue;
    final embeddedStock = _decodeMap(row['stock_json']);
    final holding = byId.putIfAbsent(
      stockId,
      () => _Holding(
        id: stockId,
        symbol: embeddedStock['symbol'] as String? ?? 'S',
        name: embeddedStock['name'] as String? ?? 'Stock',
        currency: embeddedStock['currency'] as String? ?? 'BDT',
        lastPrice: asDouble(embeddedStock['last_price'] ?? row['price']),
      ),
    );
    final quantity = asDouble(row['quantity']);
    final cost = asDouble(row['total_amount']);
    switch (row['txn_type']) {
      case 'buy':
        holding.quantity += quantity;
        holding.cost += cost;
      case 'sell':
        holding.quantity -= quantity;
        holding.cost -= cost;
    }
  }

  return byId.values.where((row) => row.quantity > 0).toList()
    ..sort((a, b) => b.marketValue.compareTo(a.marketValue));
}

bool _isBrokerAccount(Map<String, dynamic> row) {
  final raw = _decodeMap(row['raw_json']);
  return raw['account_subtype'] == 'stock_broker';
}

Map<String, dynamic> _decodeMap(Object? value) {
  if (value is! String || value.isEmpty) return {};
  final decoded = jsonDecode(value);
  if (decoded is Map) return decoded.cast<String, dynamic>();
  return {};
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
