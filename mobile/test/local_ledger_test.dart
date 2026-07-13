import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/core/local_ledger.dart';

LedgerAccount cash({double balance = 0}) =>
    LedgerAccount(balance: balance, outstanding: 0, isCard: false);
LedgerAccount card({double outstanding = 0}) =>
    LedgerAccount(balance: 0, outstanding: outstanding, isCard: true);

void main() {
  group('applyEffect / reverseEffect mirror the backend', () {
    test('expense on a cash account moves balance and is reversible', () {
      final acc = cash(balance: 1000);
      final txn = {'type': 'expense', 'amount': 100};
      applyEffect(acc, null, txn);
      expect(acc.balance, 900);
      reverseEffect(acc, null, txn);
      expect(acc.balance, 1000);
    });

    test('expense on a card raises outstanding; reverse clamps at zero', () {
      final acc = card(outstanding: 250);
      final txn = {'type': 'expense', 'amount': 100};
      applyEffect(acc, null, txn);
      expect(acc.outstanding, 350);
      reverseEffect(acc, null, txn);
      expect(acc.outstanding, 250);
      // Reversing more than exists never goes negative.
      reverseEffect(acc, null, {'type': 'expense', 'amount': 999});
      expect(acc.outstanding, 0);
    });

    test('income raises the cash balance', () {
      final acc = cash(balance: 500);
      applyEffect(acc, null, {'type': 'income', 'amount': 200});
      expect(acc.balance, 700);
    });

    test('plain cash->cash transfer', () {
      final from = cash(balance: 1000);
      final to = cash(balance: 100);
      final txn = {'type': 'transfer', 'amount': 300};
      applyEffect(from, to, txn);
      expect(from.balance, 700);
      expect(to.balance, 400);
      reverseEffect(from, to, txn);
      expect(from.balance, 1000);
      expect(to.balance, 100);
    });

    test('card payment: cash out, card outstanding down (clamped)', () {
      final from = cash(balance: 1000);
      final to = card(outstanding: 250);
      final txn = {'type': 'transfer', 'amount': 300, 'transaction_type': 'CARD_PAYMENT'};
      applyEffect(from, to, txn);
      expect(from.balance, 700);
      expect(to.outstanding, 0); // max(250-300, 0)
      reverseEffect(from, to, txn);
      expect(from.balance, 1000);
      expect(to.outstanding, 300); // reverse is un-clamped, mirroring backend
    });

    test('card spending: card outstanding up, cash in', () {
      final from = card(outstanding: 100);
      final to = cash(balance: 0);
      final txn = {'type': 'transfer', 'amount': 200, 'transaction_type': 'CARD_SPENDING'};
      applyEffect(from, to, txn);
      expect(from.outstanding, 300);
      expect(to.balance, 200);
    });
  });

  group('normalizeTransferType', () {
    final cashRow = {'type': 'cash'};
    final cardRow = {'type': 'credit_card'};
    test('cash -> card is a card payment', () {
      expect(normalizeTransferType(cashRow, cardRow), 'CARD_PAYMENT');
    });
    test('card -> cash is card spending', () {
      expect(normalizeTransferType(cardRow, cashRow), 'CARD_SPENDING');
    });
    test('cash -> cash is a plain transfer', () {
      expect(normalizeTransferType(cashRow, cashRow), 'transfer');
    });
  });
}
