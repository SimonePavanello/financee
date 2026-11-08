import 'package:drift/drift.dart';

import '../core/utils/streams.dart';
import 'default_categories.dart';
import 'models.dart';

part 'app_database.g.dart';

/// Tipo di movimento. L'ordine è salvato nel DB: aggiungere solo in coda.
enum TxType { expense, income }

/// Tipo di conto. L'ordine è salvato nel DB: aggiungere solo in coda.
enum AccountKind {
  standard,

  /// Conto dei buoni pasto: al massimo uno. Le spese possono essere pagate
  /// in parte con questo conto (vedi [Transactions.voucherCents]).
  mealVoucher,
}

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
  IntColumn get kind => intEnum<AccountKind>()
      .withDefault(Constant(AccountKind.standard.index))();
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

/// Tipo di debito. L'ordine è salvato nel DB: aggiungere solo in coda.
enum DebtKind {
  /// Un importo totale (es. PayPal in 3 rate, Klarna): ogni spesa collegata
  /// lo riduce.
  amount,

  /// Un finanziamento a rate (es. prestito auto): importo della rata, numero
  /// di rate e rate già pagate prima di registrarle nell'app. Niente
  /// interessi: il totale è rata × numero di rate.
  installments,
}

/// Debito da restituire (prestito, finanziamento, soldi chiesti a qualcuno).
/// Le spese collegate ([Transactions.debtId]) sono i pagamenti che lo
/// riducono, fino a estinguerlo.
@DataClassName('DebtEntity')
class Debts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40)();

  /// Importo da restituire, sempre positivo, in centesimi. Per i debiti a
  /// rate è rata × numero di rate.
  IntColumn get amountCents => integer()();
  TextColumn get iconKey => text()();

  /// Colore ARGB a 32 bit.
  IntColumn get color => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get kind =>
      intEnum<DebtKind>().withDefault(Constant(DebtKind.amount.index))();

  /// Solo per i debiti a rate: importo di una rata, in centesimi.
  IntColumn get installmentCents => integer().nullable()();

  /// Solo per i debiti a rate: numero totale di rate.
  IntColumn get installmentCount => integer().nullable()();

  /// Solo per i debiti a rate: rate già pagate prima di registrarle
  /// nell'app (contano come restituite).
  IntColumn get paidInstallments => integer().withDefault(const Constant(0))();
}

/// Totale di un debito: per quelli a rate è rata × numero di rate.
int debtTotalCents({
  required DebtKind kind,
  required int amountCents,
  int? installmentCents,
  int? installmentCount,
}) =>
    kind == DebtKind.installments &&
            installmentCents != null &&
            installmentCount != null
        ? installmentCents * installmentCount
        : amountCents;

/// Pagamenti di un debito: totale restituito, numero di pagamenti e data
/// dell'ultimo.
typedef DebtPayments = ({int paidCents, int count, DateTime? lastDate});

/// Obiettivo di risparmio di un conto (al massimo uno per conto): quanto è
/// stato messo da parte è il saldo del conto.
@DataClassName('SavingsGoalEntity')
class SavingsGoals extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Conto su cui si risparmia.
  IntColumn get accountId => integer().unique().references(Accounts, #id)();
  TextColumn get name => text().withLength(min: 1, max: 40)();

  /// Saldo da raggiungere, sempre positivo, in centesimi.
  IntColumn get targetCents => integer()();

  /// Giorno entro cui raggiungerlo (facoltativo).
  DateTimeColumn get deadline => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Variazione del saldo di un conto: giorno e centesimi con segno.
typedef BalanceDelta = (DateTime date, int cents);

@DataClassName('TransactionEntity')
@TableIndex(name: 'transactions_date_idx', columns: {#date})
@TableIndex(name: 'transactions_account_idx', columns: {#accountId})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get type => intEnum<TxType>()();

  /// Importo totale, sempre positivo, in centesimi (evita gli errori dei
  /// double). Se c'è una parte pagata con i buoni pasto, è compresa qui.
  IntColumn get amountCents => integer()();
  IntColumn get categoryId => integer().references(Categories, #id)();

  /// Conto da cui esce (o in cui entra) l'importo, esclusa l'eventuale
  /// parte pagata con i buoni pasto.
  IntColumn get accountId => integer().references(Accounts, #id)();

  /// Conto dei buoni pasto usati per pagare una parte della spesa
  /// ([voucherCents]). Nullo se la spesa è pagata tutta con [accountId].
  IntColumn get voucherAccountId =>
      integer().nullable().references(Accounts, #id)();

  /// Parte di [amountCents] pagata con i buoni pasto: 0 se non ci sono buoni,
  /// altrimenti tra 0 e [amountCents] esclusi (vedi [normalizeVoucherSplit]).
  IntColumn get voucherCents => integer().withDefault(const Constant(0))();

  /// Debito che questa spesa contribuisce a restituire (solo per le uscite).
  IntColumn get debtId => integer().nullable().references(Debts, #id)();

  /// Giorno del movimento (mezzanotte, ora locale).
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Ripartizione di una spesa tra il conto scelto e il conto dei buoni pasto.
typedef VoucherSplit = ({int accountId, int? voucherAccountId, int voucherCents});

/// Riporta la ripartizione in forma canonica:
/// - nessun buono (o buoni dallo stesso conto) → spesa normale;
/// - buoni che coprono tutto l'importo → spesa intera sul conto dei buoni.
VoucherSplit normalizeVoucherSplit({
  required int amountCents,
  required int accountId,
  int? voucherAccountId,
  int voucherCents = 0,
}) {
  if (voucherAccountId == null ||
      voucherCents <= 0 ||
      voucherAccountId == accountId) {
    return (accountId: accountId, voucherAccountId: null, voucherCents: 0);
  }
  if (voucherCents >= amountCents) {
    return (accountId: voucherAccountId, voucherAccountId: null, voucherCents: 0);
  }
  return (
    accountId: accountId,
    voucherAccountId: voucherAccountId,
    voucherCents: voucherCents,
  );
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

@DriftDatabase(
  tables: [Accounts, Categories, Debts, Transactions, Transfers, SavingsGoals],
)
class AppDatabase extends _$AppDatabase {
  /// L'executor arriva da `openAppDatabaseConnection()` (vedi connection.dart)
  /// oppure, nei test, da un database in memoria.
  AppDatabase(super.executor);

  /// v1: categorie e movimenti.
  /// v2: conti (ogni movimento appartiene a un conto) e trasferimenti.
  /// v3: buoni pasto (tipo di conto e parte di una spesa pagata con i buoni).
  /// v4: debiti (le spese possono essere collegate a un debito).
  /// v5: obiettivi di risparmio sui conti.
  /// v6: debiti a rate (rata, numero di rate, rate già pagate).
  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seedDefaultCategories();
          await _insertDefaultAccount();
        },
        onUpgrade: (m, from, to) async {
          // Prima di tutto la tabella dei debiti, a cui transactions fa
          // riferimento.
          if (from < 4) await m.createTable(debts);
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
                newColumns: [
                  transactions.accountId,
                  transactions.voucherAccountId,
                  transactions.voucherCents,
                  transactions.debtId,
                ],
              ),
            );
            await m.createIndex(transactionsAccountIdx);
          }
          // Da v1 i passi qui sopra creano già tabelle e colonne con lo schema
          // attuale (buoni compresi); da v2 vanno aggiunte le colonne nuove.
          if (from == 2) {
            await m.addColumn(accounts, accounts.kind);
            await m.addColumn(transactions, transactions.voucherAccountId);
            await m.addColumn(transactions, transactions.voucherCents);
          }
          if (from == 2 || from == 3) {
            await m.addColumn(transactions, transactions.debtId);
          }
          if (from == 4 || from == 5) {
            await m.addColumn(debts, debts.kind);
            await m.addColumn(debts, debts.installmentCents);
            await m.addColumn(debts, debts.installmentCount);
            await m.addColumn(debts, debts.paidInstallments);
          }
          if (from < 5) await m.createTable(savingsGoals);
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
    AccountKind kind = AccountKind.standard,
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
        kind: Value(kind),
      ),
    );
  }

  Future<bool> updateAccount(AccountEntity account) =>
      update(accounts).replace(account);

  /// Imposta [accountId] come conto dei buoni pasto (al massimo uno: gli
  /// altri tornano conti normali). Con `null` nessun conto è dei buoni.
  Future<void> setMealVoucherAccount(int? accountId) => transaction(() async {
        await (update(accounts)
              ..where((a) => a.kind.equalsValue(AccountKind.mealVoucher)))
            .write(AccountsCompanion(kind: Value(AccountKind.standard)));
        if (accountId != null) {
          await (update(accounts)..where((a) => a.id.equals(accountId)))
              .write(AccountsCompanion(kind: Value(AccountKind.mealVoucher)));
        }
      });

  /// Attiva i buoni pasto: il conto "Buoni pasto" diventa il conto dei buoni
  /// (creandolo se non c'è) e si prepara la categoria per i buoni ricevuti.
  /// Restituisce l'id del conto.
  Future<int> enableMealVouchers() => transaction(() async {
        final name = kMealVoucherAccount.name.toLowerCase();
        final existing = (await getAccounts())
            .where((a) => a.name.trim().toLowerCase() == name)
            .firstOrNull;
        final id = existing?.id ??
            await createAccount(
              name: kMealVoucherAccount.name,
              iconKey: kMealVoucherAccount.iconKey,
              color: kMealVoucherAccount.color,
            );
        await setMealVoucherAccount(id);
        await ensureMealVoucherCategory();
        return id;
      });

  /// Categoria di entrata con cui si registrano i buoni ricevuti; la crea
  /// se non esiste. Restituisce il suo id.
  Future<int> ensureMealVoucherCategory() async {
    final existing = await (select(categories)
          ..where(
            (c) =>
                c.type.equalsValue(TxType.income) &
                c.name.lower().equals(kMealVoucherCategory.name.toLowerCase()),
          ))
        .get();
    if (existing.isNotEmpty) return existing.first.id;
    return createCategory(
      name: kMealVoucherCategory.name,
      type: TxType.income,
      iconKey: kMealVoucherCategory.iconKey,
      color: kMealVoucherCategory.color,
    );
  }

  /// Saldo di ogni conto (id conto -> centesimi), considerando solo i
  /// movimenti con data precedente a [before] se indicata. Di una spesa
  /// pagata in parte con i buoni, il conto scelto perde solo la parte non
  /// coperta dai buoni e il conto dei buoni perde il resto.
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
                                    THEN x.amount_cents - x.voucher_cents
                                    ELSE x.voucher_cents - x.amount_cents END)
                    FROM transactions x WHERE x.account_id = a.id $dateFilter), 0)
        + COALESCE((SELECT SUM(CASE WHEN x.type = ${TxType.income.index}
                                    THEN x.voucher_cents ELSE -x.voucher_cents END)
                    FROM transactions x
                    WHERE x.voucher_account_id = a.id $dateFilter), 0)
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
          (SELECT COUNT(*) FROM transactions x
           WHERE x.account_id = a.id OR x.voucher_account_id = a.id)
          + (SELECT COUNT(*) FROM transfers x
             WHERE x.from_account_id = a.id OR x.to_account_id = a.id) AS n
        FROM accounts a
        ''',
        readsFrom: {accounts, transactions, transfers},
      ).watch().map(
            (rows) => {for (final r in rows) r.read<int>('id'): r.read<int>('n')},
          );

  Future<int> countAccountUsage(int accountId) async {
    final row = await customSelect(
      '''
      SELECT (SELECT COUNT(*) FROM transactions x
              WHERE x.account_id = ?1 OR x.voucher_account_id = ?1)
        + (SELECT COUNT(*) FROM transfers x
           WHERE x.from_account_id = ?1 OR x.to_account_id = ?1) AS n
      ''',
      variables: [Variable.withInt(accountId)],
      readsFrom: {transactions, transfers},
    ).getSingle();
    return row.read<int>('n');
  }

  /// Elimina un conto. Se [mergeInto] è valorizzato, movimenti, trasferimenti
  /// e saldo iniziale vengono uniti a quel conto (il saldo del conto di
  /// destinazione diventa la somma dei due). I trasferimenti tra i due conti
  /// diventano interni e vengono eliminati.
  Future<void> deleteAccount(int accountId, {int? mergeInto}) =>
      transaction(() async {
        // L'obiettivo del conto passa al conto di destinazione, se quello
        // non ne ha già uno; altrimenti viene eliminato.
        final targetGoal = mergeInto == null
            ? null
            : await (select(savingsGoals)
                  ..where((g) => g.accountId.equals(mergeInto)))
                .getSingleOrNull();
        if (mergeInto != null && targetGoal == null) {
          await (update(savingsGoals)
                ..where((g) => g.accountId.equals(accountId)))
              .write(SavingsGoalsCompanion(accountId: Value(mergeInto)));
        } else {
          await (delete(savingsGoals)
                ..where((g) => g.accountId.equals(accountId)))
              .go();
        }
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
          await (update(transactions)
                ..where((t) => t.voucherAccountId.equals(accountId)))
              .write(TransactionsCompanion(voucherAccountId: Value(mergeInto)));
          // Una spesa divisa tra i due conti uniti torna una spesa normale.
          await (update(transactions)
                ..where((t) => t.voucherAccountId.equalsExp(t.accountId)))
              .write(
            const TransactionsCompanion(
              voucherAccountId: Value(null),
              voucherCents: Value(0),
            ),
          );
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
  // Debiti
  // ---------------------------------------------------------------------------

  Stream<List<DebtEntity>> watchDebts() => (select(debts)
        ..orderBy([
          (d) => OrderingTerm.asc(d.sortOrder),
          (d) => OrderingTerm.asc(d.id),
        ]))
      .watch();

  Future<List<DebtEntity>> getDebts() => (select(debts)
        ..orderBy([
          (d) => OrderingTerm.asc(d.sortOrder),
          (d) => OrderingTerm.asc(d.id),
        ]))
      .get();

  /// Crea un debito. Per un debito a rate ([DebtKind.installments]) il
  /// totale è calcolato da rata e numero di rate.
  Future<int> createDebt({
    required String name,
    required int amountCents,
    required String iconKey,
    required int color,
    DebtKind kind = DebtKind.amount,
    int? installmentCents,
    int? installmentCount,
    int paidInstallments = 0,
  }) async {
    final installments = kind == DebtKind.installments;
    final maxOrder = debts.sortOrder.max();
    final current = await (selectOnly(debts)..addColumns([maxOrder]))
        .map((r) => r.read(maxOrder))
        .getSingle();
    return into(debts).insert(
      DebtsCompanion.insert(
        name: name,
        amountCents: debtTotalCents(
          kind: kind,
          amountCents: amountCents,
          installmentCents: installmentCents,
          installmentCount: installmentCount,
        ),
        iconKey: iconKey,
        color: color,
        sortOrder: Value((current ?? -1) + 1),
        kind: Value(kind),
        installmentCents: Value(installments ? installmentCents : null),
        installmentCount: Value(installments ? installmentCount : null),
        paidInstallments: Value(installments ? paidInstallments : 0),
      ),
    );
  }

  /// Aggiorna un debito, ricalcolando il totale di quelli a rate (e
  /// azzerando i campi delle rate per quelli a importo totale).
  Future<bool> updateDebt(DebtEntity debt) {
    final installments = debt.kind == DebtKind.installments;
    return update(debts).replace(
      debt.copyWith(
        amountCents: debtTotalCents(
          kind: debt.kind,
          amountCents: debt.amountCents,
          installmentCents: debt.installmentCents,
          installmentCount: debt.installmentCount,
        ),
        installmentCents: Value(installments ? debt.installmentCents : null),
        installmentCount: Value(installments ? debt.installmentCount : null),
        paidInstallments: installments ? debt.paidInstallments : 0,
      ),
    );
  }

  /// Elimina un debito: le spese collegate restano, senza debito.
  Future<void> deleteDebt(int debtId) => transaction(() async {
        await (update(transactions)..where((t) => t.debtId.equals(debtId)))
            .write(const TransactionsCompanion(debtId: Value(null)));
        await (delete(debts)..where((d) => d.id.equals(debtId))).go();
      });

  /// Pagamenti di ogni debito (id debito -> totale, numero, ultima data).
  Stream<Map<int, DebtPayments>> watchDebtPayments() {
    final sum = transactions.amountCents.sum();
    final count = transactions.id.count();
    final last = transactions.date.max();
    final query = selectOnly(transactions)
      ..addColumns([transactions.debtId, sum, count, last])
      ..where(
        transactions.debtId.isNotNull() &
            transactions.type.equalsValue(TxType.expense),
      )
      ..groupBy([transactions.debtId]);
    return query.watch().map(
          (rows) => {
            for (final r in rows)
              r.read(transactions.debtId)!: (
                paidCents: r.read(sum) ?? 0,
                count: r.read(count) ?? 0,
                lastDate: r.read(last),
              ),
          },
        );
  }

  // ---------------------------------------------------------------------------
  // Obiettivi di risparmio
  // ---------------------------------------------------------------------------

  Stream<List<SavingsGoalEntity>> watchSavingsGoals() =>
      (select(savingsGoals)..orderBy([(g) => OrderingTerm.asc(g.id)])).watch();

  Future<List<SavingsGoalEntity>> getSavingsGoals() =>
      (select(savingsGoals)..orderBy([(g) => OrderingTerm.asc(g.id)])).get();

  /// Crea l'obiettivo di [accountId] (un conto ne ha al massimo uno).
  Future<int> createSavingsGoal({
    required int accountId,
    required String name,
    required int targetCents,
    DateTime? deadline,
  }) =>
      into(savingsGoals).insert(
        SavingsGoalsCompanion.insert(
          accountId: accountId,
          name: name,
          targetCents: targetCents,
          deadline: Value(deadline == null ? null : _day(deadline)),
        ),
      );

  Future<bool> updateSavingsGoal(SavingsGoalEntity goal) =>
      update(savingsGoals).replace(
        goal.copyWith(
          deadline: Value(goal.deadline == null ? null : _day(goal.deadline!)),
        ),
      );

  Future<int> deleteSavingsGoal(int id) =>
      (delete(savingsGoals)..where((g) => g.id.equals(id))).go();

  /// Variazioni del saldo dei conti che hanno un obiettivo (id conto ->
  /// variazioni, dalla più vecchia), con le stesse regole di
  /// [watchAccountBalances].
  Stream<Map<int, List<BalanceDelta>>> watchGoalAccountDeltas() => customSelect(
        '''
        SELECT g.account_id AS account_id, x.date AS date,
          CASE WHEN x.type = ${TxType.income.index}
               THEN x.amount_cents - x.voucher_cents
               ELSE x.voucher_cents - x.amount_cents END AS delta
        FROM savings_goals g JOIN transactions x ON x.account_id = g.account_id
        UNION ALL
        SELECT g.account_id, x.date,
          CASE WHEN x.type = ${TxType.income.index}
               THEN x.voucher_cents ELSE -x.voucher_cents END
        FROM savings_goals g
        JOIN transactions x ON x.voucher_account_id = g.account_id
        UNION ALL
        SELECT g.account_id, x.date, x.amount_cents
        FROM savings_goals g JOIN transfers x ON x.to_account_id = g.account_id
        UNION ALL
        SELECT g.account_id, x.date, -x.amount_cents
        FROM savings_goals g JOIN transfers x ON x.from_account_id = g.account_id
        ORDER BY date
        ''',
        readsFrom: {savingsGoals, transactions, transfers},
      ).watch().map((rows) {
        final result = <int, List<BalanceDelta>>{};
        for (final r in rows) {
          final delta = r.read<int>('delta');
          if (delta == 0) continue;
          (result[r.read<int>('account_id')] ??= []).add(
            (r.read<DateTime>('date'), delta),
          );
        }
        return result;
      });

  // ---------------------------------------------------------------------------
  // Movimenti (entrate e uscite)
  // ---------------------------------------------------------------------------

  /// Movimenti con data in [start, end), dal più recente.
  Stream<List<TransactionWithCategory>> watchTransactionsBetween(
    DateTime start,
    DateTime end,
  ) =>
      _watchTransactions(
        transactions.date.isBiggerOrEqualValue(start) &
            transactions.date.isSmallerThanValue(end),
      );

  /// Tutti i pagamenti collegati a un debito, dal più recente.
  Stream<List<TransactionWithCategory>> watchDebtTransactions(int debtId) =>
      _watchTransactions(transactions.debtId.equals(debtId));

  Stream<List<TransactionWithCategory>> _watchTransactions(
    Expression<bool> filter,
  ) {
    final voucher = alias(accounts, 'voucher_account');
    final query = select(transactions).join([
      innerJoin(categories, categories.id.equalsExp(transactions.categoryId)),
      innerJoin(accounts, accounts.id.equalsExp(transactions.accountId)),
      leftOuterJoin(voucher, voucher.id.equalsExp(transactions.voucherAccountId)),
      leftOuterJoin(debts, debts.id.equalsExp(transactions.debtId)),
    ])
      ..where(filter)
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
                row.readTableOrNull(voucher),
                row.readTableOrNull(debts),
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

  /// Aggiunge un movimento. Per una spesa pagata in parte con i buoni pasto,
  /// [voucherCents] (compresi in [amountCents]) escono da [voucherAccountId]
  /// e il resto da [accountId]. Una spesa può essere il pagamento di un
  /// debito ([debtId]); per le entrate il debito viene ignorato.
  Future<int> addTransaction({
    required TxType type,
    required int amountCents,
    required int categoryId,
    required int accountId,
    required DateTime date,
    String note = '',
    int? voucherAccountId,
    int voucherCents = 0,
    int? debtId,
  }) {
    final split = normalizeVoucherSplit(
      amountCents: amountCents,
      accountId: accountId,
      voucherAccountId: type == TxType.expense ? voucherAccountId : null,
      voucherCents: voucherCents,
    );
    return into(transactions).insert(
      TransactionsCompanion.insert(
        type: type,
        amountCents: amountCents,
        categoryId: categoryId,
        accountId: split.accountId,
        voucherAccountId: Value(split.voucherAccountId),
        voucherCents: Value(split.voucherCents),
        debtId: Value(type == TxType.expense ? debtId : null),
        date: _day(date),
        note: Value(note),
      ),
    );
  }

  Future<bool> updateTransaction(TransactionEntity tx) {
    final split = normalizeVoucherSplit(
      amountCents: tx.amountCents,
      accountId: tx.accountId,
      voucherAccountId:
          tx.type == TxType.expense ? tx.voucherAccountId : null,
      voucherCents: tx.voucherCents,
    );
    return update(transactions).replace(
      tx.copyWith(
        date: _day(tx.date),
        accountId: split.accountId,
        voucherAccountId: Value(split.voucherAccountId),
        voucherCents: split.voucherCents,
        debtId: Value(tx.type == TxType.expense ? tx.debtId : null),
      ),
    );
  }

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
