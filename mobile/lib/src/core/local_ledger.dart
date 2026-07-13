import 'finance_summary.dart' show isCreditCardAccount;
import 'formatters.dart';

/// On-device balance math for offline-first writes.
///
/// The mobile mirror only holds the most recent transactions, so balances can
/// NOT be recomputed from scratch. Instead the server balance is the anchor
/// (overwritten by every sync pull) and each local write applies a precise
/// incremental delta here. These rules mirror the backend
/// `TransactionService._apply_balance` / `_reverse_balance` exactly, including
/// credit-card `current_outstanding` and CARD_PAYMENT / CARD_SPENDING handling,
/// so the optimistic local number matches what the server will return on sync.
///
/// A [LedgerAccount] is a mutable view over one account's two money fields.
class LedgerAccount {
  LedgerAccount({required this.balance, required this.outstanding, required this.isCard});

  factory LedgerAccount.fromRow(Map<String, dynamic> row) {
    return LedgerAccount(
      balance: asDouble(row['balance']),
      outstanding: asDouble(row['current_outstanding']),
      isCard: isCreditCardAccount(row),
    );
  }

  double balance;
  double outstanding;
  final bool isCard;
}

/// Whether a transfer row moves money out of a credit card as a spend.
bool _isCardSpending(Map<String, dynamic> txn) =>
    (txn['transaction_type'] as String?) == 'CARD_SPENDING';

/// Whether a transfer row pays down a credit card.
bool _isCardPayment(Map<String, dynamic> txn) =>
    (txn['transaction_type'] as String?) == 'CARD_PAYMENT';

/// Applies a transaction's effect to its account(s). Mirrors the backend's
/// `_apply_balance`. [to] is required only for transfers.
void applyEffect(LedgerAccount from, LedgerAccount? to, Map<String, dynamic> txn) {
  final amount = asDouble(txn['amount']);
  switch (txn['type']) {
    case 'expense':
      if (from.isCard) {
        from.outstanding += amount;
      } else {
        from.balance -= amount;
      }
    case 'income':
      from.balance += amount;
    case 'transfer':
      if (to == null) return;
      if (from.isCard && _isCardSpending(txn)) {
        from.outstanding += amount;
      } else {
        from.balance -= amount;
      }
      if (to.isCard && _isCardPayment(txn)) {
        to.outstanding = _clampZero(to.outstanding - amount);
      } else {
        to.balance += amount;
      }
  }
}

/// Reverses a transaction's effect. Mirrors the backend's `_reverse_balance`.
void reverseEffect(LedgerAccount from, LedgerAccount? to, Map<String, dynamic> txn) {
  final amount = asDouble(txn['amount']);
  switch (txn['type']) {
    case 'expense':
      if (from.isCard) {
        from.outstanding = _clampZero(from.outstanding - amount);
      } else {
        from.balance += amount;
      }
    case 'income':
      from.balance -= amount;
    case 'transfer':
      if (to == null) return;
      if (from.isCard && _isCardSpending(txn)) {
        from.outstanding = _clampZero(from.outstanding - amount);
      } else {
        from.balance += amount;
      }
      if (to.isCard && _isCardPayment(txn)) {
        to.outstanding += amount;
      } else {
        to.balance -= amount;
      }
  }
}

/// Derives the CARD_PAYMENT / CARD_SPENDING marker the backend assigns a
/// transfer, so a locally-created transfer applies the same balance math and
/// pushes the same `transaction_type`. Returns `'transfer'` for plain moves.
String normalizeTransferType(Map<String, dynamic> from, Map<String, dynamic>? to) {
  if (to == null) return 'transfer';
  final fromCard = isCreditCardAccount(from);
  final toCard = isCreditCardAccount(to);
  if (toCard && !fromCard) return 'CARD_PAYMENT';
  if (fromCard && !toCard) return 'CARD_SPENDING';
  return 'transfer';
}

double _clampZero(double value) => value < 0 ? 0 : value;
