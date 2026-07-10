import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/core/finance_summary.dart';

void main() {
  test('computes per-person loan nets (positive = they owe me)', () {
    final summaries = buildDebtSummaries([
      // Rahim: +lent 1000 − borrowed 300 − repaid_by_them 400 = +300.
      {
        'id': 't1',
        'type': 'expense',
        'amount': 1000,
        'debt_type': 'lent',
        'counterparty_name': 'Rahim',
        'txn_date': '2026-07-01T00:00:00Z',
        'include_in_totals': 0,
      },
      {
        'id': 't2',
        'type': 'income',
        'amount': 300,
        'debt_type': 'borrowed',
        'counterparty_name': 'Rahim',
        'txn_date': '2026-07-02T00:00:00Z',
        'include_in_totals': 0,
      },
      {
        'id': 't3',
        'type': 'income',
        'amount': 400,
        'debt_type': 'repaid_by_them',
        'counterparty_name': 'Rahim',
        'txn_date': '2026-07-03T00:00:00Z',
        'include_in_totals': 0,
      },
      // Karim: borrowed 500 then fully repaid — settled.
      {
        'id': 't4',
        'type': 'income',
        'amount': 500,
        'debt_type': 'borrowed',
        'counterparty_name': 'Karim',
        'txn_date': '2026-07-01T00:00:00Z',
        'include_in_totals': 0,
      },
      {
        'id': 't5',
        'type': 'expense',
        'amount': 500,
        'debt_type': 'repaid_to_them',
        'counterparty_name': 'Karim',
        'txn_date': '2026-07-04T00:00:00Z',
        'include_in_totals': 0,
      },
      // Plain transactions without a debt_type are ignored.
      {
        'id': 't6',
        'type': 'expense',
        'amount': 999,
        'txn_date': '2026-07-05T00:00:00Z',
      },
    ]);

    expect(summaries, hasLength(2));

    final rahim = summaries.singleWhere((p) => p.name == 'Rahim');
    expect(rahim.net, 300); // they owe me
    expect(rahim.transactionCount, 3);

    final karim = summaries.singleWhere((p) => p.name == 'Karim');
    expect(karim.net, 0); // settled
    expect(karim.transactionCount, 2);
  });

  test('debt sign convention matches the API contract', () {
    expect(debtSign('lent'), 1);
    expect(debtSign('repaid_to_them'), 1);
    expect(debtSign('borrowed'), -1);
    expect(debtSign('repaid_by_them'), -1);
    expect(debtSign(null), 0);

    // Money direction: lent / repaid_to_them are money OUT (expense-shaped),
    // borrowed / repaid_by_them are money IN (income-shaped).
    expect(isDebtMoneyOut('lent'), isTrue);
    expect(isDebtMoneyOut('repaid_to_them'), isTrue);
    expect(isDebtMoneyOut('borrowed'), isFalse);
    expect(isDebtMoneyOut('repaid_by_them'), isFalse);
  });
}
