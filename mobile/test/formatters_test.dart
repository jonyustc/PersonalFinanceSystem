import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/core/formatters.dart';

void main() {
  test('formats supported currencies', () {
    expect(money(50000, currency: 'BDT'), 'BDT 50,000.00');
    expect(money(500, currency: 'USD'), r'$500.00');
    expect(money(300, currency: 'EUR'), '€300.00');
    expect(money(250, currency: 'GBP'), '£250.00');
    expect(money(120, currency: 'AED'), 'AED 120.00');
  });
}
