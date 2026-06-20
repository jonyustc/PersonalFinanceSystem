import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../state/app_controller.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_card.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/metric_grid.dart';
import '../../widgets/money_text.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/stat_card.dart';
import '../dashboard/dashboard_page.dart';

enum _PortfolioTab { dashboard, holding, performance, trade, dividend, market }

class PortfolioPage extends ConsumerStatefulWidget {
  const PortfolioPage({super.key});

  @override
  ConsumerState<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends ConsumerState<PortfolioPage> {
  _PortfolioTab _tab = _PortfolioTab.dashboard;
  String? _selectedPortfolioId;
  Map<String, dynamic>? _selectedSummary;

  Future<void> _selectPortfolio(String? id) async {
    setState(() {
      _selectedPortfolioId = id;
      _selectedSummary = null;
    });
    if (id == null) return;
    final loaded = await ref
        .read(appControllerProvider.notifier)
        .loadPortfolioSummaryFor(id);
    if (!mounted || _selectedPortfolioId != id) return;
    setState(() => _selectedSummary = loaded);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(appControllerProvider).asData?.value;
    if (snapshot == null) {
      return const ListSkeleton();
    }

    final currency = snapshot.session?.currency ?? 'BDT';
    final advanced = snapshot.portfolioAdvanced;
    final portfolios = snapshot.portfolios;
    final allSummary = _effectivePortfolioSummary(
      snapshot.portfolioSummary ?? const <String, dynamic>{},
      snapshot.stocks,
      snapshot.portfolioTransactions,
      snapshot.accounts,
    );
    // When a specific portfolio is selected, prefer its live/cached summary.
    final summary = _selectedPortfolioId == null
        ? allSummary
        : (_selectedSummary ?? allSummary);
    final brokerAccounts = _brokerAccounts(summary, snapshot.accounts);
    final holdings = _holdings(summary);
    final portfolioNameById = <String, String>{
      for (final portfolio in portfolios)
        if (portfolio['id'] != null)
          portfolio['id'].toString(): portfolio['name'] as String? ?? 'Portfolio',
    };

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
                  _PortfolioHeader(
                    portfolios: portfolios,
                    selectedPortfolioId: _selectedPortfolioId,
                    advanced: advanced,
                    onSelect: _selectPortfolio,
                    onToggleAdvanced: () => ref
                        .read(appControllerProvider.notifier)
                        .setPortfolioAdvanced(!advanced),
                  ),
                  const SizedBox(height: 12),
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
                      advanced: advanced,
                    ),
                    _PortfolioTab.holding => _HoldingView(
                      summary: summary,
                      holdings: holdings,
                      currency: currency,
                      advanced: advanced,
                    ),
                    _PortfolioTab.performance => _PerformanceView(
                      portfolioId: _selectedPortfolioId,
                      advanced: advanced,
                      currency: currency,
                    ),
                    _PortfolioTab.trade => _TradeView(
                      transactions: snapshot.portfolioTransactions,
                      stocks: snapshot.stocks,
                      brokerAccounts: brokerAccounts,
                      portfolioNameById: portfolioNameById,
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
    final selectedPortfolio = snapshot.portfolios.firstWhere(
      (portfolio) => portfolio['id'] == _selectedPortfolioId,
      orElse: () => const <String, dynamic>{},
    );
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
        initialBrokerAccountId:
            selectedPortfolio['broker_account_id'] as String?,
      ),
    );
  }

  Future<void> _confirmDeleteTrade(Map<String, dynamic> transaction) async {
    final stock = _stockFromTransaction(transaction);
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete stock transaction?',
      message:
          'Delete ${transaction['txn_type']} ${stock['name'] ?? ''}? '
          'This cannot be undone.',
      confirmLabel: 'Delete',
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (!confirmed) return;
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
      _PortfolioTab.performance,
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
    required this.advanced,
  });

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> brokerAccounts;
  final String currency;
  final bool advanced;

  @override
  Widget build(BuildContext context) {
    final totalReturn = _num(summary['total_return']);
    final realized = _num(summary['total_realized_profit']);
    final unrealized = _num(
      summary['total_unrealized_gain'] ?? summary['unrealized_gain_loss'],
    );
    final dividend = _num(
      summary['total_dividend_income'] ?? summary['dividend_income'],
    );
    final roi = _num(summary['roi_percent']);
    return Column(
      children: [
        MetricGrid(
          children: [
            StatCard(
              label: 'Total Investment',
              amount: _num(summary['total_investment']),
              currency: currency,
              icon: Icons.account_balance_wallet_outlined,
            ),
            StatCard(
              label: 'Current Value',
              amount: _num(summary['current_equity_value']),
              currency: currency,
              icon: Icons.paid_outlined,
            ),
            StatCard(
              label: 'Total Return',
              amount: totalReturn,
              currency: currency,
              icon: Icons.trending_up,
              signed: true,
              amountColor: AppColors.amount(context, positive: totalReturn >= 0),
            ),
            StatCard(
              label: 'Portfolio Value',
              amount: _num(summary['total_portfolio_value']),
              currency: currency,
              icon: Icons.speed_outlined,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _Panel(
          title: 'Returns',
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.8,
            children: [
              _MiniMetric(
                'Realized Gain',
                money(realized, currency: currency),
                danger: realized < 0,
              ),
              _MiniMetric(
                'Unrealized Gain',
                money(unrealized, currency: currency),
                danger: unrealized < 0,
              ),
              _MiniMetric('Dividend Income', money(dividend, currency: currency)),
              _MiniMetric(
                'ROI',
                '${roi >= 0 ? '+' : ''}${roi.toStringAsFixed(2)}%',
                danger: roi < 0,
              ),
            ],
          ),
        ),
        if (advanced) ...[
          const SizedBox(height: AppSpacing.md),
          _Panel(
            title: 'Advanced Investor Analytics',
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.8,
              children: [
                _MiniMetric(
                  'Net Capital Invested',
                  money(_num(summary['net_capital_invested']), currency: currency),
                ),
                _MiniMetric(
                  'Capital Recovery',
                  '${_num(summary['capital_recovery_percent']).toStringAsFixed(1)}%',
                ),
                _MiniMetric(
                  'Wealth Multiple',
                  '${_num(summary['wealth_multiple']).toStringAsFixed(2)}×',
                ),
                _MiniMetric(
                  'Withdrawals',
                  money(_num(summary['total_withdrawals']), currency: currency),
                ),
              ],
            ),
          ),
        ],
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
                'Cash',
                money(_num(summary['cash_balance']), currency: currency),
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
    required this.advanced,
  });

  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> holdings;
  final String currency;
  final bool advanced;

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
            final realized = _num(holding['realized_profit_loss']);
            final totalReturn = _num(
              holding['total_return'] ?? holding['total_profit_loss'],
            );
            final brokerCost = _num(
              holding['broker_cost_basis'] ?? holding['avg_buy_price'],
            );
            final marketPrice = _num(
              holding['market_price'] ?? holding['stock']?['last_price'],
            );
            final stockCurrency = stock['currency'] as String? ?? currency;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Panel(
                title: stock['name'] as String? ?? 'Stock',
                trailing: money(marketValue, currency: stockCurrency),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${quantity.toStringAsFixed(4)} shares · Broker cost ${money(brokerCost, currency: stockCurrency)}',
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
                          'Market Price',
                          money(marketPrice, currency: stockCurrency),
                        ),
                        _MiniMetric(
                          'Unrealized',
                          money(unrealized, currency: currency),
                          danger: unrealized < 0,
                        ),
                        _MiniMetric(
                          'Gain %',
                          '${_num(holding['unrealized_percent']).toStringAsFixed(2)}%',
                          danger: unrealized < 0,
                        ),
                        _MiniMetric(
                          'Realized',
                          money(realized, currency: currency),
                          danger: realized < 0,
                        ),
                        _MiniMetric(
                          'Dividend',
                          money(
                            _num(holding['dividend_income']),
                            currency: currency,
                          ),
                        ),
                        _MiniMetric(
                          'Total Return',
                          money(totalReturn, currency: currency),
                          danger: totalReturn < 0,
                        ),
                      ],
                    ),
                    if (advanced) ...[
                      const SizedBox(height: 8),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        childAspectRatio: 2.6,
                        children: [
                          _MiniMetric(
                            'Effective Cost',
                            money(
                              _num(holding['effective_cost_basis']),
                              currency: stockCurrency,
                            ),
                          ),
                          _MiniMetric(
                            'Net Capital',
                            money(
                              _num(holding['net_capital_invested']),
                              currency: currency,
                            ),
                          ),
                          _MiniMetric(
                            'Capital Recovery',
                            '${_num(holding['capital_recovery_percent']).toStringAsFixed(1)}%',
                          ),
                          _MiniMetric(
                            'Wealth Multiple',
                            '${_num(holding['wealth_multiple']).toStringAsFixed(2)}×',
                          ),
                        ],
                      ),
                    ],
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
    required this.portfolioNameById,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> stocks;
  final List<Map<String, dynamic>> brokerAccounts;
  final Map<String, String> portfolioNameById;
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
                    final portfolioId = transaction['portfolio_id']?.toString();
                    final portfolioName =
                        (portfolioId != null
                            ? portfolioNameById[portfolioId]
                            : null) ??
                        'Unassigned';
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
                                      const SizedBox(height: 4),
                                      _PortfolioBadge(label: portfolioName),
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
    this.initialBrokerAccountId,
  });

  final Map<String, dynamic>? initial;
  final List<Map<String, dynamic>> stocks;
  final List<Map<String, dynamic>> transactions;
  final List<Map<String, dynamic>> brokerAccounts;
  final String? initialBrokerAccountId;

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
    } else {
      // New trade: default the portfolio (broker account) to the selected one.
      _brokerAccountId = widget.initialBrokerAccountId;
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
                decoration: const InputDecoration(
                  labelText: 'Portfolio (broker account)',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('My Portfolio (no broker account)'),
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

class _PortfolioHeader extends StatelessWidget {
  const _PortfolioHeader({
    required this.portfolios,
    required this.selectedPortfolioId,
    required this.advanced,
    required this.onSelect,
    required this.onToggleAdvanced,
  });

  final List<Map<String, dynamic>> portfolios;
  final String? selectedPortfolioId;
  final bool advanced;
  final ValueChanged<String?> onSelect;
  final VoidCallback onToggleAdvanced;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: selectedPortfolioId ?? '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Portfolio',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('All Portfolios'),
                  ),
                  ...portfolios.map(
                    (portfolio) => DropdownMenuItem<String>(
                      value: portfolio['id'] as String,
                      child: Text(
                        '${portfolio['name']} · ${_kindLabel(portfolio['kind'] as String?)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    onSelect(value == null || value.isEmpty ? null : value),
              ),
            ),
            const SizedBox(width: 8),
            FilterChip(
              selected: advanced,
              label: const Text('Advanced'),
              avatar: const Icon(Icons.auto_awesome, size: 16),
              onSelected: (_) => onToggleAdvanced(),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Each broker account is a portfolio — a trade joins its broker account.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PortfolioBadge extends StatelessWidget {
  const _PortfolioBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PerformanceView extends ConsumerStatefulWidget {
  const _PerformanceView({
    required this.portfolioId,
    required this.advanced,
    required this.currency,
  });

  final String? portfolioId;
  final bool advanced;
  final String currency;

  @override
  ConsumerState<_PerformanceView> createState() => _PerformanceViewState();
}

class _PerformanceViewState extends ConsumerState<_PerformanceView> {
  late Future<Map<String, dynamic>> _series;
  late Future<Map<String, dynamic>> _annual;
  late Future<Map<String, dynamic>> _analytics;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PerformanceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.portfolioId != widget.portfolioId) _load();
  }

  void _load() {
    final notifier = ref.read(appControllerProvider.notifier);
    _series = notifier.loadPortfolioSeries(widget.portfolioId);
    _annual = notifier.loadPortfolioAnnual(widget.portfolioId);
    _analytics = notifier.loadPortfolioAnalytics(widget.portfolioId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<Map<String, dynamic>>(
          future: _series,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final growth = _rows(data['growth']);
            final composition = _rows(data['return_composition']);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Panel(
                  title: 'Portfolio Growth',
                  child: _LineChartCard(
                    points: growth,
                    valueKey: 'portfolio_value',
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                _Panel(
                  title: 'Total Return Growth',
                  child: _LineChartCard(
                    points: growth,
                    valueKey: 'cumulative_return',
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 12),
                _Panel(
                  title: 'Return Composition',
                  child: _CompositionChart(
                    rows: composition,
                    currency: widget.currency,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            );
          },
        ),
        FutureBuilder<Map<String, dynamic>>(
          future: _annual,
          builder: (context, snapshot) {
            final rows = _rows(snapshot.data?['rows']);
            return _Panel(
              title: 'Annual Performance Report',
              child: _AnnualTable(rows: rows, currency: widget.currency),
            );
          },
        ),
        if (widget.advanced) ...[
          const SizedBox(height: 12),
          FutureBuilder<Map<String, dynamic>>(
            future: _analytics,
            builder: (context, snapshot) {
              final data = snapshot.data ?? const <String, dynamic>{};
              return _Panel(
                title: 'Advanced Investor Analytics',
                child: _AnalyticsGrid(
                  data: data,
                  currency: widget.currency,
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  List<Map<String, dynamic>> _rows(Object? value) {
    return (value as List? ?? [])
        .whereType<Map>()
        .map((row) => row.cast<String, dynamic>())
        .toList();
  }
}

class _LineChartCard extends StatelessWidget {
  const _LineChartCard({
    required this.points,
    required this.valueKey,
    required this.color,
  });

  final List<Map<String, dynamic>> points;
  final String valueKey;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('Not enough data yet.')),
      );
    }
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), _num(points[i][valueKey])),
    ];
    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompositionChart extends StatelessWidget {
  const _CompositionChart({required this.rows, required this.currency});

  final List<Map<String, dynamic>> rows;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = [Colors.indigo, Colors.green, Colors.orange];
    final positive = rows
        .where((row) => _num(row['value']) != 0)
        .toList();
    if (positive.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(child: Text('Not enough data yet.')),
      );
    }
    return Row(
      children: [
        SizedBox(
          height: 140,
          width: 140,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 36,
              sectionsSpace: 2,
              sections: [
                for (var i = 0; i < positive.length; i++)
                  PieChartSectionData(
                    value: _num(positive[i]['value']).abs(),
                    color: colors[i % colors.length],
                    radius: 26,
                    showTitle: false,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < positive.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          positive[i]['label'] as String? ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Text(
                        money(_num(positive[i]['value']), currency: currency),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnnualTable extends StatelessWidget {
  const _AnnualTable({required this.rows, required this.currency});

  final List<Map<String, dynamic>> rows;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Text('No yearly activity yet.');
    final sorted = [...rows]
      ..sort((a, b) => _num(b['year']).compareTo(_num(a['year'])));
    return Column(
      children: [
        for (final row in sorted)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _num(row['year']).toStringAsFixed(0),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    Text(
                      '${_num(row['annual_return_percent']) >= 0 ? '+' : ''}${_num(row['annual_return_percent']).toStringAsFixed(2)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.amount(
                          context,
                          positive: _num(row['annual_return_percent']) >= 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 3.2,
                  children: [
                    _MiniMetric(
                      'New Invest',
                      money(_num(row['new_investment']), currency: currency),
                    ),
                    _MiniMetric(
                      'Realized',
                      money(_num(row['realized_gain']), currency: currency),
                    ),
                    _MiniMetric(
                      'Dividend',
                      money(_num(row['dividend_income']), currency: currency),
                    ),
                    _MiniMetric(
                      'Ending',
                      money(_num(row['ending_value']), currency: currency),
                    ),
                  ],
                ),
                const Divider(height: 16),
              ],
            ),
          ),
      ],
    );
  }
}

class _AnalyticsGrid extends StatelessWidget {
  const _AnalyticsGrid({required this.data, required this.currency});

  final Map<String, dynamic> data;
  final String currency;

  String _pct(Object? value) {
    if (value == null) return '—';
    final num = _num(value);
    return '${num >= 0 ? '+' : ''}${num.toStringAsFixed(2)}%';
  }

  @override
  Widget build(BuildContext context) {
    final best = (data['best_trade'] as Map?)?.cast<String, dynamic>();
    final worst = (data['worst_trade'] as Map?)?.cast<String, dynamic>();
    final profitFactor = data['profit_factor'];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.8,
      children: [
        _MiniMetric('Portfolio XIRR', _pct(data['portfolio_xirr_percent'])),
        _MiniMetric('CAGR', _pct(data['cagr_percent'])),
        _MiniMetric(
          'Win Rate',
          '${_num(data['win_rate_percent']).toStringAsFixed(1)}%',
        ),
        _MiniMetric(
          'Profit Factor',
          profitFactor == null ? '—' : _num(profitFactor).toStringAsFixed(2),
        ),
        _MiniMetric('Avg Gain', _pct(data['average_gain_percent'])),
        _MiniMetric('Avg Loss', _pct(data['average_loss_percent'])),
        _MiniMetric(
          'Avg Holding',
          '${_num(data['average_holding_period_days']).toStringAsFixed(0)} d',
        ),
        _MiniMetric(
          'Turnover',
          '${_num(data['portfolio_turnover_ratio']).toStringAsFixed(2)}×',
        ),
        _MiniMetric(
          'Best Trade',
          best == null
              ? '—'
              : '${best['symbol']} ${money(_num(best['profit']), currency: currency)}',
        ),
        _MiniMetric(
          'Worst Trade',
          worst == null
              ? '—'
              : '${worst['symbol']} ${money(_num(worst['profit']), currency: currency)}',
          danger: worst != null && _num(worst['profit']) < 0,
        ),
        _MiniMetric('Trades', '${data['total_trades'] ?? 0}'),
        _MiniMetric(
          'Win / Loss',
          '${data['winning_trades'] ?? 0} / ${data['losing_trades'] ?? 0}',
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
  var withdrawals = 0.0;

  for (final transaction in transactions.reversed) {
    final txnType = transaction['txn_type'] as String? ?? '';
    final totalAmount = _num(transaction['total_amount']);
    cashBalance += _num(transaction['cash_flow']);
    if (txnType == 'deposit') principal += totalAmount;
    if (txnType == 'withdraw') withdrawals += totalAmount;
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
  final unrealizedTotal = equityValue - activeCostBasis;
  final overallProfitLoss = realized + unrealizedTotal;
  final totalReturn = realized + dividendIncome + unrealizedTotal;
  // Total Investment = deposited cash; fall back to cost basis when untracked.
  final investmentBase = principal != 0 ? principal : activeCostBasis;
  final recovered = realized + dividendIncome;
  return {
    ...backendSummary,
    'total_principal_investment': principal,
    'invested_capital': principal,
    'active_cost_basis': activeCostBasis,
    'current_equity_value': equityValue,
    'unrealized_gain_loss': unrealizedTotal,
    'cash_balance': fallbackCash,
    'total_portfolio_value': equityValue + fallbackCash,
    'total_realized_capital_gain_loss': realized,
    'dividend_income': dividendIncome,
    'total_realized_profit': realized,
    'overall_profit_loss': overallProfitLoss,
    'return_percent': principal == 0 ? 0 : overallProfitLoss / principal * 100,
    'cagr_percent': 0,
    // Spec dashboard + advanced fields (so offline cold-start isn't all zeros).
    'total_investment': investmentBase,
    'total_dividend_income': dividendIncome,
    'total_unrealized_gain': unrealizedTotal,
    'total_return': totalReturn,
    'roi_percent': investmentBase == 0 ? 0 : totalReturn / investmentBase * 100,
    'net_capital_invested': investmentBase - recovered - withdrawals,
    'capital_recovery_percent': investmentBase == 0
        ? 0
        : recovered / investmentBase * 100,
    'wealth_multiple': investmentBase == 0
        ? 0
        : (equityValue + withdrawals) / investmentBase,
    'total_withdrawals': withdrawals,
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
    _PortfolioTab.performance => 'Perf',
    _PortfolioTab.trade => 'Trade',
    _PortfolioTab.dividend => 'Dividend',
    _PortfolioTab.market => 'Market',
  };
}

IconData _tabIcon(_PortfolioTab tab) {
  return switch (tab) {
    _PortfolioTab.dashboard => Icons.dashboard_outlined,
    _PortfolioTab.holding => Icons.pie_chart_outline,
    _PortfolioTab.performance => Icons.insights_outlined,
    _PortfolioTab.trade => Icons.swap_vert,
    _PortfolioTab.dividend => Icons.payments_outlined,
    _PortfolioTab.market => Icons.show_chart,
  };
}

String _kindLabel(String? kind) {
  return switch (kind) {
    'long_term_sip' => 'Long-Term SIP',
    'mid_term_trading' => 'Mid-Term Trading',
    _ => 'General',
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
