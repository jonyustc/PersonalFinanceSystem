import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/src/core/formatters.dart';

void main() {
  test('formats supported currencies', () {
    // Whole amounts drop the decimals; fractional amounts keep two places.
    expect(money(50000, currency: 'BDT'), '৳50,000');
    expect(money(500, currency: 'USD'), r'$500');
    expect(money(300, currency: 'EUR'), '€300');
    expect(money(250, currency: 'GBP'), '£250');
    expect(money(120, currency: 'AED'), 'AED 120');
    expect(money(12.5, currency: 'BDT'), '৳12.50');
    expect(money(-500, currency: 'BDT'), '-৳500');
  });
}
