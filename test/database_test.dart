import 'dart:io';

import 'package:drift/native.dart';
import 'package:financiee/data/app_database.dart';
import 'package:financiee/data/default_categories.dart';
import 'package:financiee/data/models.dart';
import 'package:financiee/data/sample_data.dart';
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
    final dir = await Directory.systemTemp.createTemp('financiee_migr_');
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
}

const _schemaV1 = '''
CREATE TABLE "categories" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL, "type" INTEGER NOT NULL, "icon_key" TEXT NOT NULL, "color" INTEGER NOT NULL, "sort_order" INTEGER NOT NULL DEFAULT 0, "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE TABLE "transactions" ("id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, "type" INTEGER NOT NULL, "amount_cents" INTEGER NOT NULL, "category_id" INTEGER NOT NULL REFERENCES categories (id), "date" INTEGER NOT NULL, "note" TEXT NOT NULL DEFAULT '', "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)));
CREATE INDEX transactions_date_idx ON transactions (date);
''';
