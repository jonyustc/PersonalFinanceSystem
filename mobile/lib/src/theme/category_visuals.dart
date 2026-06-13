import 'package:flutter/material.dart';

/// A color + icon pairing used to render a category in a colorful, recognizable
/// way (the "category-rich" look of top finance apps).
class CategoryVisual {
  const CategoryVisual(this.color, this.icon);

  final Color color;
  final IconData icon;
}

/// Vibrant, evenly-spaced palette used when a category has no explicit color.
const _palette = [
  Color(0xFFEF4444), // red
  Color(0xFFF97316), // orange
  Color(0xFFF59E0B), // amber
  Color(0xFF10B981), // emerald
  Color(0xFF06B6D4), // cyan
  Color(0xFF3B82F6), // blue
  Color(0xFF6366F1), // indigo
  Color(0xFF8B5CF6), // violet
  Color(0xFFEC4899), // pink
  Color(0xFF14B8A6), // teal
];

/// Keyword → icon mapping so common categories get a fitting glyph even when
/// no icon is stored. First matching keyword wins.
const _iconKeywords = <String, IconData>{
  'food': Icons.restaurant,
  'restaurant': Icons.restaurant,
  'grocer': Icons.local_grocery_store,
  'lunch': Icons.lunch_dining,
  'dinner': Icons.dinner_dining,
  'coffee': Icons.local_cafe,
  'transport': Icons.directions_bus,
  'uber': Icons.local_taxi,
  'taxi': Icons.local_taxi,
  'fuel': Icons.local_gas_station,
  'gas': Icons.local_gas_station,
  'car': Icons.directions_car,
  'travel': Icons.flight,
  'flight': Icons.flight,
  'rent': Icons.home,
  'home': Icons.home,
  'house': Icons.house,
  'bill': Icons.receipt_long,
  'utilit': Icons.bolt,
  'electric': Icons.bolt,
  'water': Icons.water_drop,
  'internet': Icons.wifi,
  'phone': Icons.smartphone,
  'mobile': Icons.smartphone,
  'shop': Icons.shopping_bag,
  'cloth': Icons.checkroom,
  'health': Icons.favorite,
  'medic': Icons.medical_services,
  'pharma': Icons.medical_services,
  'gym': Icons.fitness_center,
  'fitness': Icons.fitness_center,
  'education': Icons.school,
  'school': Icons.school,
  'book': Icons.menu_book,
  'entertain': Icons.movie,
  'movie': Icons.movie,
  'music': Icons.music_note,
  'game': Icons.sports_esports,
  'gift': Icons.card_giftcard,
  'donation': Icons.volunteer_activism,
  'charity': Icons.volunteer_activism,
  'salary': Icons.payments,
  'income': Icons.savings,
  'invest': Icons.trending_up,
  'saving': Icons.savings,
  'tax': Icons.account_balance,
  'bank': Icons.account_balance,
  'insurance': Icons.shield,
  'pet': Icons.pets,
  'baby': Icons.child_friendly,
  'child': Icons.child_care,
  'beauty': Icons.spa,
  'salon': Icons.content_cut,
  'transfer': Icons.swap_horiz,
};

/// Resolves a category's visual identity: an explicit hex [color] if present,
/// otherwise a stable palette color derived from [name]; and an icon inferred
/// from the name's keywords, falling back to a generic category glyph.
CategoryVisual categoryVisual({String? name, String? color}) {
  final lower = (name ?? '').toLowerCase();
  final resolvedColor = _parseHexColor(color) ?? _colorForName(lower);
  return CategoryVisual(resolvedColor, _iconForName(lower));
}

Color _colorForName(String name) {
  if (name.isEmpty) return _palette[0];
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return _palette[hash % _palette.length];
}

IconData _iconForName(String name) {
  for (final entry in _iconKeywords.entries) {
    if (name.contains(entry.key)) return entry.value;
  }
  return Icons.category_rounded;
}

Color? _parseHexColor(String? value) {
  if (value == null) return null;
  var hex = value.trim().replaceAll('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final intValue = int.tryParse(hex, radix: 16);
  return intValue == null ? null : Color(intValue);
}
