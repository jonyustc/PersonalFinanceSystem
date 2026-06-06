import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/features/dashboard/dashboard_page.dart';

void main() {
  test('todayTransactions returns only current-day rows newest first', () {
    final rows = todayTransactions(
      [
        {'id': 'old', 'txn_date': '2026-06-05T23:59:00'},
        {'id': 'morning', 'txn_date': '2026-06-06T09:00:00'},
        {'id': 'evening', 'txn_date': '2026-06-06T18:30:00'},
      ],
      today: DateTime(2026, 6, 6, 19, 32),
    );

    expect(rows.map((row) => row['id']), ['evening', 'morning']);
  });
}
