import 'package:drift/native.dart';
import 'package:financiee/data/app_database.dart';
import 'package:financiee/data/default_categories.dart';
import 'package:financiee/data/sample_data.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;

  setUpAll(() => initializeDateFormatting('it_IT'));
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('al primo avvio crea le categorie predefinite', () async {
    final cats = await db.getCategories();
    expect(cats.length, kDefaultCategories.length);
    expect(cats.where((c) => c.type == TxType.income).length, 6);
  });

  test('inserisce e legge i movimenti di un intervallo', () async {
    final cats = await db.getCategories();
    final spesa = cats.firstWhere((c) => c.name == 'Spesa');
    await db.addTransaction(
      type: TxType.expense,
      amountCents: 4520,
      categoryId: spesa.id,
      date: DateTime(2026, 11, 4, 18, 30),
      note: 'Esselunga',
    );
    await db.addTransaction(
      type: TxType.expense,
      amountCents: 1000,
      categoryId: spesa.id,
      date: DateTime(2026, 10, 31),
    );

    final nov = await db
        .watchTransactionsBetween(DateTime(2026, 11), DateTime(2026, 12))
        .first;
    expect(nov, hasLength(1));
    expect(nov.single.tx.date, DateTime(2026, 11, 4)); // ora azzerata
    expect(nov.single.category.name, 'Spesa');
    expect(await db.watchTransactionCount().first, 2);
  });

  test('eliminando una categoria i movimenti vengono spostati', () async {
    final cats = await db.getCategories();
    final spesa = cats.firstWhere((c) => c.name == 'Spesa');
    final altro = cats.firstWhere((c) => c.name == 'Altre spese');
    final id = await db.createCategory(
      name: 'Palestra',
      type: TxType.expense,
      iconKey: 'fitness',
      color: 0xFF22C55E,
    );
    await db.addTransaction(
      type: TxType.expense,
      amountCents: 3900,
      categoryId: id,
      date: DateTime(2026, 11, 2),
    );
    expect(await db.countTransactionsForCategory(id), 1);

    await db.deleteCategory(id, moveTransactionsTo: altro.id);

    expect((await db.getCategories()).any((c) => c.id == id), isFalse);
    expect(await db.countTransactionsForCategory(altro.id), 1);
    expect(await db.countTransactionsForCategory(spesa.id), 0);
  });

  test('i dati di esempio coprono sei mesi senza date future', () async {
    final now = DateTime(2026, 11, 6);
    final n = await insertSampleData(db, now: now);
    expect(n, greaterThan(100));
    final all = await db
        .watchTransactionsBetween(DateTime(2000), DateTime(2100))
        .first;
    expect(all.every((t) => !t.tx.date.isAfter(now)), isTrue);
    expect(all.map((t) => t.tx.date.month).toSet().length, 6);
  });
}
