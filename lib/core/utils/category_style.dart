import 'package:flutter/material.dart';

/// Icone selezionabili per le categorie. Nel database si salva la chiave
/// (non il codepoint) così il tree-shaking delle icone resta attivo.
const Map<String, IconData> kCategoryIcons = {
  'cart': Icons.shopping_cart_rounded,
  'bakery': Icons.bakery_dining_rounded,
  'restaurant': Icons.restaurant_rounded,
  'coffee': Icons.local_cafe_rounded,
  'bar': Icons.local_bar_rounded,
  'home': Icons.home_rounded,
  'bolt': Icons.bolt_rounded,
  'water': Icons.water_drop_rounded,
  'wifi': Icons.wifi_rounded,
  'phone': Icons.smartphone_rounded,
  'car': Icons.directions_car_rounded,
  'fuel': Icons.local_gas_station_rounded,
  'train': Icons.train_rounded,
  'parking': Icons.local_parking_rounded,
  'flight': Icons.flight_rounded,
  'beach': Icons.beach_access_rounded,
  'health': Icons.favorite_rounded,
  'medication': Icons.medication_rounded,
  'fitness': Icons.fitness_center_rounded,
  'beauty': Icons.spa_rounded,
  'movie': Icons.movie_rounded,
  'game': Icons.sports_esports_rounded,
  'music': Icons.music_note_rounded,
  'book': Icons.menu_book_rounded,
  'school': Icons.school_rounded,
  'shopping': Icons.shopping_bag_rounded,
  'clothes': Icons.checkroom_rounded,
  'subscriptions': Icons.subscriptions_rounded,
  'gift': Icons.card_giftcard_rounded,
  'celebration': Icons.celebration_rounded,
  'pets': Icons.pets_rounded,
  'baby': Icons.child_friendly_rounded,
  'family': Icons.family_restroom_rounded,
  'tools': Icons.build_rounded,
  'insurance': Icons.shield_rounded,
  'bank': Icons.account_balance_rounded,
  'tax': Icons.receipt_long_rounded,
  'charity': Icons.volunteer_activism_rounded,
  'work': Icons.work_rounded,
  'laptop': Icons.laptop_mac_rounded,
  'trending': Icons.trending_up_rounded,
  'savings': Icons.savings_rounded,
  'payments': Icons.payments_rounded,
  'money': Icons.attach_money_rounded,
  'exchange': Icons.currency_exchange_rounded,
  'refund': Icons.replay_rounded,
  'redeem': Icons.redeem_rounded,
  'rent': Icons.real_estate_agent_rounded,
  'sell': Icons.sell_rounded,
  'other': Icons.category_rounded,
};

IconData categoryIcon(String key) =>
    kCategoryIcons[key] ?? Icons.category_rounded;

/// Palette per le categorie.
const List<Color> kCategoryColors = [
  Color(0xFF6366F1), // indaco
  Color(0xFF8B5CF6), // viola
  Color(0xFFA855F7), // porpora
  Color(0xFFD946EF), // fucsia
  Color(0xFFEC4899), // rosa
  Color(0xFFF43F5E), // rosso rosa
  Color(0xFFEF4444), // rosso
  Color(0xFFF97316), // arancio
  Color(0xFFF59E0B), // ambra
  Color(0xFFEAB308), // giallo
  Color(0xFF84CC16), // lime
  Color(0xFF22C55E), // verde
  Color(0xFF10B981), // smeraldo
  Color(0xFF14B8A6), // teal
  Color(0xFF06B6D4), // ciano
  Color(0xFF0EA5E9), // azzurro
  Color(0xFF3B82F6), // blu
  Color(0xFF64748B), // ardesia
];
