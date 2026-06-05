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
      stocks: const [],
      portfolioTransactions: const [],
    );

    expect(summary.assets, 1000);
    expect(summary.creditCardOutstanding, 250);
    expect(summary.netWorth, 750);
    expect(summary.monthlyIncome, 500);
    expect(summary.monthlyExpense, 100);
    expect(summary.cashFlow, 400);
    expect(summary.budgetUsage, 0.25);
  });
}
