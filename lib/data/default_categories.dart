import 'app_database.dart';

class DefaultCategory {
  const DefaultCategory(this.name, this.type, this.iconKey, this.color);

  final String name;
  final TxType type;
  final String iconKey;
  final int color;
}

class DefaultAccount {
  const DefaultAccount(this.name, this.iconKey, this.color);

  final String name;
  final String iconKey;
  final int color;
}

/// Conto creato al primo avvio (e in migrazione, per i movimenti esistenti).
const kDefaultAccount = DefaultAccount('Conto principale', 'bank', 0xFF6366F1);

/// Categorie create al primo avvio. L'utente può modificarle o eliminarle.
const kDefaultCategories = <DefaultCategory>[
  // Uscite
  DefaultCategory('Spesa', TxType.expense, 'cart', 0xFF22C55E),
  DefaultCategory('Ristoranti e bar', TxType.expense, 'restaurant', 0xFFF97316),
  DefaultCategory('Casa', TxType.expense, 'home', 0xFF6366F1),
  DefaultCategory('Bollette', TxType.expense, 'bolt', 0xFFF59E0B),
  DefaultCategory('Trasporti', TxType.expense, 'car', 0xFF0EA5E9),
  DefaultCategory('Salute', TxType.expense, 'health', 0xFFEF4444),
  DefaultCategory('Svago', TxType.expense, 'movie', 0xFFA855F7),
  DefaultCategory('Shopping', TxType.expense, 'shopping', 0xFFEC4899),
  DefaultCategory('Abbonamenti', TxType.expense, 'subscriptions', 0xFF8B5CF6),
  DefaultCategory('Viaggi', TxType.expense, 'flight', 0xFF14B8A6),
  DefaultCategory('Istruzione', TxType.expense, 'school', 0xFF3B82F6),
  DefaultCategory('Regali', TxType.expense, 'gift', 0xFFD946EF),
  DefaultCategory('Altre spese', TxType.expense, 'other', 0xFF64748B),
  // Entrate
  DefaultCategory('Stipendio', TxType.income, 'work', 0xFF10B981),
  DefaultCategory('Freelance', TxType.income, 'laptop', 0xFF06B6D4),
  DefaultCategory('Investimenti', TxType.income, 'trending', 0xFF84CC16),
  DefaultCategory('Rimborsi', TxType.income, 'refund', 0xFF0EA5E9),
  DefaultCategory('Regali ricevuti', TxType.income, 'redeem', 0xFFEC4899),
  DefaultCategory('Altre entrate', TxType.income, 'payments', 0xFF64748B),
];
