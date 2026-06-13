import 'package:intl/intl.dart';

final _money0 = NumberFormat('#,##0');
final _money2 = NumberFormat('#,##0.00');
final _date = DateFormat('MMM d, yyyy');
final _dateTime = DateFormat('MMM d, h:mm a');
final _weekdayDate = DateFormat('EEE, MMM d');
final _weekdayDateYear = DateFormat('EEE, MMM d, yyyy');

/// Human day label relative to today: "Today", "Yesterday", "Tomorrow", else a
/// weekday + date (with year only when it differs from the current year).
String dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  final diff = d.difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == -1) return 'Yesterday';
  if (diff == 1) return 'Tomorrow';
  return (d.year == now.year ? _weekdayDate : _weekdayDateYear).format(d);
}

String _currencySymbol(String currency) => switch (currency.toUpperCase()) {
  'USD' => r'$',
  'EUR' => '€',
  'GBP' => '£',
  'AED' => 'AED ',
  _ => '৳', // ৳ Bangladeshi Taka
};

/// Formats money with the currency symbol, grouped thousands, and decimals
/// shown only when there is a fractional part (e.g. ৳361,000 but ৳12.50).
/// Negative values render as -৳500.
String money(num value, {String currency = 'BDT'}) {
  final symbol = _currencySymbol(currency);
  final negative = value < 0;
  final magnitude = value.abs();
  final hasFraction = (magnitude * 100).round() % 100 != 0;
  final formatted = (hasFraction ? _money2 : _money0).format(magnitude);
  return '${negative ? '-' : ''}$symbol$formatted';
}

String compactDate(String value) {
  final parsed = DateTime.tryParse(value);
  return parsed == null ? value : _date.format(parsed.toLocal());
}

String syncTime(String? value) {
  final parsed = DateTime.tryParse(value ?? '');
  if (parsed == null) return 'Never synced';
  return 'Last sync ${_dateTime.format(parsed.toLocal())}';
}

double asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
