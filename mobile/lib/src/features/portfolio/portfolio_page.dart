import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/metric_grid.dart';
import '../../widgets/money_text.dart';
import '../../widgets/stat_card.dart';
import '../dashboard/dashboard_page.dart';

enum _PortfolioTab { dashboard, holding, trade, dividend, market }

class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage> {
  _PortfolioTab _tab = _PortfolioTab.dashboard;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currency = snapshot.session?.currency ?? 'BDT';
    final summary = _effectivePortfolioSummary(
      snapshot.portfolioSummary ?? const <String, dynamic>{},
      snapshot.stocks,
      snapshot.portfolioTransactions,
      snapshot.accounts,
    );
    final brokerAccounts = _brokerAccounts(summary, snapshot.accounts);
    final holdings = _holdings(summary);

    return Scaffold(
      floatingActionButton: _tab == _PortfolioTab.trade
          ? FloatingActionButton(
              onPressed: () => _showTradeEditor(),
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.read(appControllerProvider.notifier).syncNow(),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              sliver: SliverList.list(
                children: [
                  _PortfolioTabs(
                    selected: _tab,
                    onChanged: (tab) => setState(() => _tab = tab),
                  ),
                  const SizedBox(height: 16),
                  switch (_tab) {
                    _PortfolioTab.dashboard => _DashboardView(
                      summary: summary,
                      brokerAccounts: brokerAccounts,
                      currency: currency,
                    ),
                    _PortfolioTab.holding => _HoldingView(
                      summary: summary,
                      holdings: holdings,
                      currency: currency,
                    ),
                    _PortfolioTab.trade => _TradeView(
                      transactions: snapshot.portfolioTransactions,
                      stocks: snapshot.stocks,
                      brokerAccounts: brokerAccounts,
                      onAdd: () => _showTradeEditor(),
                      onEdit: _showTradeEditor,
                      onDelete: _confirmDeleteTrade,
                    ),
                    _PortfolioTab.dividend => _DividendView(
                      summary: summary,
                      currency: currency,
                    ),
                    _PortfolioTab.market => _MarketView(
                      stocks: snapshot.stocks,
                      defaultCurrency: currency,
                      onRefreshPrices: () => ref
                          .read(appControllerProvider.notifier)
                          .refreshStockPrices(),
                      onSearchDseStock: (query) => ref
                          .read(appControllerProvider.notifier)
                          .searchDseStocks(query),
                      onSaveStock:
                          ({
                            id,
                            required name,
                            required symbol,
                            exchange,
                            currency,
                            required lastPrice,
                          }) => ref
                              .read(appControllerProvider.notifier)
                              .saveStock(
                                id: id,
                                name: name,
                                symbol: symbol,
                                exchange: exchange,
                                currency: currency,
                                lastPrice: lastPrice,
                              ),
                    ),
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTradeEditor([Map<String, dynamic>? transaction]) async {
    final snapshot = ref.read(appControllerProvider).asData?.value;
    if (snapshot == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TradeEditorSheet(
        initial: transaction,
        stocks: snapshot.stocks,
        transactions: snapshot.portfolioTransactions,
        brokerAccounts: _brokerAccounts(
          snapshot.portfolioSummary ?? const <String, dynamic>{},
          snapshot.accounts,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTrade(Map<String, dynamic> transaction) async {
    final stock = _stockFromTransaction(transaction);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete stock transaction?'),
        content: Text(
          'Delete ${transaction['txn_type']} ${stock['name'] ?? ''}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(appControllerProvider.notifier)
        .deletePortfolioTransaction(transaction['id'] as String);
  }
}

class _PortfolioTabs extends StatelessWidget {
  const _PortfolioTabs({required this.selected, required this.onChanged});

  final _PortfolioTab selected;
  final ValueChanged<_PortfolioTab> onChanged;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      _PortfolioTab.dashboard,
      _PortfolioTab.holding,
      _PortfolioTab.trade,
      _PortfolioTab.dividend,
      _PortfolioTab.market,
    ];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final active = selected == tab;
          return ChoiceChip(
            selected: active,
            label: Text(_tabLabel(tab)),
            avatar: Icon(_tabIcon(tab), size: 18),
            onSelected: (_) => onChanged(tab),
            labelStyle: TextStyle(
              fontWeight: FontWeight.w800,
              color: active
                  ? Theme.of(context).colorScheme.onPrimary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            selectedColor: Theme.of(context).colorScheme.primary,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          );
        },
      ),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    required this.summary,
    required this.brokerAccounts,
    required this.currency,
  });

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> brokerAccounts;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final profitLoss = _num(summary['overall_profit_loss']);
    final cash = _num(summary['cash_balance']);
    return Column(
      children: [
        MetricGrid(
          children: [
            StatCard(
              label: 'Portfolio',
              amount: _num(summary['total_portfolio_value']),
              currency: currency,
              icon: Icons.trending_up,
            ),
            StatCard(
              label: 'Broker cash',
              amount: cash,
              currency: currency,
              icon: Icons.account_balance_wallet_outlined,
              amountColor: cash < 0
                  ? AppColors.amount(context, positive: false)
                  : null,
            ),
            StatCard(
              label: 'Equity value',
              amount: _num(summary['current_equity_value']),
              currency: currency,
              icon: Icons.paid_outlined,
            ),
            StatCard(
              label: 'Profit / Loss',
              amount: profitLoss,
              currency: currency,
              icon: Icons.monetization_on_outlined,
              signed: true,
              amountColor: AppColors.amount(context, positive: profitLoss >= 0),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        _Panel(
          title: 'Portfolio Snapshot',
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.8,
            children: [
              _MiniMetric(
                'Deposited',
                money(_num(summary['invested_capital']), currency: currency),
              ),
              _MiniMetric(
                'Cost Basis',
                money(_num(summary['active_cost_basis']), currency: currency),
              ),
              _MiniMetric(
                'Dividend',
                money(_num(summary['dividend_income']), currency: currency),
              ),
              _MiniMetric(
                'Return',
                '${_num(summary['return_percent']).toStringAsFixed(1)}%',
              ),
              _MiniMetric(
                'CAGR',
                '${_num(summary['cagr_percent']).toStringAsFixed(1)}%',
              ),
            ],
          ),
        ),
        if (brokerAccounts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Panel(
            title: 'Broker Accounts',
            child: Column(
              children: brokerAccounts.map((account) {
                return _ListAmountRow(
                  title: account['name'] as String? ?? 'Broker',
                  amount: money(
                    _num(account['balance']),
                    currency: account['currency'] as String? ?? currency,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _HoldingView extends StatelessWidget {
  const _HoldingView({
    required this.summary,
    required this.holdings,
    required this.currency,
  });

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> holdings;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final total = _num(summary['total_portfolio_value']);
    final equity = _num(summary['current_equity_value']);
    final cash = _num(summary['cash_balance']);
    final equityPercent = total == 0 ? 0.0 : equity / total * 100;
    final cashPercent = total == 0 ? 0.0 : cash / total * 100;
    final stockCountLabel =
        '${holdings.length} ${holdings.length == 1 ? 'stock' : 'stocks'}';

    return Column(
      children: [
        _HoldingAllocationSummary(
          total: total,
          equity: equity,
          cash: cash,
          equityPercent: equityPercent,
          cashPercent: cashPercent,
          stockCountLabel: stockCountLabel,
          currency: currency,
        ),
        const SizedBox(height: 16),
        if (holdings.isEmpty)
          const EmptyPanel(
            icon: Icons.show_chart,
            title: 'No holdings yet',
            body: 'Add stock transactions to build holdings.',
          )
        else
          ...holdings.map((holding) {
            final stock =
                (holding['stock'] as Map?)?.cast<String, dynamic>() ?? {};
            final marketValue = _num(holding['market_value']);
            final weight = total == 0 ? 0.0 : marketValue / total;
            final weightPercent = weight * 100;
            final unrealized = _num(holding['unrealized_profit_loss']);
            final quantity = _num(holding['quantity']);
            final invested = _num(holding['invested_amount']);
            final avgPrice = _num(holding['avg_buy_price']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Panel(
                title: stock['name'] as String? ?? 'Stock',
                trailing: money(
                  marketValue,
                  currency: stock['currency'] as String? ?? currency,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${quantity.toStringAsFixed(4)} shares at avg ${money(avgPrice, currency: stock['currency'] as String? ?? currency)}',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: weight.clamp(0, 1).toDouble(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${weightPercent.toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 2.6,
                      children: [
                        _MiniMetric(
                          'Cost',
                          money(invested, currency: currency),
                        ),
                        _MiniMetric(
                          'Unrealized',
                          money(unrealized, currency: currency),
                          danger: unrealized < 0,
                        ),
                        _MiniMetric(
                          'Gain %',
                          '${_num(holding['unrealized_percent']).toStringAsFixed(2)}%',
                        ),
                        _MiniMetric(
                          'Dividend',
                          money(
                            _num(holding['dividend_income']),
                            currency: currency,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _TradeView extends StatelessWidget {
  const _TradeView({
    required this.transactions,
    required this.stocks,
    required this.brokerAccounts,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> stocks;
  final List<Map<String, dynamic>> brokerAccounts;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add Stock Transaction'),
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Transaction List',
          child: transactions.isEmpty
              ? const Text('No stock transactions yet.')
              : Column(
                  children: transactions.map((transaction) {
                    final cashFlow = _num(transaction['cash_flow']);
                    final stock = _stockFromTransaction(transaction);
                    final positive = cashFlow >= 0;
                    final accent = AppColors.amount(
                      context,
                      positive: positive,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: AppCard(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 19,
                                  backgroundColor: accent.withValues(
                                    alpha: 0.10,
                                  ),
                                  foregroundColor: accent,
                                  child: Icon(
                                    positive
                                        ? Icons.south_west
                                        : Icons.north_east,
                                    size: 19,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_labelTxn(transaction['txn_type'] as String? ?? '')} ${stock['name'] ?? ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '${transaction['txn_date']} · ${transaction['notes'] ?? 'No note'}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${positive ? '+' : '-'}${money(cashFlow.abs(), currency: stock['currency'] as String? ?? 'BDT')}',
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w800,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => onEdit(transaction),
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Edit'),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                TextButton.icon(
                                  onPressed: () => onDelete(transaction),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  label: const Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _DividendView extends StatelessWidget {
  const _DividendView({required this.summary, required this.currency});

  final Map<String, dynamic> summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final rows = (summary['dividend_report'] as List? ?? [])
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList()
      ..sort((a, b) {
        final yearCompare = _num(b['year']).compareTo(_num(a['year']));
        if (yearCompare != 0) return yearCompare;
        return (a['stock_name'] as String? ?? '').compareTo(
          b['stock_name'] as String? ?? '',
        );
      });
    return _Panel(
      title: 'Dividend Report',
      child: rows.isEmpty
          ? const Text('No dividends recorded.')
          : Column(
              children: rows.map((row) {
                final theme = Theme.of(context);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${row['stock_name']} · ${row['year']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                (row['source'] as String? ?? 'manual')
                                    .toUpperCase(),
                                if (row['record_date'] != null)
                                  'Record ${row['record_date']}',
                                if (row['cash_dividend_percent'] != null)
                                  '${_num(row['cash_dividend_percent']).toStringAsFixed(2)}% cash',
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      MoneyText(
                        _num(row['dividend_gain']),
                        currency: currency,
                        color: AppColors.amount(context, positive: true),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _MarketView extends StatefulWidget {
  const _MarketView({
    required this.stocks,
    required this.defaultCurrency,
    required this.onRefreshPrices,
    required this.onSearchDseStock,
    required this.onSaveStock,
  });

  final List<Map<String, dynamic>> stocks;
  final String defaultCurrency;
  final Future<String> Function() onRefreshPrices;
  final Future<List<Map<String, dynamic>>> Function(String query)
  onSearchDseStock;
  final Future<void> Function({
    String? id,
    required String name,
    required String symbol,
    String? exchange,
    String? currency,
    required double lastPrice,
  })
  onSaveStock;

  @override
  State<_MarketView> createState() => _MarketViewState();
}

class _MarketViewState extends State<_MarketView> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _symbol = TextEditingController();
  final _exchange = TextEditingController();
  final _currency = TextEditingController();
  final _lastPrice = TextEditingController();
  String? _savingId;
  String? _editingId;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _currency.text = widget.defaultCurrency;
  }

  @override
  void dispose() {
    _name.dispose();
    _symbol.dispose();
    _exchange.dispose();
    _currency.dispose();
    _lastPrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          title: _editingId == null ? 'Market Stock Form' : 'Edit Market Stock',
          subtitle: 'Create stock master data and update latest market price.',
          trailing: '${widget.stocks.length} stocks',
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Stock name',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter stock name'
                      : null,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _savingId == null ? _pickDseStock : null,
                  icon: const Icon(Icons.search),
                  label: const Text('Find stock from DSE'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _symbol,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Symbol',
                          prefixIcon: Icon(Icons.tag),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter symbol'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 104,
                      child: TextFormField(
                        controller: _currency,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                        ),
                        validator: (value) =>
                            value == null || value.trim().length != 3
                            ? '3 letters'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _exchange,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Exchange',
                          prefixIcon: Icon(Icons.account_balance_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _lastPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Initial price',
                          prefixIcon: Icon(Icons.price_change_outlined),
                          helperText: 'Use Fetch DSE to update latest price.',
                        ),
                        validator: (value) {
                          final price = double.tryParse(value ?? '');
                          return price == null || price < 0
                              ? 'Enter valid price'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (_editingId != null) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _savingId == null ? _clearForm : null,
                          icon: const Icon(Icons.close),
                          label: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _savingId == 'form' ? null : _saveForm,
                        icon: _savingId == 'form'
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(_editingId == null ? Icons.add : Icons.save),
                        label: Text(
                          _savingId == 'form'
                              ? 'Saving'
                              : _editingId == null
                              ? 'Add stock'
                              : 'Update stock',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Current Market Price',
          subtitle: 'Fetch latest DSE LTP to refresh equity value and P/L.',
          trailing: '${widget.stocks.length} stocks',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _refreshing || widget.stocks.isEmpty
                    ? null
                    : _refreshPrices,
                icon: _refreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: Text(_refreshing ? 'Fetching DSE prices' : 'Fetch DSE prices'),
              ),
              const SizedBox(height: 12),
              if (widget.stocks.isEmpty)
                const EmptyPanel(
                  icon: Icons.show_chart,
                  title: 'No stock master data',
                  body: 'Use the market form above to add your first stock.',
                )
              else
                ...widget.stocks.map((stock) {
                  final price = _num(stock['last_price']);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      tileColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: CircleAvatar(
                        child: Text(
                          (stock['symbol'] as String? ?? 'S').characters.first
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(
                        stock['name'] as String? ?? 'Stock',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        [
                          stock['symbol'] as String? ?? '',
                          stock['exchange'] as String? ?? 'DSE',
                        ].where((value) => value.isNotEmpty).join(' - '),
                      ),
                      trailing: Text(
                        money(
                          price,
                          currency:
                              stock['currency'] as String? ??
                              widget.defaultCurrency,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onTap: () => _editStock(stock),
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _refreshPrices() async {
    setState(() => _refreshing = true);
    try {
      final message = await widget.onRefreshPrices();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _pickDseStock() async {
    final picked = await showDseStockPicker(
      context: context,
      search: widget.onSearchDseStock,
      initialQuery: _symbol.text,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _name.text = picked['name'] as String? ?? '';
      _symbol.text = picked['symbol'] as String? ?? '';
      _exchange.text = picked['source'] as String? ?? 'DSE';
      _currency.text = 'BDT';
      _lastPrice.text = _num(picked['last_price']).toStringAsFixed(4);
    });
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _savingId = 'form');
    try {
      await widget.onSaveStock(
        id: _editingId,
        name: _name.text,
        symbol: _symbol.text,
        exchange: _exchange.text,
        currency: _currency.text,
        lastPrice: double.parse(_lastPrice.text),
      );
      if (mounted) {
        setState(() {
          _savingId = null;
          _resetFormFields();
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingId = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _editStock(Map<String, dynamic> stock) {
    setState(() {
      _editingId = stock['id'] as String?;
      _name.text = stock['name'] as String? ?? '';
      _symbol.text = stock['symbol'] as String? ?? '';
      _exchange.text = stock['exchange'] as String? ?? '';
      _currency.text = stock['currency'] as String? ?? widget.defaultCurrency;
      _lastPrice.text = _num(stock['last_price']).toStringAsFixed(4);
    });
  }

  void _clearForm() {
    setState(_resetFormFields);
  }

  void _resetFormFields() {
    _editingId = null;
    _name.clear();
    _symbol.clear();
    _exchange.clear();
    _currency.text = widget.defaultCurrency;
    _lastPrice.clear();
  }
}

class _TradeEditorSheet extends ConsumerStatefulWidget {
  const _TradeEditorSheet({
    this.initial,
    required this.stocks,
    required this.transactions,
    required this.brokerAccounts,
  });

  final Map<String, dynamic>? initial;
  final List<Map<String, dynamic>> stocks;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> brokerAccounts;

  @override
  ConsumerState<_TradeEditorSheet> createState() => _TradeEditorSheetState();
}

class _TradeEditorSheetState extends ConsumerState<_TradeEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  final _newStockName = TextEditingController();
  final _newStockSymbol = TextEditingController();
  final _quantity = TextEditingController();
  final _price = TextEditingController();
  final _fees = TextEditingController();
  final _notes = TextEditingController();
  final _dividendPerShare = TextEditingController();
  final _taxRate = TextEditingController(text: '10');
  String _txnType = 'buy';
  String? _stockId;
  String? _brokerAccountId;
  DateTime _date = DateTime.now();
  DateTime? _recordDate;
  bool _busy = false;
  bool _loadingDividend = false;
  String? _dividendLookupMessage;
  double? _eligibleDividendQuantity;
  double? _grossDividendAmount;
  double? _taxDividendAmount;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _txnType = initial['txn_type'] as String? ?? 'buy';
      _stockId = initial['stock_id'] as String?;
      _brokerAccountId = initial['broker_account_id'] as String?;
      _quantity.text = _num(initial['quantity']) == 0
          ? ''
          : _num(initial['quantity']).toString();
      _price.text = _num(initial['price']).toString();
      _fees.text = _num(initial['fees']) == 0
          ? ''
          : _num(initial['fees']).toString();
      _notes.text = initial['notes'] as String? ?? '';
      _date =
          DateTime.tryParse(initial['txn_date'] as String? ?? '') ??
          DateTime.now();
      _recordDate = DateTime.tryParse(initial['record_date'] as String? ?? '');
    }
  }

  @override
  void dispose() {
    _newStockName.dispose();
    _newStockSymbol.dispose();
    _quantity.dispose();
    _price.dispose();
    _fees.dispose();
    _notes.dispose();
    _dividendPerShare.dispose();
    _taxRate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final needsStock =
        _txnType == 'buy' || _txnType == 'sell' || _txnType == 'income';
    final isTrade = _txnType == 'buy' || _txnType == 'sell';
    final autoFee = _defaultBrokerFee();
    final hasManualFee = _fees.text.trim().isNotEmpty;
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initial == null
                          ? 'Add Stock Transaction'
                          : 'Edit Stock Transaction',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 3.2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                children: [
                  _txnTypeButton('buy', 'Buy'),
                  _txnTypeButton('sell', 'Sell'),
                  _txnTypeButton('withdraw', 'Withdraw'),
                  _txnTypeButton('income', 'Dividend'),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _brokerAccountId,
                decoration: const InputDecoration(labelText: 'Broker account'),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('No broker account'),
                  ),
                  ...widget.brokerAccounts.map(
                    (account) => DropdownMenuItem<String>(
                      value: account['id'] as String,
                      child: Text(account['name'] as String? ?? 'Broker'),
                    ),
                  ),
                ],
                onChanged: (value) => setState(
                  () =>
                      _brokerAccountId = value?.isEmpty == true ? null : value,
                ),
              ),
              if (needsStock) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _stockId,
                  decoration: const InputDecoration(labelText: 'Stock'),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('New stock'),
                    ),
                    ...widget.stocks.map(
                      (stock) => DropdownMenuItem<String>(
                        value: stock['id'] as String,
                        child: Text('${stock['name']} (${stock['symbol']})'),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(
                      () => _stockId = value?.isEmpty == true ? null : value,
                    );
                    _fetchDividendEstimateForCurrentStock();
                  },
                ),
              ],
              if (needsStock && _stockId == null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickDseStock,
                  icon: const Icon(Icons.search),
                  label: const Text('Find stock from DSE'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _newStockName,
                  decoration: const InputDecoration(labelText: 'Stock name'),
                  validator: (value) {
                    if (!needsStock || _stockId != null) return null;
                    return value == null || value.trim().isEmpty
                        ? 'Enter stock name'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _newStockSymbol,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Symbol'),
                ),
              ],
              if (isTrade) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Quantity'),
                  onChanged: (_) => setState(() {}),
                  validator: _positiveValidator,
                ),
              ],
              if (_txnType == 'income') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _dividendPerShare,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Dividend/share',
                        ),
                        onChanged: (_) => _recalculateManualDividend(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _taxRate,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Tax %'),
                        onChanged: (_) => _recalculateManualDividend(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _DividendEstimateSummary(
                  loading: _loadingDividend,
                  message: _dividendLookupMessage,
                  eligibleQuantity: _eligibleDividendQuantity,
                  grossAmount: _grossDividendAmount,
                  taxAmount: _taxDividendAmount,
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _txnType == 'income'
                      ? 'Dividend amount'
                      : _txnType == 'withdraw'
                      ? 'Amount'
                      : 'Price/share',
                ),
                onChanged: (_) => setState(() {}),
                validator: _positiveValidator,
              ),
              if (isTrade) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _fees,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Broker fee',
                    hintText: 'Auto ${autoFee.toStringAsFixed(2)}',
                    helperText: hasManualFee
                        ? 'Manual fee overrides backend auto fee.'
                        : 'Blank uses backend auto fee: 0.4% of trade value.',
                    suffixIcon: hasManualFee
                        ? IconButton(
                            tooltip: 'Use auto fee',
                            onPressed: () => setState(() => _fees.clear()),
                            icon: const Icon(Icons.auto_fix_high_outlined),
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Text(
                  'Applied fee: ${hasManualFee ? _fees.text : autoFee.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (_txnType == 'income') ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickRecordDate,
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(
                        _recordDate == null
                            ? 'Record date'
                            : 'Record ${_formatDate(_recordDate!)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickPaymentDate,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text('Payment ${_formatDate(_date)}'),
                    ),
                  ],
                ),
              ] else
                OutlinedButton.icon(
                  onPressed: _pickPaymentDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(_formatDate(_date)),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.add),
                label: Text(
                  _busy
                      ? 'Saving...'
                      : widget.initial == null
                      ? 'Save Transaction'
                      : 'Update Transaction',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _txnTypeButton(String value, String label) {
    final active = _txnType == value;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: active
            ? null
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: active
            ? null
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: () {
        setState(() => _txnType = value);
        if (value == 'income') _fetchDividendEstimateForCurrentStock();
      },
      child: Text(label),
    );
  }

  String? _positiveValidator(String? value) {
    final parsed = double.tryParse(value ?? '');
    return parsed == null || parsed <= 0 ? 'Enter a valid amount' : null;
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickRecordDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordDate ?? _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _recordDate = picked);
      _recalculateManualDividend();
    }
  }

  Future<void> _pickDseStock() async {
    final picked = await showDseStockPicker(
      context: context,
      search: (query) => ref
          .read(appControllerProvider.notifier)
          .searchDseStocks(query),
      initialQuery: _newStockSymbol.text,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _newStockName.text = picked['name'] as String? ?? '';
      _newStockSymbol.text = picked['symbol'] as String? ?? '';
      if (_txnType != 'income') {
        _price.text = _num(picked['last_price']).toStringAsFixed(4);
      }
    });
    await _fetchDividendEstimate(
      symbol: _newStockSymbol.text,
      stockId: _stockId,
    );
  }

  Future<void> _fetchDividendEstimateForCurrentStock() async {
    if (_txnType != 'income') return;
    final symbol = _selectedStockSymbol();
    if (symbol == null || symbol.isEmpty) {
      setState(() {
        _dividendLookupMessage = 'Select a stock or find one from DSE.';
        _eligibleDividendQuantity = null;
        _grossDividendAmount = null;
        _taxDividendAmount = null;
      });
      return;
    }
    await _fetchDividendEstimate(symbol: symbol, stockId: _stockId);
  }

  Future<void> _fetchDividendEstimate({
    required String symbol,
    String? stockId,
  }) async {
    if (_txnType != 'income') return;
    setState(() {
      _loadingDividend = true;
      _dividendLookupMessage = 'Fetching DSE dividend data...';
    });
    try {
      final estimate = await ref
          .read(appControllerProvider.notifier)
          .getDseDividendEstimate(
            symbol: symbol,
            stockId: stockId,
            taxRatePercent: double.tryParse(_taxRate.text) ?? 10,
          );
      if (!mounted) return;
      setState(() {
        _loadingDividend = false;
        _applyDividendEstimate(estimate);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDividend = false;
        _dividendLookupMessage =
            'DSE dividend not found. Enter dividend/share, date, and amount manually.';
      });
    }
  }

  void _applyDividendEstimate(Map<String, dynamic> estimate) {
    final found = estimate['found'] == true;
    final recordDate = DateTime.tryParse(estimate['record_date'] as String? ?? '');
    final paymentDate = DateTime.tryParse(estimate['payment_date'] as String? ?? '');
    final dividendPerShare = _num(estimate['dividend_per_share']);
    final netAmount = _num(estimate['net_amount']);
    _eligibleDividendQuantity = _num(estimate['eligible_quantity']);
    _grossDividendAmount = _num(estimate['gross_amount']);
    _taxDividendAmount = _num(estimate['tax_amount']);

    if (found && recordDate != null && dividendPerShare > 0) {
      _recordDate = recordDate;
      if (widget.initial == null && paymentDate != null) _date = paymentDate;
      _dividendPerShare.text = dividendPerShare.toStringAsFixed(4);
      if (netAmount > 0) _price.text = netAmount.toStringAsFixed(2);
      _dividendLookupMessage =
          'DSE record ${_formatDate(recordDate)}. Payment date stays editable for broker cash.';
      _notes.text = _buildDividendNote();
      return;
    }

    if (found && dividendPerShare > 0) {
      if (widget.initial == null && paymentDate != null) _date = paymentDate;
      _dividendPerShare.text = dividendPerShare.toStringAsFixed(4);
      _dividendLookupMessage =
          estimate['message'] as String? ??
          'DSE declaration found. Enter record date to calculate eligible holding.';
      return;
    }

    _dividendLookupMessage =
        estimate['message'] as String? ??
        'DSE dividend not found. Enter dividend/share, date, and amount manually.';
  }

  void _recalculateManualDividend() {
    if (_txnType != 'income') return;
    final dividendPerShare = double.tryParse(_dividendPerShare.text);
    if (dividendPerShare == null || dividendPerShare <= 0) {
      setState(() {
        _eligibleDividendQuantity = null;
        _grossDividendAmount = null;
        _taxDividendAmount = null;
      });
      return;
    }
    final quantity = _quantityOnRecordDate();
    final taxRate = double.tryParse(_taxRate.text) ?? 0;
    final gross = quantity * dividendPerShare;
    final tax = gross * taxRate / 100;
    final net = gross - tax;
    setState(() {
      _eligibleDividendQuantity = quantity;
      _grossDividendAmount = gross;
      _taxDividendAmount = tax;
      if (net > 0) _price.text = net.toStringAsFixed(2);
      _dividendLookupMessage =
          _recordDate == null
              ? 'Enter record date to calculate eligible holding.'
              : 'Calculated from holding on ${_formatDate(_recordDate!)}. Amount remains editable.';
      _notes.text = _buildDividendNote();
    });
  }

  double _quantityOnRecordDate() {
    final stockId = _stockId;
    final recordDate = _recordDate;
    if (stockId == null || stockId.isEmpty || recordDate == null) return 0;
    var quantity = 0.0;
    final sorted = [...widget.transactions]..sort((a, b) {
      final aDate = a['txn_date'] as String? ?? '';
      final bDate = b['txn_date'] as String? ?? '';
      return aDate.compareTo(bDate);
    });
    for (final transaction in sorted) {
      if (transaction['stock_id'] != stockId) continue;
      final transactionDate = DateTime.tryParse(transaction['txn_date'] as String? ?? '');
      if (transactionDate == null || transactionDate.isAfter(recordDate)) continue;
      final type = transaction['txn_type'] as String? ?? '';
      if (type == 'buy') quantity += _num(transaction['quantity']);
      if (type == 'sell') quantity -= _num(transaction['quantity']);
    }
    return quantity < 0 ? 0 : quantity;
  }

  String? _selectedStockSymbol() {
    final stockId = _stockId;
    if (stockId != null && stockId.isNotEmpty) {
      for (final stock in widget.stocks) {
        if (stock['id'] == stockId) {
          return (stock['symbol'] as String?)?.trim().toUpperCase();
        }
      }
    }
    return _newStockSymbol.text.trim().isEmpty
        ? null
        : _newStockSymbol.text.trim().toUpperCase();
  }

  String _formatDate(DateTime date) {
    return date.toIso8601String().substring(0, 10);
  }

  String _buildDividendNote() {
    final dps = double.tryParse(_dividendPerShare.text) ?? 0;
    final quantity = _eligibleDividendQuantity ?? 0;
    final gross = _grossDividendAmount ?? 0;
    final tax = _taxDividendAmount ?? 0;
    if (dps <= 0 || quantity <= 0) return _notes.text;
    return 'Dividend DPS ${dps.toStringAsFixed(4)}, qty ${quantity.toStringAsFixed(4)}, gross ${gross.toStringAsFixed(2)}, tax ${tax.toStringAsFixed(2)}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(appControllerProvider.notifier)
          .savePortfolioTransaction(
            id: widget.initial?['id'] as String?,
            txnType: _txnType,
            stockId: _stockId,
            brokerAccountId: _brokerAccountId,
            newStockName: _newStockName.text,
            newStockSymbol: _newStockSymbol.text,
            quantity: double.tryParse(_quantity.text) ?? 0,
            price: double.parse(_price.text),
            fees: _manualBrokerFee(),
            date: _date,
            recordDate: _recordDate,
            notes: _notes.text,
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

  double _defaultBrokerFee() {
    if (_txnType != 'buy' && _txnType != 'sell') return 0;
    final quantity = double.tryParse(_quantity.text) ?? 0;
    final price = double.tryParse(_price.text) ?? 0;
    return quantity * price * 0.004;
  }

  double? _manualBrokerFee() {
    final trimmed = _fees.text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }
}

Future<Map<String, dynamic>?> showDseStockPicker({
  required BuildContext context,
  required Future<List<Map<String, dynamic>>> Function(String query) search,
  String? initialQuery,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _DseStockPicker(search: search, initialQuery: initialQuery),
  );
}

class _DseStockPicker extends StatefulWidget {
  const _DseStockPicker({required this.search, this.initialQuery});

  final Future<List<Map<String, dynamic>>> Function(String query) search;
  final String? initialQuery;

  @override
  State<_DseStockPicker> createState() => _DseStockPickerState();
}

class _DseStockPickerState extends State<_DseStockPicker> {
  final _query = TextEditingController();
  Future<List<Map<String, dynamic>>>? _results;

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery ?? '';
    if (_query.text.trim().isNotEmpty) {
      _runSearch();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Find DSE stock',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _query,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'DSE trading code',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  onPressed: _runSearch,
                  icon: const Icon(Icons.arrow_forward),
                ),
              ),
              onSubmitted: (_) => _runSearch(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 360,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _results,
                builder: (context, snapshot) {
                  if (_results == null) {
                    return const Center(
                      child: Text('Search by DSE trading code.'),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text(snapshot.error.toString()));
                  }
                  final rows = snapshot.data ?? const [];
                  if (rows.isEmpty) {
                    return const Center(child: Text('No DSE stocks found.'));
                  }
                  return ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            (row['symbol'] as String? ?? 'S')
                                .characters
                                .first
                                .toUpperCase(),
                          ),
                        ),
                        title: Text(
                          row['name'] as String? ?? row['symbol'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text('${row['symbol']} - ${row['source'] ?? 'DSE'}'),
                        trailing: Text(
                          money(_num(row['last_price']), currency: 'BDT'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onTap: () => Navigator.of(context).pop(row),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _runSearch() {
    setState(() {
      _results = widget.search(_query.text.trim().toUpperCase());
    });
  }
}

class _DividendEstimateSummary extends StatelessWidget {
  const _DividendEstimateSummary({
    required this.loading,
    required this.message,
    required this.eligibleQuantity,
    required this.grossAmount,
    required this.taxAmount,
  });

  final bool loading;
  final String? message;
  final double? eligibleQuantity;
  final double? grossAmount;
  final double? taxAmount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: loading
          ? const Row(
              children: [
                SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Fetching DSE dividend data'),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message != null)
                  Text(
                    message!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (eligibleQuantity != null ||
                    grossAmount != null ||
                    taxAmount != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      if (eligibleQuantity != null)
                        Text('Qty ${eligibleQuantity!.toStringAsFixed(4)}'),
                      if (grossAmount != null)
                        Text('Gross ${grossAmount!.toStringAsFixed(2)}'),
                      if (taxAmount != null)
                        Text('Tax ${taxAmount!.toStringAsFixed(2)}'),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric(this.label, this.value, {this.danger = false});

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: danger ? AppColors.amount(context, positive: false) : null,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ListAmountRow extends StatelessWidget {
  const _ListAmountRow({required this.title, required this.amount});

  final String title;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            amount,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _HoldingAllocationSummary extends StatelessWidget {
  const _HoldingAllocationSummary({
    required this.total,
    required this.equity,
    required this.cash,
    required this.equityPercent,
    required this.cashPercent,
    required this.stockCountLabel,
    required this.currency,
  });

  final double total;
  final double equity;
  final double cash;
  final double equityPercent;
  final double cashPercent;
  final String stockCountLabel;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: 'Portfolio value',
                  value: money(total, currency: currency),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  stockCountLabel,
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: (equityPercent / 100).clamp(0, 1).toDouble(),
              backgroundColor: scheme.tertiary.withValues(alpha: 0.30),
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: 'Stocks',
                  value: '${equityPercent.toStringAsFixed(1)}%',
                  subValue: money(equity, currency: currency),
                  markerColor: scheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _SummaryMetric(
                  label: 'Cash',
                  value: '${cashPercent.toStringAsFixed(2)}%',
                  subValue: money(cash, currency: currency),
                  markerColor: scheme.tertiary,
                  danger: cash < 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    this.subValue,
    this.markerColor,
    this.danger = false,
  });

  final String label;
  final String value;
  final String? subValue;
  final Color? markerColor;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final valueColor = danger ? AppColors.amount(context, positive: false) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (markerColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(color: muted),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (subValue != null)
          Text(
            subValue!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: valueColor ?? muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

List<Map<String, dynamic>> _holdings(Map<String, dynamic> summary) {
  return (summary['holdings'] as List? ?? [])
      .whereType<Map>()
      .map((row) => row.cast<String, dynamic>())
      .toList()
    ..sort(
      (a, b) => _num(b['market_value']).compareTo(_num(a['market_value'])),
    );
}

Map<String, dynamic> _effectivePortfolioSummary(
  Map<String, dynamic> backendSummary,
  List<Map<String, dynamic>> stocks,
  List<Map<String, dynamic>> transactions,
  List<Map<String, dynamic>> accounts,
) {
  final hasBackendHoldings = (backendSummary['holdings'] as List? ?? []).isNotEmpty;
  final hasBackendValue =
      _num(backendSummary['current_equity_value']) != 0 ||
      _num(backendSummary['total_portfolio_value']) != 0;
  if (hasBackendHoldings || hasBackendValue || transactions.isEmpty) {
    return backendSummary;
  }

  final stockById = <String, Map<String, dynamic>>{
    for (final stock in stocks)
      if (stock['id'] != null) stock['id'].toString(): stock,
  };
  final holdingState = <String, _LocalHoldingState>{};
  var dividendIncome = 0.0;
  var principal = 0.0;
  var cashBalance = 0.0;

  for (final transaction in transactions.reversed) {
    final txnType = transaction['txn_type'] as String? ?? '';
    final totalAmount = _num(transaction['total_amount']);
    cashBalance += _num(transaction['cash_flow']);
    if (txnType == 'deposit') principal += totalAmount;
    if (txnType == 'income') {
      dividendIncome += totalAmount;
      continue;
    }

    final stockId = transaction['stock_id'] as String?;
    if (stockId == null || stockId.isEmpty) continue;
    final embeddedStock = _stockFromTransaction(transaction);
    final stock = stockById[stockId] ?? embeddedStock;
    final state = holdingState.putIfAbsent(
      stockId,
      () => _LocalHoldingState(stockId: stockId, stock: stock),
    );
    if (state.stock.isEmpty && stock.isNotEmpty) state.stock = stock;

    final quantity = _num(transaction['quantity']);
    final price = _num(transaction['price']);
    final shareValue = quantity * price;
    if (price > 0) state.lastTradePrice = price;
    if (txnType == 'buy') {
      state.quantity += quantity;
      state.cost += shareValue;
    } else if (txnType == 'sell' && state.quantity > 0) {
      final soldQuantity = quantity.clamp(0, state.quantity).toDouble();
      final removedCost = state.cost / state.quantity * soldQuantity;
      state.realized += totalAmount - removedCost;
      state.cost -= removedCost;
      state.quantity -= soldQuantity;
    }
  }

  final holdings = <Map<String, dynamic>>[];
  var activeCostBasis = 0.0;
  var equityValue = 0.0;
  var realized = 0.0;
  for (final state in holdingState.values) {
    if (state.quantity <= 0) {
      realized += state.realized;
      continue;
    }
    final stock = state.stock;
    final stockLastPrice = _num(stock['last_price']);
    final lastPrice = stockLastPrice == 0 ? state.lastTradePrice : stockLastPrice;
    final avgBuyPrice = state.quantity == 0 ? 0.0 : state.cost / state.quantity;
    final marketValue = state.quantity * lastPrice;
    final unrealized = marketValue - state.cost;
    activeCostBasis += state.cost;
    equityValue += marketValue;
    realized += state.realized;
    holdings.add({
      'stock': {
        'id': state.stockId,
        'symbol': stock['symbol'] as String? ?? 'STOCK',
        'name': stock['name'] as String? ?? 'Stock',
        'currency': stock['currency'] as String? ?? 'BDT',
        'last_price': lastPrice,
      },
      'quantity': state.quantity,
      'avg_buy_price': avgBuyPrice,
      'invested_amount': state.cost,
      'market_value': marketValue,
      'unrealized_profit_loss': unrealized,
      'unrealized_percent': state.cost == 0 ? 0 : unrealized / state.cost * 100,
      'realized_profit_loss': state.realized,
      'dividend_income': 0,
      'total_profit_loss': unrealized + state.realized,
    });
  }

  holdings.sort(
    (a, b) => _num(b['market_value']).compareTo(_num(a['market_value'])),
  );
  final brokerAccounts = _brokerAccounts(const <String, dynamic>{}, accounts);
  final brokerCash = brokerAccounts.fold<double>(
    0,
    (sum, account) => sum + _num(account['balance']),
  );
  final fallbackCash = cashBalance == 0 ? brokerCash : cashBalance;
  final overallProfitLoss = realized + (equityValue - activeCostBasis);
  return {
    ...backendSummary,
    'total_principal_investment': principal,
    'invested_capital': principal,
    'active_cost_basis': activeCostBasis,
    'current_equity_value': equityValue,
    'unrealized_gain_loss': equityValue - activeCostBasis,
    'cash_balance': fallbackCash,
    'total_portfolio_value': equityValue + fallbackCash,
    'total_realized_capital_gain_loss': realized,
    'dividend_income': dividendIncome,
    'total_realized_profit': realized,
    'overall_profit_loss': overallProfitLoss,
    'return_percent': principal == 0 ? 0 : overallProfitLoss / principal * 100,
    'cagr_percent': 0,
    'broker_accounts': brokerAccounts,
    'holdings': holdings,
  };
}

class _LocalHoldingState {
  _LocalHoldingState({required this.stockId, required this.stock});

  final String stockId;
  Map<String, dynamic> stock;
  double quantity = 0;
  double cost = 0;
  double realized = 0;
  double lastTradePrice = 0;
}

List<Map<String, dynamic>> _brokerAccounts(
  Map<String, dynamic> summary,
  List<Map<String, dynamic>> accounts,
) {
  final summaryAccounts = (summary['broker_accounts'] as List? ?? [])
      .whereType<Map>()
      .map((row) => row.cast<String, dynamic>())
      .toList();
  if (summaryAccounts.isNotEmpty) return summaryAccounts;
  return accounts.where((account) {
    final raw = account['raw_json'] as String? ?? '';
    return raw.contains('"account_subtype":"stock_broker"') ||
        raw.contains('"account_subtype": "stock_broker"');
  }).toList();
}

Map<String, dynamic> _stockFromTransaction(Map<String, dynamic> transaction) {
  final raw = transaction['stock_json'];
  if (raw is String && raw.isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }
  final stock = transaction['stock'];
  if (stock is Map) return stock.cast<String, dynamic>();
  return {};
}

String _tabLabel(_PortfolioTab tab) {
  return switch (tab) {
    _PortfolioTab.dashboard => 'Dash',
    _PortfolioTab.holding => 'Holding',
    _PortfolioTab.trade => 'Trade',
    _PortfolioTab.dividend => 'Dividend',
    _PortfolioTab.market => 'Market',
  };
}

IconData _tabIcon(_PortfolioTab tab) {
  return switch (tab) {
    _PortfolioTab.dashboard => Icons.dashboard_outlined,
    _PortfolioTab.holding => Icons.pie_chart_outline,
    _PortfolioTab.trade => Icons.swap_vert,
    _PortfolioTab.dividend => Icons.payments_outlined,
    _PortfolioTab.market => Icons.show_chart,
  };
}

String _labelTxn(String value) {
  return switch (value) {
    'buy' => 'Buy',
    'sell' => 'Sell',
    'withdraw' => 'Withdraw',
    'income' => 'Dividend',
    _ => value,
  };
}

double _num(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
