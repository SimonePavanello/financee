import 'package:drift/drift.dart';

import 'default_categories.dart';
import 'models.dart';

part 'app_database.g.dart';

/// Tipo di movimento. L'ordine è salvato nel DB: aggiungere solo in coda.
enum TxType { expense, income }

@DataClassName('CategoryEntity')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  IntColumn get type => intEnum<TxType>()();
  TextColumn get iconKey => text()();

  /// Colore ARGB a 32 bit.
  IntColumn get color => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('TransactionEntity')
@TableIndex(name: 'transactions_date_idx', columns: {#date})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get type => intEnum<TxType>()();

  /// Importo sempre positivo, in centesimi (evita gli errori dei double).
  IntColumn get amountCents => integer()();
  IntColumn get categoryId => integer().references(Categories, #id)();

  /// Giorno del movimento (mezzanotte, ora locale).
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Categories, Transactions])
class AppDatabase extends _$AppDatabase {
  /// L'executor arriva da `openAppDatabaseConnection()` (vedi connection.dart)
  /// oppure, nei test, da un database in memoria.
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultCategories();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _seedDefaultCategories() async {
    await batch((b) {
      b.insertAll(categories, [
        for (final (i, c) in kDefaultCategories.indexed)
          CategoriesCompanion.insert(
            name: c.name,
            type: c.type,
            iconKey: c.iconKey,
            color: c.color,
            sortOrder: Value(i),
          ),
      ]);
    });
  }

  // ---------------------------------------------------------------------------
  // Categorie
  // ---------------------------------------------------------------------------

  Stream<List<CategoryEntity>> watchCategories() => (select(categories)
        ..orderBy([
          (c) => OrderingTerm.asc(c.sortOrder),
          (c) => OrderingTerm.asc(c.name),
        ]))
      .watch();

  Future<List<CategoryEntity>> getCategories() => select(categories).get();

  Future<int> createCategory({
    required String name,
    required TxType type,
    required String iconKey,
    required int color,
  }) async {
    final maxOrder = categories.sortOrder.max();
    final current = await (selectOnly(categories)..addColumns([maxOrder]))
        .map((r) => r.read(maxOrder))
        .getSingle();
    return into(categories).insert(
      CategoriesCompanion.insert(
        name: name,
        type: type,
        iconKey: iconKey,
        color: color,
        sortOrder: Value((current ?? -1) + 1),
      ),
    );
  }

  Future<bool> updateCategory(CategoryEntity category) =>
      update(categories).replace(category);

  Future<int> countTransactionsForCategory(int categoryId) async {
    final count = transactions.id.count();
    final query = selectOnly(transactions)
      ..addColumns([count])
      ..where(transactions.categoryId.equals(categoryId));
    return query.map((r) => r.read(count) ?? 0).getSingle();
  }

  /// Numero di movimenti per categoria (id categoria -> conteggio).
  Stream<Map<int, int>> watchCategoryUsage() {
    final count = transactions.id.count();
    final query = selectOnly(transactions)
      ..addColumns([transactions.categoryId, count])
      ..groupBy([transactions.categoryId]);
    return query.watch().map(
          (rows) => {
            for (final r in rows)
              r.read(transactions.categoryId)!: r.read(count) ?? 0,
          },
        );
  }

  /// Elimina una categoria. Se [moveTransactionsTo] è valorizzato, i movimenti
  /// vengono spostati in quella categoria prima dell'eliminazione.
  Future<void> deleteCategory(int categoryId, {int? moveTransactionsTo}) =>
      transaction(() async {
        if (moveTransactionsTo != null) {
          await (update(transactions)
                ..where((t) => t.categoryId.equals(categoryId)))
              .write(TransactionsCompanion(categoryId: Value(moveTransactionsTo)));
        }
        await (delete(categories)..where((c) => c.id.equals(categoryId))).go();
      });

  // ---------------------------------------------------------------------------
  // Movimenti
  // ---------------------------------------------------------------------------

  /// Movimenti con data in [start, end), dal più recente.
  Stream<List<TransactionWithCategory>> watchTransactionsBetween(
    DateTime start,
    DateTime end,
  ) {
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
    ])
      ..where(
        transactions.date.isBiggerOrEqualValue(start) &
            transactions.date.isSmallerThanValue(end),
      )
      ..orderBy([
        OrderingTerm.desc(transactions.date),
        OrderingTerm.desc(transactions.id),
      ]);

    return query.watch().map(
          (rows) => [
            for (final row in rows)
              TransactionWithCategory(
                row.readTable(transactions),
                row.readTable(categories),
              ),
          ],
        );
  }

  Stream<int> watchTransactionCount() {
    final count = transactions.id.count();
    return (selectOnly(transactions)..addColumns([count]))
        .map((r) => r.read(count) ?? 0)
        .watchSingle();
  }

  Future<int> addTransaction({
    required TxType type,
    required int amountCents,
    required int categoryId,
    required DateTime date,
    String note = '',
  }) =>
      into(transactions).insert(
        TransactionsCompanion.insert(
          type: type,
          amountCents: amountCents,
          categoryId: categoryId,
          date: DateTime(date.year, date.month, date.day),
          note: Value(note),
        ),
      );

  Future<bool> updateTransaction(TransactionEntity tx) =>
      update(transactions).replace(
        tx.copyWith(date: DateTime(tx.date.year, tx.date.month, tx.date.day)),
      );

  Future<int> deleteTransaction(int id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  /// Reinserisce un movimento appena eliminato (per "Annulla").
  Future<int> restoreTransaction(TransactionEntity tx) =>
      into(transactions).insert(tx, mode: InsertMode.insertOrReplace);

  Future<int> deleteAllTransactions() => delete(transactions).go();

  Future<void> insertTransactions(List<TransactionsCompanion> rows) =>
      batch((b) => b.insertAll(transactions, rows));
}
