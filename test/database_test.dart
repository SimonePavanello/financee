import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:financee/data/app_database.dart';
import 'package:financee/data/default_categories.dart';
import 'package:financee/data/models.dart';
import 'package:financee/data/sample_data.dart';
import 'package:financee/domain/savings_goals.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;

  setUpAll(() => initializeDateFormatting('it_IT'));
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<CategoryEntity> cat(String name) async =>
      (await db.getCategories()).firstWhere((c) => c.name == name);

  test('al primo avvio crea categorie predefinite e conto principale', () async {
    final cats = await db.getCategories();
    expect(cats.length, kDefaultCategories.length);
    expect(cats.where((c) => c.type == TxType.income).length, 6);
    final accounts = await db.getAccounts();
    expect(accounts.single.name, 'Conto principale');
  });

  test('inserisce e legge i movimenti con categoria e conto', () async {
    final spesa = await cat('Spesa');
    final main = (await db.getAccounts()).single;
    await db.addTransaction(
      type: TxType.expense,
      amountCents: 4520,
      categoryId: spesa.id,
      accountId: main.id,
      date: DateTime(2026, 11, 4, 18, 30),
      note: 'Esselunga',
    );
    await db.addTransaction(
      type: TxType.expense,
      amountCents: 1000,
      categoryId: spesa.id,
      accountId: main.id,
      date: DateTime(2026, 10, 31),
    );

    final nov = await db
        .watchTransactionsBetween(DateTime(2026, 11), DateTime(2026, 12))
        .first;
    expect(nov, hasLength(1));
    expect(nov.single.tx.date, DateTime(2026, 11, 4)); // ora azzerata
    expect(nov.single.category.name, 'Spesa');
    expect(nov.single.account.name, 'Conto principale');
    expect(await db.watchTransactionCount().first, 2);
  });

  test('saldi dei conti: saldo iniziale, movimenti e trasferimenti', () async {
    final main = (await db.getAccounts()).single.id;
    final savings = await db.createAccount(
      name: 'Risparmi',
      iconKey: 'savings',
      color: 0xFFF59E0B,
      initialBalanceCents: 100000,
    );
    await db.addTransaction(
      type: TxType.income,
      amountCents: 200000,
      categoryId: (await cat('Stipendio')).id,
      accountId: main,
      date: DateTime(2026, 11, 1),
    );
    await db.addTransaction(
      type: TxType.expense,
      amountCents: 65000,
      categoryId: (await cat('Casa')).id,
      accountId: main,
      date: DateTime(2026, 11, 3),
    );
    await db.addTransfer(
      fromAccountId: main,
      toAccountId: savings,
      amountCents: 10000,
      date: DateTime(2026, 11, 5),
      note: 'Accantonamento',
    );

    final balances = await db.watchAccountBalances().first;
    expect(balances[main], 200000 - 65000 - 10000);
    expect(balances[savings], 100000 + 10000);

    // Saldi a una data: solo ciò che precede il 4 novembre.
    final before = await db.watchAccountBalances(before: DateTime(2026, 11, 4)).first;
    expect(before[main], 135000);
    expect(before[savings], 100000);

    final transfers = await db
        .watchTransfersBetween(DateTime(2026, 11), DateTime(2026, 12))
        .first;
    expect(transfers.single.from.name, 'Conto principale');
    expect(transfers.single.to.name, 'Risparmi');
    expect(transfers.single.signedCentsFor(main), -10000);
    expect(transfers.single.signedCentsFor(savings), 10000);

    final movements = await db
        .watchMovementsBetween(DateTime(2026, 11), DateTime(2026, 12))
        .first;
    expect(movements, hasLength(3));
    expect(movements.first, isA<TransferWithAccounts>()); // il più recente
    expect(await db.countAccountUsage(main), 3);
    expect(await db.countAccountUsage(savings), 1);
  });

  test('eliminando un conto lo si può unire a un altro senza perdere saldo', () async {
    final main = (await db.getAccounts()).single.id;
    final cash = await db.createAccount(
      name: 'Contanti',
      iconKey: 'cash',
      color: 0xFF22C55E,
      initialBalanceCents: 5000,
    );
    final card = await db.createAccount(
      name: 'Carta',
      iconKey: 'card',
      color: 0xFF0EA5E9,
    );
    await db.addTransaction(
      type: TxType.expense,
      amountCents: 1200,
      categoryId: (await cat('Ristoranti e bar')).id,
      accountId: cash,
      date: DateTime(2026, 11, 2),
    );
    await db.addTransfer(
      fromAccountId: main,
      toAccountId: cash,
      amountCents: 10000,
      date: DateTime(2026, 11, 1),
    );
    await db.addTransfer(
      fromAccountId: cash,
      toAccountId: card,
      amountCents: 2000,
      date: DateTime(2026, 11, 3),
    );
    final before = await db.watchAccountBalances().first;
    final expectedMain = before[main]! + before[cash]!;

    await db.deleteAccount(cash, mergeInto: main);

    final accounts = await db.getAccounts();
    expect(accounts.map((a) => a.id), isNot(contains(cash)));
    final after = await db.watchAccountBalances().first;
    expect(after[main], expectedMain);
    expect(after[card], before[card]);
    final transfers = await db
        .watchTransfersBetween(DateTime(2000), DateTime(2100))
        .first;
    // Il trasferimento principale -> contanti è diventato interno ed è sparito.
    expect(transfers, hasLength(1));
    expect(transfers.single.from.id, main);
  });

  test('eliminando una categoria i movimenti vengono spostati', () async {
    final main = (await db.getAccounts()).single.id;
    final altro = await cat('Altre spese');
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
      accountId: main,
      date: DateTime(2026, 11, 2),
    );
    await db.deleteCategory(id, moveTransactionsTo: altro.id);
    expect((await db.getCategories()).any((c) => c.id == id), isFalse);
    expect(await db.countTransactionsForCategory(altro.id), 1);
  });

  test('i dati di esempio coprono sei mesi, con conti e trasferimenti', () async {
    final now = DateTime(2026, 11, 6);
    final n = await insertSampleData(db, now: now);
    expect(n, greaterThan(100));
    final all = await db
        .watchMovementsBetween(DateTime(2000), DateTime(2100))
        .first;
    expect(all.every((t) => !t.date.isAfter(now)), isTrue);
    expect(all.map((t) => t.date.month).toSet().length, 6);
    expect(all.whereType<TransferWithAccounts>(), isNotEmpty);
    expect((await db.getAccounts()).map((a) => a.name),
        containsAll(['Conto principale', 'Contanti', 'Risparmi']));
  });

  test('deleteAllMovements svuota movimenti e trasferimenti', () async {
    await insertSampleData(db, now: DateTime(2026, 11, 6));
    expect(await db.deleteAllMovements(), greaterThan(0));
    final all = await db
        .watchMovementsBetween(DateTime(2000), DateTime(2100))
        .first;
    expect(all, isEmpty);
  });

  test('migrazione v1 -> v2: i movimenti esistenti vanno nel conto principale', () async {
    final dir = await Directory.systemTemp.createTemp('financee_migr_');
    final file = File('${dir.path}/v1.sqlite');
    // Schema e dati come li salvava la versione 1 dell'app.
    final raw = sqlite3.open(file.path);
    raw.execute(_schemaV1);
    raw.execute(
      "INSERT INTO categories (id, name, type, icon_key, color) "
      "VALUES (1, 'Spesa', 0, 'cart', 4280401502)",
    );
    raw.execute(
      "INSERT INTO transactions (type, amount_cents, category_id, date, note) "
      "VALUES (0, 4520, 1, 1793833200, 'Esselunga'), (0, 1000, 1, 1793919600, '')",
    );
    raw.execute('PRAGMA user_version = 1');
    raw.close();

    final migrated = AppDatabase(NativeDatabase(file));
    final accounts = await migrated.getAccounts();
    expect(accounts.single.name, 'Conto principale');
    final txs = await migrated
        .watchTransactionsBetween(DateTime(2000), DateTime(2100))
        .first;
    expect(txs, hasLength(2));
    expect(txs.every((t) => t.account.id == accounts.single.id), isTrue);
    expect(txs.map((t) => t.tx.note), contains('Esselunga'));
    final balances = await migrated.watchAccountBalances().first;
    expect(balances[accounts.single.id], -5520);

    final indexes = await migrated
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .map((r) => r.read<String>('name'))
        .get();
    expect(indexes, containsAll([
      'transactions_date_idx',
      'transactions_account_idx',
      'transfers_date_idx',
    ]));
    await migrated.close();
    await dir.delete(recursive: true);
  });
  group('buoni pasto', () {
    test('attivarli crea il conto e la categoria, una volta sola', () async {
      final id = await db.enableMealVouchers();
      expect(await db.enableMealVouchers(), id);
      final accounts = await db.getAccounts();
      expect(accounts, hasLength(2));
      final vouchers = accounts.firstWhere((a) => a.id == id);
      expect(vouchers.name, 'Buoni pasto');
      expect(vouchers.kind, AccountKind.mealVoucher);
      final cats = (await db.getCategories())
          .where((c) => c.name == 'Buoni pasto')
          .toList();
      expect(cats.single.type, TxType.income);
    });

    test('riusa un conto "Buoni pasto" esistente e ne tiene uno solo', () async {
      final existing = await db.createAccount(
        name: 'buoni pasto',
        iconKey: 'ticket',
        color: 0xFFF97316,
      );
      expect(await db.enableMealVouchers(), existing);
      final main = (await db.getAccounts()).firstWhere((a) => a.id != existing);
      await db.setMealVoucherAccount(main.id);
      final kinds = {for (final a in await db.getAccounts()) a.id: a.kind};
      expect(kinds[main.id], AccountKind.mealVoucher);
      expect(kinds[existing], AccountKind.standard);
      await db.setMealVoucherAccount(null);
      expect(
        (await db.getAccounts()).every((a) => a.kind == AccountKind.standard),
        isTrue,
      );
    });

    test('spesa da 180 €: 140 € in buoni e 40 € dal conto principale', () async {
      final main = (await db.getAccounts()).single.id;
      final vouchers = await db.enableMealVouchers();
      await db.addTransaction(
        type: TxType.income,
        amountCents: 16000, // 20 buoni da 8 €
        categoryId: await db.ensureMealVoucherCategory(),
        accountId: vouchers,
        date: DateTime(2026, 11, 2),
      );
      await db.addTransaction(
        type: TxType.income,
        amountCents: 100000,
        categoryId: (await cat('Stipendio')).id,
        accountId: main,
        date: DateTime(2026, 11, 1),
      );
      final id = await db.addTransaction(
        type: TxType.expense,
        amountCents: 18000,
        categoryId: (await cat('Spesa')).id,
        accountId: main,
        voucherAccountId: vouchers,
        voucherCents: 14000,
        date: DateTime(2026, 11, 7),
        note: 'Spesa grande',
      );

      final balances = await db.watchAccountBalances().first;
      expect(balances[main], 100000 - 4000);
      expect(balances[vouchers], 16000 - 14000);
      final before =
          await db.watchAccountBalances(before: DateTime(2026, 11, 7)).first;
      expect(before[vouchers], 16000);
      expect(await db.countAccountUsage(vouchers), 2);
      expect(await db.countAccountUsage(main), 2);

      final txs = await db
          .watchTransactionsBetween(DateTime(2026, 11), DateTime(2026, 12))
          .first;
      final split = txs.firstWhere((t) => t.tx.id == id);
      expect(split.voucherAccount?.id, vouchers);
      expect(split.accountCents, 4000);
      expect(
        txs.where((t) => t.tx.id != id).every((t) => !t.usesVouchers),
        isTrue,
      );

      // Modificandola in modo che i buoni coprano tutto, la spesa passa
      // interamente sul conto dei buoni.
      await db.updateTransaction(split.tx.copyWith(voucherCents: 18000));
      final full = (await db
              .watchTransactionsBetween(DateTime(2026, 11), DateTime(2026, 12))
              .first)
          .firstWhere((t) => t.tx.id == id);
      expect(full.account.id, vouchers);
      expect(full.usesVouchers, isFalse);
      final after = await db.watchAccountBalances().first;
      expect(after[main], 100000);
      expect(after[vouchers], 16000 - 18000);
    });

    test('un\'entrata non può essere divisa con i buoni', () async {
      final main = (await db.getAccounts()).single.id;
      final vouchers = await db.enableMealVouchers();
      await db.addTransaction(
        type: TxType.income,
        amountCents: 5000,
        categoryId: (await cat('Rimborsi')).id,
        accountId: main,
        voucherAccountId: vouchers,
        voucherCents: 800,
        date: DateTime(2026, 11, 3),
      );
      final balances = await db.watchAccountBalances().first;
      expect(balances[main], 5000);
      expect(balances[vouchers], 0);
    });

    test('unendo il conto dei buoni al principale la spesa torna normale', () async {
      final main = (await db.getAccounts()).single.id;
      final vouchers = await db.enableMealVouchers();
      final card = await db.createAccount(
        name: 'Carta',
        iconKey: 'card',
        color: 0xFF0EA5E9,
      );
      await db.addTransaction(
        type: TxType.expense,
        amountCents: 18000,
        categoryId: (await cat('Spesa')).id,
        accountId: main,
        voucherAccountId: vouchers,
        voucherCents: 14000,
        date: DateTime(2026, 11, 7),
      );
      await db.addTransaction(
        type: TxType.expense,
        amountCents: 3000,
        categoryId: (await cat('Ristoranti e bar')).id,
        accountId: card,
        voucherAccountId: vouchers,
        voucherCents: 1600,
        date: DateTime(2026, 11, 8),
      );
      final before = await db.watchAccountBalances().first;

      await db.deleteAccount(vouchers, mergeInto: main);

      final after = await db.watchAccountBalances().first;
      expect(after[main], before[main]! + before[vouchers]!);
      expect(after[card], before[card]);
      final txs = await db
          .watchTransactionsBetween(DateTime(2000), DateTime(2100))
          .first;
      final grocery = txs.firstWhere((t) => t.tx.amountCents == 18000);
      expect(grocery.usesVouchers, isFalse);
      expect(grocery.tx.voucherAccountId, isNull);
      final dinner = txs.firstWhere((t) => t.tx.amountCents == 3000);
      expect(dinner.voucherAccount?.id, main);
      expect(dinner.voucherCents, 1600);
    });
  });

  test('migrazione v2 -> v3: conti e movimenti restano, buoni a zero', () async {
    final dir = await Directory.systemTemp.createTemp('financee_migr_');
    final file = File('${dir.path}/v2.sqlite');
    final raw = sqlite3.open(file.path);
    raw.execute(_schemaV2);
    raw.execute(
      "INSERT INTO categories (id, name, type, icon_key, color) "
      "VALUES (1, 'Spesa', 0, 'cart', 4280401502)",
    );
    raw.execute(
      "INSERT INTO accounts (id, name, icon_key, color, initial_balance_cents) "
      "VALUES (1, 'Conto principale', 'bank', 4284703473, 10000), "
      "(2, 'Buoni pasto', 'wallet', 4294538774, 16000)",
    );
    raw.execute(
      "INSERT INTO transactions "
      "(type, amount_cents, category_id, account_id, date, note) "
      "VALUES (0, 4520, 1, 1, 1793833200, 'Esselunga'), "
      "(0, 800, 1, 2, 1793919600, '')",
    );
    raw.execute('PRAGMA user_version = 2');
    raw.close();

    final migrated = AppDatabase(NativeDatabase(file));
    final accounts = await migrated.getAccounts();
    expect(accounts.map((a) => a.name), ['Conto principale', 'Buoni pasto']);
    expect(accounts.every((a) => a.kind == AccountKind.standard), isTrue);
    final txs = await migrated
        .watchTransactionsBetween(DateTime(2000), DateTime(2100))
        .first;
    expect(txs, hasLength(2));
    expect(txs.every((t) => !t.usesVouchers && t.tx.voucherCents == 0), isTrue);
    final balances = await migrated.watchAccountBalances().first;
    expect(balances[1], 10000 - 4520);
    expect(balances[2], 16000 - 800);
    // Il conto "Buoni pasto" già esistente diventa quello dei buoni.
    expect(await migrated.enableMealVouchers(), 2);
    await migrated.close();
    await dir.delete(recursive: true);
  });
  group('debiti', () {
    test('le spese collegate riducono il debito, le entrate no', () async {
      final main = (await db.getAccounts()).single.id;
      final rate = await cat('Trasporti');
      final auto = await db.createDebt(
        name: 'Prestito auto',
        amountCents: 500000,
        iconKey: 'car',
        color: 0xFF0EA5E9,
      );
      final marco = await db.createDebt(
        name: 'Soldi da Marco',
        amountCents: 10000,
        iconKey: 'person',
        color: 0xFFF43F5E,
      );
      for (final (day, cents) in [(5, 25000), (15, 25000)]) {
        await db.addTransaction(
          type: TxType.expense,
          amountCents: cents,
          categoryId: rate.id,
          accountId: main,
          date: DateTime(2026, 11, day),
          note: 'Rata',
          debtId: auto,
        );
      }
      // Un'entrata non può essere un pagamento: il collegamento si perde.
      await db.addTransaction(
        type: TxType.income,
        amountCents: 10000,
        categoryId: (await cat('Altre entrate')).id,
        accountId: main,
        date: DateTime(2026, 11, 2),
        debtId: marco,
      );
      final marcoPayment = await db.addTransaction(
        type: TxType.expense,
        amountCents: 10000,
        categoryId: (await cat('Altre spese')).id,
        accountId: main,
        date: DateTime(2026, 11, 20),
        debtId: marco,
      );

      final payments = await db.watchDebtPayments().first;
      expect(payments[auto]?.paidCents, 50000);
      expect(payments[auto]?.count, 2);
      expect(payments[auto]?.lastDate, DateTime(2026, 11, 15));
      expect(payments[marco]?.paidCents, 10000);

      final autoTxs = await db.watchDebtTransactions(auto).first;
      expect(autoTxs.map((t) => t.tx.date.day), [15, 5]); // dal più recente
      expect(autoTxs.every((t) => t.debt?.name == 'Prestito auto'), isTrue);
      final month = await db
          .watchTransactionsBetween(DateTime(2026, 11), DateTime(2026, 12))
          .first;
      expect(month.where((t) => t.debt != null), hasLength(3));

      // Trasformare il pagamento in un'entrata lo scollega dal debito.
      final tx = (await db.watchDebtTransactions(marco).first).single.tx;
      expect(tx.id, marcoPayment);
      await db.updateTransaction(tx.copyWith(type: TxType.income));
      expect((await db.watchDebtPayments().first)[marco], isNull);
    });

    test('eliminando un debito i pagamenti restano, scollegati', () async {
      final main = (await db.getAccounts()).single.id;
      final id = await db.createDebt(
        name: 'Telefono a rate',
        amountCents: 60000,
        iconKey: 'phone',
        color: 0xFF8B5CF6,
      );
      await db.addTransaction(
        type: TxType.expense,
        amountCents: 5000,
        categoryId: (await cat('Abbonamenti')).id,
        accountId: main,
        date: DateTime(2026, 11, 3),
        debtId: id,
      );
      await db.deleteDebt(id);
      expect(await db.getDebts(), isEmpty);
      final txs = await db
          .watchTransactionsBetween(DateTime(2026, 11), DateTime(2026, 12))
          .first;
      expect(txs.single.tx.debtId, isNull);
      expect(txs.single.debt, isNull);
      expect((await db.watchAccountBalances().first)[main], -5000);
    });
  });

  test('migrazione v3 -> v4: movimenti senza debito, debiti utilizzabili', () async {
    final dir = await Directory.systemTemp.createTemp('financee_migr_');
    final file = File('${dir.path}/v3.sqlite');
    final raw = sqlite3.open(file.path);
    raw.execute(_schemaV3);
    raw.execute(
      "INSERT INTO categories (id, name, type, icon_key, color) "
      "VALUES (1, 'Spesa', 0, 'cart', 4280401502)",
    );
    raw.execute(
      "INSERT INTO accounts (id, name, icon_key, color, initial_balance_cents, kind) "
      "VALUES (1, 'Conto principale', 'bank', 4284703473, 10000, 0), "
      "(2, 'Buoni pasto', 'ticket', 4294538774, 16000, 1)",
    );
    raw.execute(
      "INSERT INTO transactions "
      "(type, amount_cents, category_id, account_id, voucher_account_id, voucher_cents, date, note) "
      "VALUES (0, 18000, 1, 1, 2, 14000, 1793833200, 'Spesa grande')",
    );
    raw.execute('PRAGMA user_version = 3');
    raw.close();

    final migrated = AppDatabase(NativeDatabase(file));
    final txs = await migrated
        .watchTransactionsBetween(DateTime(2000), DateTime(2100))
        .first;
    expect(txs.single.voucherCents, 14000);
    expect(txs.single.tx.debtId, isNull);
    final balances = await migrated.watchAccountBalances().first;
    expect(balances[1], 10000 - 4000);
    expect(balances[2], 16000 - 14000);
    final id = await migrated.createDebt(
      name: 'Prestito',
      amountCents: 100000,
      iconKey: 'loan',
      color: 0xFFF43F5E,
    );
    await migrated.updateTransaction(txs.single.tx.copyWith(debtId: Value(id)));
    expect((await migrated.watchDebtPayments().first)[id]?.paidCents, 18000);
    await migrated.close();
    await dir.delete(recursive: true);
  });

  group('obiettivi di risparmio', () {
    test('variazioni del conto coerenti con il saldo, buoni compresi', () async {
      final main = (await db.getAccounts()).single.id;
      final savings = await db.createAccount(
        name: 'Risparmi',
        iconKey: 'piggy',
        color: 0xFF10B981,
        initialBalanceCents: 100000,
      );
      final vouchers = await db.enableMealVouchers();
      await db.addTransfer(
        fromAccountId: main,
        toAccountId: savings,
        amountCents: 30000,
        date: DateTime(2026, 9, 15),
      );
      await db.addTransfer(
        fromAccountId: savings,
        toAccountId: main,
        amountCents: 5000,
        date: DateTime(2026, 10, 2),
      );
      await db.addTransaction(
        type: TxType.income,
        amountCents: 2000,
        categoryId: (await cat('Altre entrate')).id,
        accountId: savings,
        date: DateTime(2026, 10, 20),
      );
      // Spesa divisa: 40 € dal conto risparmi e 140 € dai buoni.
      await db.addTransaction(
        type: TxType.expense,
        amountCents: 18000,
        categoryId: (await cat('Spesa')).id,
        accountId: savings,
        voucherAccountId: vouchers,
        voucherCents: 14000,
        date: DateTime(2026, 11, 3),
      );
      final id = await db.createSavingsGoal(
        accountId: savings,
        name: 'Fondo emergenza',
        targetCents: 500000,
        deadline: DateTime(2027, 12, 31, 18),
      );
      await db.createSavingsGoal(
        accountId: vouchers,
        name: 'Buoni',
        targetCents: 1000,
      );

      final goal = (await db.getSavingsGoals()).firstWhere((g) => g.id == id);
      expect(goal.deadline, DateTime(2027, 12, 31));
      final deltas = await db.watchGoalAccountDeltas().first;
      expect(deltas[savings], [
        (DateTime(2026, 9, 15), 30000),
        (DateTime(2026, 10, 2), -5000),
        (DateTime(2026, 10, 20), 2000),
        (DateTime(2026, 11, 3), -4000),
      ]);
      expect(deltas[vouchers], [(DateTime(2026, 11, 3), -14000)]);
      expect(deltas.containsKey(main), isFalse);
      final balances = await db.watchAccountBalances().first;
      final summaries = GoalSummary.combine(
        goals: await db.getSavingsGoals(),
        accounts: await db.getAccounts(),
        deltas: deltas,
        today: DateTime(2026, 11, 8),
      );
      expect(summaries, hasLength(2));
      for (final s in summaries) {
        expect(s.balanceCents, balances[s.accountId], reason: s.account.name);
      }
      // Un conto ha al massimo un obiettivo.
      await expectLater(
        db.createSavingsGoal(accountId: savings, name: 'Altro', targetCents: 1),
        throwsA(anything),
      );
    });

    test('unendo i conti l\'obiettivo passa al conto rimasto', () async {
      final main = (await db.getAccounts()).single.id;
      final a = await db.createAccount(name: 'Vacanze', iconKey: 'travel', color: 0);
      final b = await db.createAccount(name: 'Auto', iconKey: 'car', color: 0);
      await db.createSavingsGoal(accountId: a, name: 'Giappone', targetCents: 300000);
      await db.createSavingsGoal(accountId: b, name: 'Auto nuova', targetCents: 900000);
      // Il conto principale non ha obiettivi: quello di "Vacanze" passa lì.
      await db.deleteAccount(a, mergeInto: main);
      var goals = await db.getSavingsGoals();
      expect(
        goals.map((g) => (g.name, g.accountId)),
        containsAll([('Giappone', main), ('Auto nuova', b)]),
      );
      // Ora il conto principale ne ha già uno: quello di "Auto" si elimina.
      await db.deleteAccount(b, mergeInto: main);
      goals = await db.getSavingsGoals();
      expect(goals.single.name, 'Giappone');
      final c = await db.createAccount(name: 'Vuoto', iconKey: 'bank', color: 0);
      await db.createSavingsGoal(accountId: c, name: 'Prova', targetCents: 100);
      await db.deleteAccount(c);
      expect((await db.getSavingsGoals()).single.name, 'Giappone');
    });
  });

  test('debiti a rate: totale calcolato e cambio di modalità', () async {
    final id = await db.createDebt(
      name: 'Prestito auto',
      amountCents: 0,
      iconKey: 'car',
      color: 0xFF6366F1,
      kind: DebtKind.installments,
      installmentCents: 25000,
      installmentCount: 60,
      paidInstallments: 12,
    );
    final created = (await db.getDebts()).single;
    expect(created.id, id);
    expect(created.kind, DebtKind.installments);
    expect(created.amountCents, 1500000);
    expect(created.installmentCents, 25000);
    expect(created.installmentCount, 60);
    expect(created.paidInstallments, 12);

    // Modificando la rata il totale si ricalcola.
    await db.updateDebt(created.copyWith(installmentCents: const Value(30000)));
    expect((await db.getDebts()).single.amountCents, 1800000);

    // Passando a importo totale i campi delle rate si azzerano.
    await db.updateDebt(
      (await db.getDebts()).single.copyWith(
        kind: DebtKind.amount,
        amountCents: 900000,
      ),
    );
    final plain = (await db.getDebts()).single;
    expect(plain.amountCents, 900000);
    expect(plain.installmentCents, isNull);
    expect(plain.installmentCount, isNull);
    expect(plain.paidInstallments, 0);

    // Un debito a importo ignora eventuali campi delle rate.
    await db.createDebt(
      name: 'Klarna',
      amountCents: 30000,
      iconKey: 'card',
      color: 0,
      installmentCents: 10000,
      installmentCount: 3,
      paidInstallments: 1,
    );
    final klarna = (await db.getDebts()).last;
    expect(klarna.kind, DebtKind.amount);
    expect(klarna.amountCents, 30000);
    expect(klarna.installmentCount, isNull);
    expect(klarna.paidInstallments, 0);
  });

  test('migrazione v5 -> v6: debiti esistenti a importo totale', () async {
    final dir = await Directory.systemTemp.createTemp('financee_migr_');
    final file = File('${dir.path}/v5.sqlite');
    final raw = sqlite3.open(file.path);
    raw.execute(_schemaV5);
    raw.execute(
      "INSERT INTO categories (id, name, type, icon_key, color) "
      "VALUES (1, 'Spesa', 0, 'cart', 4280401502)",
    );
    raw.execute(
      "INSERT INTO accounts (id, name, icon_key, color, initial_balance_cents, kind) "
      "VALUES (1, 'Conto principale', 'bank', 4284703473, 10000, 0)",
    );
    raw.execute(
      "INSERT INTO debts (id, name, amount_cents, icon_key, color) "
      "VALUES (1, 'Prestito', 100000, 'loan', 4294198366)",
    );
    raw.execute(
      "INSERT INTO transactions (type, amount_cents, category_id, account_id, debt_id, date, note) "
      "VALUES (0, 25000, 1, 1, 1, 1793833200, 'Rata')",
    );
    raw.execute(
      "INSERT INTO savings_goals (account_id, name, target_cents) "
      "VALUES (1, 'Fondo', 500000)",
    );
    raw.execute('PRAGMA user_version = 5');
    raw.close();

    final migrated = AppDatabase(NativeDatabase(file));
    final debt = (await migrated.getDebts()).single;
    expect(debt.kind, DebtKind.amount);
    expect(debt.installmentCents, isNull);
    expect(debt.paidInstallments, 0);
    expect((await migrated.watchDebtPayments().first)[1]?.paidCents, 25000);
    expect((await migrated.getSavingsGoals()).single.name, 'Fondo');
    await migrated.createDebt(
      name: 'Mutuo',
      amountCents: 0,
      iconKey: 'home',
      color: 0,
      kind: DebtKind.installments,
      installmentCents: 60000,
      installmentCount: 240,
      paidInstallments: 30,
    );
    expect((await migrated.getDebts()).last.amountCents, 14400000);
    await migrated.close();
    await dir.delete(recursive: true);
  });

  test('migrazione v4 -> v5: obiettivi utilizzabili, dati invariati', () async {
    final dir = await Directory.systemTemp.createTemp('financee_migr_');
    final file = File('${dir.path}/v4.sqlite');
    final raw = sqlite3.open(file.path);
    raw.execute(_schemaV4);
    raw.execute(
      "INSERT INTO categories (id, name, type, icon_key, color) "
      "VALUES (1, 'Spesa', 0, 'cart', 4280401502)",
    );
    raw.execute(
      "INSERT INTO accounts (id, name, icon_key, color, initial_balance_cents, kind) "
      "VALUES (1, 'Conto principale', 'bank', 4284703473, 10000, 0), "
      "(2, 'Risparmi', 'piggy', 4279286145, 250000, 0)",
    );
    raw.execute(
      "INSERT INTO debts (id, name, amount_cents, icon_key, color) "
      "VALUES (1, 'Prestito', 100000, 'loan', 4294198366)",
    );
    raw.execute(
      "INSERT INTO transactions (type, amount_cents, category_id, account_id, debt_id, date, note) "
      "VALUES (0, 25000, 1, 1, 1, 1793833200, 'Rata')",
    );
    raw.execute('PRAGMA user_version = 4');
    raw.close();

    final migrated = AppDatabase(NativeDatabase(file));
    expect((await migrated.watchDebtPayments().first)[1]?.paidCents, 25000);
    expect(await migrated.getSavingsGoals(), isEmpty);
    await migrated.createSavingsGoal(accountId: 2, name: 'Casa', targetCents: 1000000);
    final goals = GoalSummary.combine(
      goals: await migrated.getSavingsGoals(),
      accounts: await migrated.getAccounts(),
      deltas: await migrated.watchGoalAccountDeltas().first,
      today: DateTime(2026, 11, 8),
    );
    expect(goals.single.balanceCents, 250000);
    expect(goals.single.progress, closeTo(0.25, 1e-9));
    await migrated.close();
    await dir.delete(recursive: true);
  });
}

const _schemaV1 = '''
CREATE TABLE "categories" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "type" INTEGER NOT NULL, "icon_key" TEXT NOT NULL, "color" INTEGER NOT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "transactions" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "type" INTEGER NOT NULL, "amount_cents" INTEGER NOT NULL, "category_id" INTEGER NOT NULL REFERENCES categories (id), "date" INTEGER NOT NULL, "note" TEXT NOT NULL DEFAULT '', "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE INDEX transactions_date_idx ON transactions (date);
''';

const _schemaV2 = '''
CREATE TABLE "accounts" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "icon_key" TEXT NOT NULL, "color" INTEGER NOT NULL, "initial_balance_cents" INTEGER NOT NULL DEFAULT 0, "sort_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "categories" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "type" INTEGER NOT NULL, "icon_key" TEXT NOT NULL, "color" INTEGER NOT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "transactions" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "type" INTEGER NOT NULL, "amount_cents" INTEGER NOT NULL, "category_id" INTEGER NOT NULL REFERENCES categories (id), "account_id" INTEGER NOT NULL REFERENCES accounts (id), "date" INTEGER NOT NULL, "note" TEXT NOT NULL DEFAULT '', "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "transfers" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "from_account_id" INTEGER NOT NULL REFERENCES accounts (id), "to_account_id" INTEGER NOT NULL REFERENCES accounts (id), "amount_cents" INTEGER NOT NULL, "date" INTEGER NOT NULL, "note" TEXT NOT NULL DEFAULT '', "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE INDEX transactions_date_idx ON transactions (date);
CREATE INDEX transactions_account_idx ON transactions (account_id);
CREATE INDEX transfers_date_idx ON transfers (date);
''';

const _schemaV3 = '''
CREATE TABLE "accounts" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "icon_key" TEXT NOT NULL, "color" INTEGER NOT NULL, "initial_balance_cents" INTEGER NOT NULL DEFAULT 0, "sort_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "kind" INTEGER NOT NULL DEFAULT 0);
CREATE TABLE "categories" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "type" INTEGER NOT NULL, "icon_key" TEXT NOT NULL, "color" INTEGER NOT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "transactions" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "type" INTEGER NOT NULL, "amount_cents" INTEGER NOT NULL, "category_id" INTEGER NOT NULL REFERENCES categories (id), "account_id" INTEGER NOT NULL REFERENCES accounts (id), "voucher_account_id" INTEGER NULL REFERENCES accounts (id), "voucher_cents" INTEGER NOT NULL DEFAULT 0, "date" INTEGER NOT NULL, "note" TEXT NOT NULL DEFAULT '', "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "transfers" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "from_account_id" INTEGER NOT NULL REFERENCES accounts (id), "to_account_id" INTEGER NOT NULL REFERENCES accounts (id), "amount_cents" INTEGER NOT NULL, "date" INTEGER NOT NULL, "note" TEXT NOT NULL DEFAULT '', "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE INDEX transactions_date_idx ON transactions (date);
CREATE INDEX transactions_account_idx ON transactions (account_id);
CREATE INDEX transfers_date_idx ON transfers (date);
''';

const _schemaV4 = '''
CREATE TABLE "accounts" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "icon_key" TEXT NOT NULL, "color" INTEGER NOT NULL, "initial_balance_cents" INTEGER NOT NULL DEFAULT 0, "sort_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)), "kind" INTEGER NOT NULL DEFAULT 0);
CREATE TABLE "categories" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "type" INTEGER NOT NULL, "icon_key" TEXT NOT NULL, "color" INTEGER NOT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "debts" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "amount_cents" INTEGER NOT NULL, "icon_key" TEXT NOT NULL, "color" INTEGER NOT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "transactions" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "type" INTEGER NOT NULL, "amount_cents" INTEGER NOT NULL, "category_id" INTEGER NOT NULL REFERENCES categories (id), "account_id" INTEGER NOT NULL REFERENCES accounts (id), "voucher_account_id" INTEGER NULL REFERENCES accounts (id), "voucher_cents" INTEGER NOT NULL DEFAULT 0, "debt_id" INTEGER NULL REFERENCES debts (id), "date" INTEGER NOT NULL, "note" TEXT NOT NULL DEFAULT '', "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "transfers" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "from_account_id" INTEGER NOT NULL REFERENCES accounts (id), "to_account_id" INTEGER NOT NULL REFERENCES accounts (id), "amount_cents" INTEGER NOT NULL, "date" INTEGER NOT NULL, "note" TEXT NOT NULL DEFAULT '', "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE INDEX transactions_date_idx ON transactions (date);
CREATE INDEX transactions_account_idx ON transactions (account_id);
CREATE INDEX transfers_date_idx ON transfers (date);
''';

/// Schema v5: come il v4 più gli obiettivi di risparmio.
const _schemaV5 = '''
$_schemaV4
CREATE TABLE "savings_goals" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "account_id" INTEGER NOT NULL UNIQUE REFERENCES accounts (id), "name" TEXT NOT NULL, "target_cents" INTEGER NOT NULL, "deadline" INTEGER NULL, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
''';
