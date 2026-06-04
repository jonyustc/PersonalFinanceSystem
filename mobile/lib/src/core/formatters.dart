import 'package:intl/intl.dart';

final _money = NumberFormat.currency(symbol: '', decimalDigits: 2);
final _date = DateFormat('MMM d, yyyy');
final _dateTime = DateFormat('MMM d, h:mm a');

String money(num value, {String currency = 'USD'}) {
  return '$currency ${_money.format(value)}';
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
