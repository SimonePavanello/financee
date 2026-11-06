import 'dart:math';

import 'package:drift/drift.dart';

import '../core/utils/formatters.dart';
import 'app_database.dart';

/// Genera sei mesi di movimenti realistici per esplorare l'app.
/// Usa le categorie predefinite (se rinominate, quei movimenti vengono saltati).
Future<int> insertSampleData(AppDatabase db, {DateTime? now}) async {
  final categories = await db.getCategories();
  final byName = {for (final c in categories) c.name: c};
  final today = now ?? DateTime.now();
  final rnd = Random(42);
  final rows = <TransactionsCompanion>[];

  T pick<T>(List<T> items) => items[rnd.nextInt(items.length)];

  void add(String category, double amount, DateTime date, String note) {
    final c = byName[category];
    if (c == null || date.isAfter(today)) return;
    rows.add(
      TransactionsCompanion.insert(
        type: c.type,
        amountCents: (amount * 100).round(),
        categoryId: c.id,
        date: DateTime(date.year, date.month, date.day),
        note: Value(note),
      ),
    );
  }

  for (var m = 5; m >= 0; m--) {
    final month = DateTime(today.year, today.month - m);
    DateTime day(int d) => DateTime(month.year, month.month, d);

    // Entrate
    add('Stipendio', 1950 + rnd.nextInt(120).toDouble(), day(1),
        'Stipendio ${formatMonthName(month)}');
    if (m.isEven) {
      add('Freelance', 250 + rnd.nextInt(350).toDouble(), day(20),
          pick(['Progetto sito web', 'Consulenza', 'Logo per cliente']));
    }
    if (m == 4) add('Rimborsi', 85, day(9), 'Rimborso 730');
    if (m == 1) add('Investimenti', 64.3, day(15), 'Cedola BTP');

    // Casa e bollette
    add('Casa', 650, day(3), 'Affitto');
    add('Bollette', 55 + rnd.nextInt(45) + rnd.nextInt(99) / 100, day(8), 'Luce');
    add('Bollette', 30 + rnd.nextInt(60) + rnd.nextInt(99) / 100, day(12), 'Gas');
    add('Bollette', 27.99, day(15), 'Internet fibra');

    // Abbonamenti
    add('Abbonamenti', 13.99, day(5), 'Netflix');
    add('Abbonamenti', 11.99, day(10), 'Spotify');
    add('Abbonamenti', 39, day(2), 'Palestra');

    // Spesa settimanale
    for (final d in [2, 9, 16, 23]) {
      add('Spesa', 38 + rnd.nextInt(70) + rnd.nextInt(99) / 100,
          day(d + rnd.nextInt(3)),
          pick(['Esselunga', 'Coop', 'Conad', 'Lidl', 'Carrefour']));
    }

    // Ristoranti
    final dinners = 3 + rnd.nextInt(3);
    for (var i = 0; i < dinners; i++) {
      add('Ristoranti e bar', 8 + rnd.nextInt(45) + 0.5, day(1 + rnd.nextInt(28)),
          pick(['Pizzeria da Gino', 'Aperitivo', 'Sushi', 'Colazione al bar', 'Trattoria']));
    }

    // Trasporti
    add('Trasporti', 35, day(1), 'Abbonamento mezzi');
    add('Trasporti', 55 + rnd.nextInt(25).toDouble(), day(6 + rnd.nextInt(5)), 'Benzina');

    // Svago, shopping, salute
    if (rnd.nextBool()) {
      add('Svago', 9.5 * (1 + rnd.nextInt(2)), day(14 + rnd.nextInt(10)), 'Cinema');
    }
    if (m == 3) add('Svago', 68, day(21), 'Concerto');
    if (rnd.nextInt(3) > 0) {
      add('Shopping', 30 + rnd.nextInt(90).toDouble(), day(18 + rnd.nextInt(8)),
          pick(['Zalando', 'Amazon', 'Decathlon', 'IKEA']));
    }
    if (rnd.nextBool()) {
      add('Salute', 12 + rnd.nextInt(30).toDouble(), day(1 + rnd.nextInt(27)), 'Farmacia');
    }
    if (m == 2) add('Viaggi', 320, day(12), 'Weekend a Roma');
    if (m == 4) add('Regali', 45, day(18), 'Regalo compleanno Marta');
    if (m == 5) add('Istruzione', 120, day(10), 'Corso di inglese');
  }

  await db.insertTransactions(rows);
  return rows.length;
}
