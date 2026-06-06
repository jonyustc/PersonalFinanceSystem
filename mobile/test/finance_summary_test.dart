import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/core/finance_summary.dart';

void main() {
  test('builds consistent net worth and monthly totals', () {
    final now = DateTime(2026, 6, 5);
    final summary = buildFinanceSummary(
      now: now,
      accounts: [
        {'id': 'cash', 'name': 'Cash', 'type': 'cash', 'balance': 1000},
        {
          'id': 'card',
          'name': 'Card',
          'type': 'credit_card',
          'balance': 250,
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
    expect(summary.netWorth, 950);
    expect(summary.monthlyIncome, 500);
    expect(summary.monthlyExpense, 100);
    expect(summary.cashFlow, 400);
    expect(summary.budgetUsage, 0.25);
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
}
