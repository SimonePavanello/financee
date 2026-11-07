import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:financiee/data/app_database.dart';
import 'package:financiee/data/backup/backup.dart';
import 'package:financiee/data/sample_data.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:test/test.dart';

// Solo dati di prova: nessun dato reale nei test.

void main() {
  late AppDatabase db;

  setUpAll(() {
    // Il test del ripristino usa di proposito due database in memoria.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    return initializeDateFormatting('it_IT');
  });
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Riempie il database con un po' di tutto: dati di esempio, buoni pasto,
  /// un debito con un pagamento e un obiettivo con scadenza.
  Future<void> fill(AppDatabase target) async {
    await insertSampleData(target, now: DateTime(2026, 11, 8));
    final accounts = await target.getAccounts();
    final main = accounts.first.id;
    final savings = accounts.firstWhere((a) => a.name == 'Risparmi').id;
    final vouchers = await target.enableMealVouchers();
    final spesa = (await target.getCategories())
        .firstWhere((c) => c.name == 'Spesa');
    final debt = await target.createDebt(
      name: 'Prestito auto',
      amountCents: 500000,
      iconKey: 'car',
      color: 0xFFF43F5E,
    );
    await target.addTransaction(
      type: TxType.expense,
      amountCents: 18000,
      categoryId: spesa.id,
      accountId: main,
      voucherAccountId: vouchers,
      voucherCents: 14000,
      date: DateTime(2026, 11, 7),
      note: 'Spesa con "virgolette", accenti èàù e €',
      debtId: debt,
    );
    await target.createSavingsGoal(
      accountId: savings,
      name: 'Fondo emergenza',
      targetCents: 1000000,
      deadline: DateTime(2027, 12, 31),
    );
  }

  /// Tutto il contenuto del database, tabella per tabella.
  Future<Map<String, List<List<Object?>>>> dump(AppDatabase target) async {
    final b = await target.createBackup();
    return {for (final e in b.tables.entries) e.key: e.value.rows};
  }

  test('nome del file con la data', () {
    expect(backupFileName(DateTime(2026, 3, 7, 22)), 'financiee-backup-2026-03-07.json');
  });

  test('esporta e ripristina tutto identico, sostituendo i dati presenti', () async {
    await fill(db);
    final before = await dump(db);
    final balances = await db.watchAccountBalances().first;
    final backup = await db.createBackup(
      settings: {'meal_voucher_value_cents': 750},
      now: DateTime(2026, 11, 8, 10, 30),
    );
    final text = backup.encode();

    // Un altro dispositivo con dati diversi.
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.createAccount(name: 'Da sostituire', iconKey: 'bank', color: 0);
    await other.createDebt(name: 'Vecchio', amountCents: 1, iconKey: 'loan', color: 0);

    final parsed = BackupFile.parse(text, currentSchemaVersion: other.schemaVersion);
    expect(parsed.createdAt, DateTime(2026, 11, 8, 10, 30));
    expect(parsed.schemaVersion, db.schemaVersion);
    expect(parsed.settings, {'meal_voucher_value_cents': 750});
    expect(parsed.accounts, before['accounts']!.length);
    expect(parsed.transactions, before['transactions']!.length);
    expect(parsed.debts, 1);
    expect(parsed.savingsGoals, 1);
    expect(parsed.dateRange!.$2, DateTime(2026, 11, 8));

    await other.restoreBackup(parsed);
    expect(await dump(other), before);
    expect(await other.watchAccountBalances().first, balances);
    final txs = await other
        .watchTransactionsBetween(DateTime(2026, 11, 7), DateTime(2026, 11, 8))
        .first;
    final split = txs.firstWhere((t) => t.usesVouchers);
    expect(split.tx.note, 'Spesa con "virgolette", accenti èàù e €');
    expect(split.debt?.name, 'Prestito auto');
    expect(split.voucherCents, 14000);
    expect((await other.getSavingsGoals()).single.deadline, DateTime(2027, 12, 31));

    // Dopo il ripristino i nuovi dati non si scontrano con gli id importati.
    final id = await other.createAccount(name: 'Nuovo', iconKey: 'bank', color: 0);
    expect(before['accounts']!.map((r) => r.first), isNot(contains(id)));
  });

  test('un backup senza obiettivi né colonne nuove usa i valori predefiniti', () async {
    await fill(db);
    final full = await db.createBackup();
    final accounts = full.tables['accounts']!;
    final kind = accounts.columns.indexOf('kind');
    // Come un backup di una versione precedente: niente obiettivi e conti
    // senza la colonna "kind".
    final old = BackupFile(
      createdAt: full.createdAt,
      schemaVersion: 4,
      tables: {
        for (final e in full.tables.entries)
          if (e.key != 'savings_goals') e.key: e.value,
        'accounts': BackupTable(
          [...accounts.columns]..removeAt(kind),
          [for (final r in accounts.rows) [...r]..removeAt(kind)],
        ),
      },
    );
    final parsed = BackupFile.parse(old.encode(), currentSchemaVersion: db.schemaVersion);
    await db.restoreBackup(parsed);
    expect(await db.getSavingsGoals(), isEmpty);
    final restored = await db.getAccounts();
    expect(restored.length, accounts.rows.length);
    expect(restored.every((a) => a.kind == AccountKind.standard), isTrue);
  });

  test('riferimenti non validi: errore e dati attuali intatti', () async {
    await fill(db);
    final before = await dump(db);
    final backup = await db.createBackup();
    final txs = backup.tables['transactions']!;
    final accountCol = txs.columns.indexOf('account_id');
    final broken = BackupFile(
      createdAt: backup.createdAt,
      schemaVersion: backup.schemaVersion,
      tables: {
        ...backup.tables,
        'transactions': BackupTable(txs.columns, [
          for (final (i, r) in txs.rows.indexed)
            i == 0 ? ([...r]..[accountCol] = 9999) : r,
        ]),
      },
    );
    await expectLater(
      db.restoreBackup(broken),
      throwsA(isA<BackupIntegrityException>()),
    );
    expect(await dump(db), before);
  });

  group('file non validi', () {
    String encoded(Map<String, Object?> Function(Map<String, Object?>) edit) {
      final base = jsonDecode(
        BackupFile(
          createdAt: DateTime(2026, 11, 8),
          schemaVersion: 5,
          tables: {
            'accounts': const BackupTable(['id', 'name'], [
              [1, 'Conto'],
            ]),
            'categories': const BackupTable(['id', 'name'], []),
          },
        ).encode(),
      ) as Map<String, Object?>;
      return jsonEncode(edit(base));
    }

    void rejects(String text, Object message) => expect(
      () => BackupFile.parse(text, currentSchemaVersion: 5),
      throwsA(isA<FormatException>().having((e) => e.message, 'message', message)),
    );

    test('accetta il file di base', () {
      final b = BackupFile.parse(encoded((j) => j), currentSchemaVersion: 5);
      expect(b.accounts, 1);
      expect(b.transactions, 0);
      expect(b.dateRange, isNull);
    });

    test('rifiuta file che non sono backup, danneggiati o più recenti', () {
      const notBackup = 'Il file non è un backup di Financiee.';
      const damaged = 'Il backup è incompleto o danneggiato.';
      rejects('id;nome\n1;Conto', notBackup);
      rejects('[1, 2]', notBackup);
      rejects(encoded((j) => {...j, 'format': 'sossoldi'}), notBackup);
      rejects(
        encoded((j) => {...j, 'schemaVersion': 6}),
        startsWith('Il backup è stato creato con una versione più recente'),
      );
      rejects(
        encoded((j) => {...j, 'formatVersion': 2}),
        startsWith('Il backup è stato creato con una versione più recente'),
      );
      rejects(encoded((j) => {...j}..remove('tables')), damaged);
      rejects(encoded((j) => {...j, 'createdAt': 'ieri'}), damaged);
      Map<String, Object?> withAccounts(Map<String, Object?> j, Object? accounts) => {
        ...j,
        'tables': {...(j['tables'] as Map<String, Object?>), 'accounts': accounts},
      };
      // Riga più corta delle colonne, valore annidato, niente colonna id.
      rejects(encoded((j) => withAccounts(j, {'columns': ['id', 'name'], 'rows': [[1]]})), damaged);
      rejects(
        encoded((j) => withAccounts(j, {'columns': ['id', 'name'], 'rows': [[1, ['x']]]})),
        damaged,
      );
      rejects(encoded((j) => withAccounts(j, {'columns': ['name'], 'rows': [['x']]})), damaged);
      rejects(
        encoded((j) => withAccounts(j, {'columns': ['id', 'name'], 'rows': []})),
        'Il backup non contiene nessun conto.',
      );
    });

    test('tiene solo le impostazioni previste', () {
      final b = BackupFile.parse(
        encoded((j) => {
          ...j,
          'settings': {
            'meal_voucher_value_cents': 800,
            'theme_mode': 'dark',
            'meal_voucher_last_load': [1],
          },
        }),
        currentSchemaVersion: 5,
      );
      expect(b.settings, {'meal_voucher_value_cents': 800});
    });
  });
}
