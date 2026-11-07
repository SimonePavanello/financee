import 'package:drift/drift.dart';

import '../core/utils/streams.dart';
import 'default_categories.dart';
import 'models.dart';

part 'app_database.g.dart';

/// Tipo di movimento. L'ordine è salvato nel DB: aggiungere solo in coda.
enum TxType { expense, income }

@DataClassName('AccountEntity')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get iconKey => text()();

  /// Colore ARGB a 32 bit.
  IntColumn get color => integer()();

  /// Saldo del conto al momento della creazione, in centesimi (può essere
  /// negativo, es. una carta di credito).
  IntColumn get initialBalanceCents =>
      integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

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
@TableIndex(name: 'transactions_account_idx', columns: {#accountId})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get type => intEnum<TxType>()();

  /// Importo sempre positivo, in centesimi (evita gli errori dei double).
  IntColumn get amountCents => integer()();
  IntColumn get categoryId => integer().references(Categories, #id)();
  IntColumn get accountId => integer().references(Accounts, #id)();

  /// Giorno del movimento (mezzanotte, ora locale).
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Spostamento di denaro tra due conti: non è né un'entrata né una spesa.
@DataClassName('TransferEntity')
@TableIndex(name: 'transfers_date_idx', columns: {#date})
class Transfers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get fromAccountId => integer().references(Accounts, #id)();
  IntColumn get toAccountId => integer().references(Accounts, #id)();

  /// Importo sempre positivo, in centesimi.
  IntColumn get amountCents => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Accounts, Categories, Transactions, Transfers])
class AppDatabase extends _$AppDatabase {
  /// L'executor arriva da `openAppDatabaseConnection()` (vedi connection.dart)
  /// oppure, nei test, da un database in memoria.
  AppDatabase(super.executor);

  /// v1: categorie e movimenti.
  /// v2: conti (ogni movimento appartiene a un conto) e trasferimenti.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultCategories();
          await _insertDefaultAccount();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(accounts);
            await m.createTable(transfers);
            await m.createIndex(transfersDateIdx);
            // I movimenti già registrati finiscono nel conto principale.
            final defaultId = await _insertDefaultAccount();
            await m.alterTable(
              TableMigration(
                transactions,
                columnTransformer: {
                  transactions.accountId: Constant(defaultId),
                },
                newColumns: [transactions.accountId],
              ),
            );
            await m.createIndex(transactionsAccountIdx);
          }
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

  Future<int> _insertDefaultAccount() => into(accounts).insert(
        AccountsCompanion.insert(
          name: kDefaultAccount.name,
          iconKey: kDefaultAccount.iconKey,
          color: kDefaultAccount.color,
        ),
      );

  // ---------------------------------------------------------------------------
  // Conti
  // ---------------------------------------------------------------------------

  Stream<List<AccountEntity>> watchAccounts() => (select(accounts)
        ..orderBy([
          (a) => OrderingTerm.asc(a.sortOrder),
          (a) => OrderingTerm.asc(a.id),
        ]))
      .watch();

  Future<List<AccountEntity>> getAccounts() => (select(accounts)
        ..orderBy([
          (a) => OrderingTerm.asc(a.sortOrder),
          (a) => OrderingTerm.asc(a.id),
        ]))
      .get();

  Future<int> createAccount({
    required String name,
    required String iconKey,
    required int color,
    int initialBalanceCents = 0,
  }) async {
    final maxOrder = accounts.sortOrder.max();
    final current = await (selectOnly(accounts)..addColumns([maxOrder]))
        .map((r) => r.read(maxOrder))
        .getSingle();
    return into(accounts).insert(
      AccountsCompanion.insert(
        name: name,
        iconKey: iconKey,
        color: color,
        initialBalanceCents: Value(initialBalanceCents),
        sortOrder: Value((current ?? -1) + 1),
      ),
    );
  }

  Future<bool> updateAccount(AccountEntity account) =>
      update(accounts).replace(account);

  /// Saldo di ogni conto (id conto -> centesimi), considerando solo i
  /// movimenti con data precedente a [before] se indicata.
  Stream<Map<int, int>> watchAccountBalances({DateTime? before}) {
    final dateFilter = before == null ? '' : 'AND x.date < ?1';
    final variables = [
      if (before != null) Variable<DateTime>(before),
    ];
    return customSelect(
      '''
      SELECT a.id AS id,
        a.initial_balance_cents
        + COALESCE((SELECT SUM(CASE WHEN x.type = ${TxType.income.index}
                                    THEN x.amount_cents ELSE -x.amount_cents END)
                    FROM transactions x WHERE x.account_id = a.id $dateFilter), 0)
        + COALESCE((SELECT SUM(x.amount_cents) FROM transfers x
                    WHERE x.to_account_id = a.id $dateFilter), 0)
        - COALESCE((SELECT SUM(x.amount_cents) FROM transfers x
                    WHERE x.from_account_id = a.id $dateFilter), 0) AS balance
      FROM accounts a
      ''',
      variables: variables,
      readsFrom: {accounts, transactions, transfers},
    ).watch().map(
          (rows) => {
            for (final r in rows) r.read<int>('id'): r.read<int>('balance'),
          },
        );
  }

  /// Numero di movimenti e trasferimenti per conto (id conto -> conteggio).
  Stream<Map<int, int>> watchAccountUsage() => customSelect(
        '''
        SELECT a.id AS id,
          (SELECT COUNT(*) FROM transactions x WHERE x.account_id = a.id)
          + (SELECT COUNT(*) FROM transfers x
             WHERE x.from_account_id = a.id OR x.to_account_id = a.id) AS n
        FROM accounts a
        ''',
        readsFrom: {accounts, transactions, transfers},
      ).watch().map(
            (rows) => {for (final r in rows) r.read<int>('id'): r.read<int>('n')},
          );

  Future<int> countAccountUsage(int accountId) async =>
      (await watchAccountUsage().first)[accountId] ?? 0;

  /// Elimina un conto. Se [mergeInto] è valorizzato, movimenti, trasferimenti
  /// e saldo iniziale vengono uniti a quel conto (il saldo del conto di
  /// destinazione diventa la somma dei due). I trasferimenti tra i due conti
  /// diventano interni e vengono eliminati.
  Future<void> deleteAccount(int accountId, {int? mergeInto}) =>
      transaction(() async {
        if (mergeInto != null) {
          final source = await (select(accounts)
                ..where((a) => a.id.equals(accountId)))
              .getSingle();
          final target = await (select(accounts)
                ..where((a) => a.id.equals(mergeInto)))
              .getSingle();
          await update(accounts).replace(
            target.copyWith(
              initialBalanceCents:
                  target.initialBalanceCents + source.initialBalanceCents,
            ),
          );
          await (update(transactions)
                ..where((t) => t.accountId.equals(accountId)))
              .write(TransactionsCompanion(accountId: Value(mergeInto)));
          await (delete(transfers)
                ..where(
                  (t) =>
                      (t.fromAccountId.equals(accountId) &
                          t.toAccountId.equals(mergeInto)) |
                      (t.fromAccountId.equals(mergeInto) &
                          t.toAccountId.equals(accountId)),
                ))
              .go();
          await (update(transfers)
                ..where((t) => t.fromAccountId.equals(accountId)))
              .write(TransfersCompanion(fromAccountId: Value(mergeInto)));
          await (update(transfers)
                ..where((t) => t.toAccountId.equals(accountId)))
              .write(TransfersCompanion(toAccountId: Value(mergeInto)));
        }
        await (delete(accounts)..where((a) => a.id.equals(accountId))).go();
      });

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
  // Movimenti (entrate e uscite)
  // ---------------------------------------------------------------------------

  /// Movimenti con data in [start, end), dal più recente.
  Stream<List<TransactionWithCategory>> watchTransactionsBetween(
    DateTime start,
    DateTime end,
  ) {
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      innerJoin(accounts, accounts.id.equalsExp(transactions.accountId)),
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
                row.readTable(accounts),
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
    required int accountId,
    required DateTime date,
    String note = '',
  }) =>
      into(transactions).insert(
        TransactionsCompanion.insert(
          type: type,
          amountCents: amountCents,
          categoryId: categoryId,
          accountId: accountId,
          date: _day(date),
          note: Value(note),
        ),
      );

  Future<bool> updateTransaction(TransactionEntity tx) =>
      update(transactions).replace(tx.copyWith(date: _day(tx.date)));

  Future<int> deleteTransaction(int id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  /// Reinserisce un movimento appena eliminato (per "Annulla").
  Future<int> restoreTransaction(TransactionEntity tx) =>
      into(transactions).insert(tx, mode: InsertMode.insertOrReplace);

  Future<void> insertTransactions(List<TransactionsCompanion> rows) =>
      batch((b) => b.insertAll(transactions, rows));

  // ---------------------------------------------------------------------------
  // Trasferimenti tra conti
  // ---------------------------------------------------------------------------

  /// Trasferimenti con data in [start, end), dal più recente.
  Stream<List<TransferWithAccounts>> watchTransfersBetween(
    DateTime start,
    DateTime end,
  ) {
    final from = alias(accounts, 'from_account');
    final to = alias(accounts, 'to_account');
    final query = select(transfers).join([
      innerJoin(from, from.id.equalsExp(transfers.fromAccountId)),
      innerJoin(to, to.id.equalsExp(transfers.toAccountId)),
    ])
      ..where(
        transfers.date.isBiggerOrEqualValue(start) &
            transfers.date.isSmallerThanValue(end),
      )
      ..orderBy([
        OrderingTerm.desc(transfers.date),
        OrderingTerm.desc(transfers.id),
      ]);

    return query.watch().map(
          (rows) => [
            for (final row in rows)
              TransferWithAccounts(
                row.readTable(transfers),
                row.readTable(from),
                row.readTable(to),
              ),
          ],
        );
  }

  /// Movimenti e trasferimenti insieme, dal più recente.
  Stream<List<Movement>> watchMovementsBetween(DateTime start, DateTime end) =>
      combineLatest2(
        watchTransactionsBetween(start, end),
        watchTransfersBetween(start, end),
        mergeMovements,
      );

  Future<int> addTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required DateTime date,
    String note = '',
  }) {
    assert(fromAccountId != toAccountId);
    return into(transfers).insert(
      TransfersCompanion.insert(
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        amountCents: amountCents,
        date: _day(date),
        note: Value(note),
      ),
    );
  }

  Future<bool> updateTransfer(TransferEntity transfer) =>
      update(transfers).replace(transfer.copyWith(date: _day(transfer.date)));

  Future<int> deleteTransfer(int id) =>
      (delete(transfers)..where((t) => t.id.equals(id))).go();

  Future<int> restoreTransfer(TransferEntity transfer) =>
      into(transfers).insert(transfer, mode: InsertMode.insertOrReplace);

  Future<void> insertTransfers(List<TransfersCompanion> rows) =>
      batch((b) => b.insertAll(transfers, rows));

  /// Elimina movimenti e trasferimenti (conti e categorie restano).
  /// Restituisce il numero di righe eliminate.
  Future<int> deleteAllMovements() => transaction(() async {
        final a = await delete(transactions).go();
        final b = await delete(transfers).go();
        return a + b;
      });

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}
