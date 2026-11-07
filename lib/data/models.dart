import 'app_database.dart';

/// Una voce della lista movimenti: un'entrata/uscita oppure un trasferimento.
sealed class Movement {
  DateTime get date;
  DateTime get createdAt;
  String get note;
}

/// Un movimento con la sua categoria e il suo conto (risultato della join).
final class TransactionWithCategory implements Movement {
  const TransactionWithCategory(this.tx, this.category, this.account);

  final TransactionEntity tx;
  final CategoryEntity category;
  final AccountEntity account;

  bool get isIncome => tx.type == TxType.income;

  /// Importo con segno: positivo per le entrate, negativo per le uscite.
  int get signedCents => isIncome ? tx.amountCents : -tx.amountCents;

  /// Titolo da mostrare: la descrizione se presente, altrimenti la categoria.
  String get title => tx.note.trim().isEmpty ? category.name : tx.note.trim();

  @override
  DateTime get date => tx.date;

  @override
  DateTime get createdAt => tx.createdAt;

  @override
  String get note => tx.note;
}

/// Un trasferimento con i conti di origine e destinazione.
final class TransferWithAccounts implements Movement {
  const TransferWithAccounts(this.transfer, this.from, this.to);

  final TransferEntity transfer;
  final AccountEntity from;
  final AccountEntity to;

  int get amountCents => transfer.amountCents;

  String get title =>
      transfer.note.trim().isEmpty ? 'Trasferimento' : transfer.note.trim();

  /// Effetto sul saldo di [accountId]: negativo se esce, positivo se entra,
  /// zero se il conto non è coinvolto.
  int signedCentsFor(int? accountId) {
    if (accountId == from.id) return -amountCents;
    if (accountId == to.id) return amountCents;
    return 0;
  }

  bool involves(int accountId) => from.id == accountId || to.id == accountId;

  @override
  DateTime get date => transfer.date;

  @override
  DateTime get createdAt => transfer.createdAt;

  @override
  String get note => transfer.note;
}

/// Unisce movimenti e trasferimenti ordinandoli dal più recente.
List<Movement> mergeMovements(
  List<TransactionWithCategory> transactions,
  List<TransferWithAccounts> transfers,
) {
  final all = <Movement>[...transactions, ...transfers];
  all.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
  });
  return all;
}
