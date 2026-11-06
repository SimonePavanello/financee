import 'app_database.dart';

/// Un movimento insieme alla sua categoria (risultato della join).
class TransactionWithCategory {
  const TransactionWithCategory(this.tx, this.category);

  final TransactionEntity tx;
  final CategoryEntity category;

  bool get isIncome => tx.type == TxType.income;

  /// Importo con segno: positivo per le entrate, negativo per le uscite.
  int get signedCents => isIncome ? tx.amountCents : -tx.amountCents;

  /// Titolo da mostrare: la descrizione se presente, altrimenti la categoria.
  String get title => tx.note.trim().isEmpty ? category.name : tx.note.trim();
}
