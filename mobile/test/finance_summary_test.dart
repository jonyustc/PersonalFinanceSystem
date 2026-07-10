import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/core/finance_summary.dart';

void main() {
  test('builds consistent net worth and monthly totals', () {
    final now = DateTime(2026, 6, 5);
    final summary = buildFinanceSummary(
      now: now,
      accounts: [
        {'id': 'cash', 'name': 'Cash', 'type': 'cash', 'balance': 1000},
        // Credit cards carry debt in current_outstanding; balance stays 0,
        // matching the backend AccountService conventions.
        {
          'id': 'card',
          'name': 'Card',
          'type': 'credit_card',
          'balance': 0,
          'current_outstanding': 250,
          'credit_limit': 1000,
        },
      ],
      categories: [
        {'id': 'food', 'name': 'Food', 'type': 'expense', 'parent_id': null},
      ],
      transactions: [
        {
          'id': 't1',
          'account_id': 'cash',
          'category_id': 'food',
          'type': 'expense',
          'amount': 100,
          'txn_date': '2026-06-03T00:00:00Z',
          'transaction_status': 'posted',
        },
        {
          'id': 't2',
          'account_id': 'cash',
          'type': 'income',
          'amount': 500,
          'txn_date': '2026-06-01T00:00:00Z',
          'transaction_status': 'posted',
        },
      ],
      budgets: [
        {
          'id': 'b1',
          'category_id': 'food',
          'month': 6,
          'year': 2026,
          'amount': 400,
          'spent': 100,
        },
      ],
      stocks: const [
        {
          'id': 'stock',
          'symbol': 'STOCK',
          'name': 'Stock',
          'currency': 'BDT',
          'last_price': 20,
        },
      ],
      portfolioTransactions: const [
        {
          'id': 'buy',
          'stock_id': 'stock',
          'txn_type': 'buy',
          'quantity': 10,
          'price': 15,
          'total_amount': 150,
          'txn_date': '2026-06-01',
        },
      ],
    );

    expect(summary.assets, 1200);
    expect(summary.creditCardOutstanding, 250);
    expect(summary.liabilities, 250);
    expect(summary.netWorth, 950);
    expect(summary.monthlyIncome, 500);
    expect(summary.monthlyExpense, 100);
    expect(summary.cashFlow, 400);
    expect(summary.budgetUsage, 0.25);

    // Per-card rollup mirrors the backend /dashboard/simple card view.
    expect(summary.creditCards, hasLength(1));
    final card = summary.creditCards.single;
    expect(card.outstanding, 250);
    expect(card.creditLimit, 1000);
    expect(card.available, 750);
    expect(card.utilization, 25);
  });

  test('excluded expense does not count toward spent totals', () {
    final summary = buildFinanceSummary(
      now: DateTime(2026, 6, 5),
      accounts: [
        {'id': 'cash', 'name': 'Cash', 'type': 'cash', 'balance': 1000},
      ],
      categories: [
        {'id': 'food', 'name': 'Food', 'type': 'expense', 'parent_id': null},
      ],
      transactions: [
        {
          'id': 't1',
          'account_id': 'cash',
          'category_id': 'food',
          'type': 'expense',
          'amount': 100,
          'txn_date': '2026-06-03T00:00:00Z',
          'transaction_status': 'posted',
        },
        // Flagged include_in_totals=false: still moves the account balance
        // (server-owned) but must be excluded from local spending totals.
        // The sqflite mirror stores the flag as 0/1.
        {
          'id': 't2',
          'account_id': 'cash',
          'category_id': 'food',
          'type': 'expense',
          'amount': 400,
          'txn_date': '2026-06-04T00:00:00Z',
          'transaction_status': 'posted',
          'include_in_totals': 0,
        },
        {
          'id': 't3',
          'account_id': 'cash',
          'type': 'income',
          'amount': 500,
          'txn_date': '2026-06-01T00:00:00Z',
          'transaction_status': 'posted',
          'include_in_totals': false,
        },
      ],
      budgets: const [],
      stocks: const [],
      portfolioTransactions: const [],
    );

    expect(summary.monthlyExpense, 100);
    expect(summary.monthlyIncome, 0);
    expect(summary.cashFlow, -100);
    expect(summary.topExpenseCategories.single.amount, 100);
    expect(summary.accountSpending.single.amount, 100);
  });

  test('overdrawn cash balances become liabilities, not negative assets', () {
    final summary = buildFinanceSummary(
      now: DateTime(2026, 6, 10),
      accounts: [
        {'id': 'cash', 'name': 'Cash', 'type': 'cash', 'balance': 1000},
        {'id': 'od', 'name': 'Overdraft', 'type': 'bank', 'balance': -300},
      ],
      categories: const [],
      transactions: const [],
      budgets: const [],
      stocks: const [],
      portfolioTransactions: const [],
    );

    expect(summary.assets, 1000);
    expect(summary.liabilities, 300);
    expect(summary.netWorth, 700);
  });

  test('buildAccountSummary mirrors backend account summary', () {
    final summary = buildAccountSummary([
      {'id': 'cash', 'name': 'Cash', 'type': 'cash', 'balance': 1500},
      {'id': 'bank', 'name': 'Bank', 'type': 'bank', 'balance': 4000},
      {'id': 'od', 'name': 'Overdraft', 'type': 'bank', 'balance': -500},
      {
        'id': 'broker',
        'name': 'LBSL',
        'type': 'bank',
        'account_subtype': 'stock_broker',
        'balance': 2000,
      },
      {
        'id': 'card',
        'name': 'Visa',
        'type': 'credit_card',
        'balance': 0,
        'current_outstanding': 1200,
        'credit_limit': 5000,
      },
    ]);

    // Assets count positive non-card balances (broker balance included, like
    // the backend): 1500 + 4000 + 2000 = 7500.
    expect(summary.totalAssets, 7500);
    // Liabilities = card debt (1200) + overdrawn (500).
    expect(summary.liabilities, 1700);
    expect(summary.netWorth, 5800);
    expect(summary.cardDebt, 1200);
    expect(summary.cashBalance, 1500);
  });

  test('portfolio average price excludes broker fees', () {
    final holdings = buildPortfolioHoldings(
      [
        {
          'id': 'squr',
          'symbol': 'SQURPHARMA',
          'name': 'Square Pharmaceuticals PLC.',
          'currency': 'BDT',
          'last_price': 210,
        },
      ],
      [
        {
          'id': 'buy',
          'stock_id': 'squr',
          'txn_type': 'buy',
          'quantity': 100,
          'price': 200,
          'fees': 80,
          'total_amount': 20080,
          'txn_date': '2026-06-01',
        },
        {
          'id': 'sell',
          'stock_id': 'squr',
          'txn_type': 'sell',
          'quantity': 20,
          'price': 220,
          'fees': 17.6,
          'total_amount': 4382.4,
          'txn_date': '2026-06-02',
        },
      ],
    );

    expect(holdings, hasLength(1));
    expect(holdings.single.quantity, 80);
    expect(holdings.single.cost / holdings.single.quantity, 200);
    expect(holdings.single.realized, closeTo(382.4, 0.001));
  });

  test(
    'stock broker account balance is excluded from assets when holdings exist',
    () {
      final summary = buildFinanceSummary(
        now: DateTime(2026, 6, 6),
        accounts: [
          {'id': 'cash', 'name': 'Cash', 'type': 'cash', 'balance': 1000},
          {
            'id': 'lbsl',
            'name': 'LBSL',
            'type': 'bank',
            'account_subtype': 'stock_broker',
            'balance': 5000,
          },
        ],
        categories: const [],
        transactions: const [],
        budgets: const [],
        stocks: const [
          {
            'id': 'stock',
            'symbol': 'STOCK',
            'name': 'Stock',
            'currency': 'BDT',
            'last_price': 20,
          },
        ],
        portfolioTransactions: const [
          {
            'id': 'buy',
            'stock_id': 'stock',
            'txn_type': 'buy',
            'quantity': 10,
            'price': 15,
            'total_amount': 150,
            'txn_date': '2026-06-01',
          },
        ],
      );

      expect(summary.portfolioValue, 200);
      expect(summary.assets, 1200);
    },
  );

  test('uses backend portfolio total when available', () {
    final summary = buildFinanceSummary(
      now: DateTime(2026, 6, 12),
      accounts: [
        {'id': 'cash', 'name': 'Cash', 'type': 'cash', 'balance': 1000},
      ],
      categories: const [],
      transactions: const [],
      budgets: const [],
      stocks: const [
        {
          'id': 'stock',
          'symbol': 'STOCK',
          'name': 'Stock',
          'currency': 'BDT',
          'last_price': 2500,
        },
      ],
      portfolioTransactions: const [
        {
          'id': 'buy',
          'stock_id': 'stock',
          'txn_type': 'buy',
          'quantity': 100,
          'price': 1500,
          'total_amount': 150000,
          'txn_date': '2026-06-01',
        },
      ],
      portfolioSummary: const {
        'total_portfolio_value': 182000,
        'active_cost_basis': 150000,
        'overall_profit_loss': 32000,
        'holdings': [{}],
      },
    );

    expect(summary.portfolioValue, 182000);
    expect(summary.portfolioCost, 150000);
    expect(summary.portfolioGain, 32000);
    expect(summary.assets, 183000);
  });
}
