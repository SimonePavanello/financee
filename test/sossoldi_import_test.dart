import 'package:drift/native.dart';
import 'package:financee/data/app_database.dart';
import 'package:financee/data/import/csv_parser.dart';
import 'package:financee/data/import/sossoldi_import.dart';
import 'package:test/test.dart';

// Export fittizio nello stesso formato di Sossoldi (nessun dato reale).
const _header =
    'table_name,id,name,symbol,color,startingValue,active,mainAccount,createdAt,updatedAt,countNetWorth,position,deletedAt,date,amount,type,note,idCategory,idBankAccount,idBankAccountTransfer,recurring,idRecurringTransaction,parent,amountLimit,code,mainCurrency';

String _account(int id, String name, String symbol, String start,
        {bool active = true, bool main = false, int position = 0}) =>
    'bankAccount,$id,$name,$symbol,3,$start,${active ? 1 : 0},${main ? 1 : 0},2025-10-03T01:15:46.930774,2025-10-03T01:17:13.897605,1,$position,,,,,,,,,,,,,,';

String _category(int id, String name, String type) =>
    'categoryTransaction,$id,$name,home,0,,,,2025-10-03T01:12:44.372027,2025-10-03T01:12:44.372051,,$id,,,,$type,,,,,,,,,,';

String _tx(int id, String date, String amount, String type, String note,
        String category, int account,
        {String to = '', String deleted = ''}) =>
    'transaction,$id,,,,,,,${date}T10:00:00.000000,${date}T10:00:00.000000,,,$deleted,${date}T00:00:00.000,$amount,$type,$note,$category,$account,$to,0,,,,,';

final _csv = [
  _header,
  _account(1, 'Savings', 'savings', '674.0', position: 0),
  _account(2, 'Income', 'payments', '29.14', main: true, position: 1),
  _account(3, 'contanti', 'payments', '60.0', active: false, position: 2),
  _category(1, 'Dining Auto', 'OUT'),
  _category(2, 'Bar', 'OUT'),
  _category(3, 'Salary', 'IN'),
  _category(4, 'Parents', 'IN'),
  _category(5, 'Parents ', 'OUT'),
  _category(6, 'Pesca', 'OUT'),
  _tx(1, '2026-01-10', '2000.0', 'IN', 'Stipendio', '3', 2),
  _tx(2, '2026-01-11', '12.5', 'OUT', '"Pizza, con amici"', '1', 2),
  _tx(3, '2026-01-11', '1.2', 'OUT', 'Caffè', '2', 2),
  _tx(4, '2026-01-12', '880.9400000000004', 'OUT', 'Reconciliation', '', 2),
  _tx(5, '2026-01-13', '650.0', 'TRSF', 'Risparmi', '', 2, to: '1'),
  _tx(6, '2026-01-14', '100.0', 'TRSF', 'Per rate', '2', 1, to: '2'),
  _tx(7, '2026-01-15', '50.0', 'IN', 'Soldi da papà', '4', 1),
  _tx(8, '2026-01-16', '30.0', 'OUT', 'Regalo', '5', 2),
  _tx(9, '2026-01-17', '45.0', 'OUT', 'Esca', '6', 2),
  _tx(10, '2026-01-18', '999.0', 'OUT', 'Cancellato', '6', 2,
      deleted: '2026-01-19T00:00:00.000'),
].join('\r\n');

void main() {
  group('parseCsv', () {
    test('virgolette, virgole e a capo nei campi, BOM e CRLF', () {
      final rows = parseCsv('﻿a,b,c\r\n1,"x, y","riga 1\nriga 2"\r\n2,"con ""virgolette""",\r\n\r\n');
      expect(rows, [
        ['a', 'b', 'c'],
        ['1', 'x, y', 'riga 1\nriga 2'],
        ['2', 'con "virgolette"', ''],
      ]);
    });
  });

  group('SossoldiExport', () {
    final export = SossoldiExport.parse(_csv);

    test('legge conti, categorie e movimenti (esclusi quelli eliminati)', () {
      expect(export.accounts.map((a) => a.name), ['Savings', 'Income', 'contanti']);
      expect(export.accounts[1].isMain, isTrue);
      expect(export.accounts[2].active, isFalse);
      expect(export.categories, hasLength(6));
      expect(export.movements, hasLength(9));
      expect(export.movements.map((m) => m.note), contains('Pizza, con amici'));
      expect(export.movements.firstWhere((m) => m.id == 4).amountCents, 88094);
      // Nei trasferimenti la categoria viene ignorata.
      expect(export.movements.firstWhere((m) => m.id == 6).categoryId, isNull);
    });

    test('calcola i saldi come Sossoldi', () {
      final b = export.balances;
      expect(b[1], 67400 + 65000 - 10000 + 5000); // Savings
      expect(b[2], 2914 + 200000 - 1250 - 120 - 88094 - 65000 + 10000 - 3000 - 4500);
      expect(b[3], 6000);
    });

    test('rifiuta un file che non è un export di Sossoldi', () {
      expect(() => SossoldiExport.parse('data;importo\n01/01/2026;10'),
          throwsA(isA<FormatException>()));
    });
  });

  group('import nel database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<SossoldiImportPlan> plan({required bool replace}) async =>
        SossoldiImportPlan.build(
          SossoldiExport.parse(_csv),
          existingCategories: await db.getCategories(),
          existingAccounts: await db.getAccounts(),
          existingAccountUsage: await db.watchAccountUsage().first,
          replaceExisting: replace,
        );

    Future<Map<String, int>> balancesByName() async {
      final balances = await db.watchAccountBalances().first;
      return {
        for (final a in await db.getAccounts()) a.name: balances[a.id] ?? 0,
      };
    }

    test('anteprima: conti saltati e mappatura delle categorie', () async {
      final p = await plan(replace: true);
      expect(p.accounts.map((a) => a.targetName), ['Risparmi', 'Conto principale']);
      expect(p.skippedAccounts.single.name, 'contanti');
      String target(String? source, TxType type) => p.categories
          .firstWhere((c) => c.sourceName == source && c.type == type)
          .targetName;
      expect(target('Dining Auto', TxType.expense), 'Ristoranti e bar');
      expect(target('Bar', TxType.expense), 'Ristoranti e bar');
      expect(target('Parents', TxType.income), 'Famiglia');
      expect(target('Parents', TxType.expense), 'Famiglia');
      expect(target('Pesca', TxType.expense), 'Pesca'); // non mappata: stesso nome
      expect(target(null, TxType.expense), 'Altre spese');
      expect(p.categories.firstWhere((c) => c.targetName == 'Ristoranti e bar').exists,
          isTrue);
      expect(p.newCategoryNames, containsAll(['Famiglia', 'Pesca']));
      expect(p.transactionCount, 7);
      expect(p.transferCount, 2);
    });

    test('sostituendo i dati i saldi tornano esattamente', () async {
      final cash = await db.createAccount(name: 'Contanti', iconKey: 'cash', color: 0, initialBalanceCents: 999);
      // Gli obiettivi dei conti sostituiti spariscono con i conti.
      await db.createSavingsGoal(accountId: cash, name: 'Cuscinetto', targetCents: 5000);
      final p = await plan(replace: true);
      final result = await db.importSossoldi(p);

      expect(result.balancesMatch, isTrue, reason: '${result.checks.map((c) => '${c.name} ${c.expectedCents}/${c.actualCents}')}');
      final accounts = await db.getAccounts();
      expect(accounts.map((a) => a.name), ['Risparmi', 'Conto principale']);
      final txs = await db.watchTransactionsBetween(DateTime(2000), DateTime(2100)).first;
      final transfers = await db.watchTransfersBetween(DateTime(2000), DateTime(2100)).first;
      expect(txs, hasLength(7));
      expect(transfers, hasLength(2));
      final risparmi = transfers.firstWhere((t) => t.transfer.note == 'Risparmi');
      expect(risparmi.from.name, 'Conto principale');
      expect(risparmi.to.name, 'Risparmi');
      expect(txs.where((t) => t.category.name == 'Ristoranti e bar'), hasLength(2));
      expect(txs.firstWhere((t) => t.tx.note == 'Soldi da papà').category.type, TxType.income);
      expect(result.createdCategories, 3); // Famiglia (entrata), Famiglia (uscita), Pesca
      expect(await db.getSavingsGoals(), isEmpty);
    });

    test('il conto principale vuoto del primo avvio riceve quello di Sossoldi', () async {
      final defaultId = (await db.getAccounts()).single.id;
      final p = await plan(replace: false);
      expect(p.accounts.map((a) => a.targetName), ['Risparmi', 'Conto principale']);
      expect(p.accounts.last.existingAccountId, defaultId);
      expect(p.accounts.first.reusesExisting, isFalse);
      expect(p.otherAccounts, isEmpty);

      final result = await db.importSossoldi(p);
      expect(result.balancesMatch, isTrue);
      final accounts = await db.getAccounts();
      expect(accounts.map((a) => a.name), unorderedEquals(['Conto principale', 'Risparmi']));
      final main = accounts.firstWhere((a) => a.id == defaultId);
      expect(main.initialBalanceCents, 2914);
      expect(await db.countAccountUsage(defaultId), 8);
    });

    test('i conti già in uso non vengono toccati: i nomi non si scontrano', () async {
      final defaultId = (await db.getAccounts()).single.id;
      final groceries = (await db.getCategories())
          .firstWhere((c) => c.name == 'Spesa' && c.type == TxType.expense);
      await db.insertTransactions([
        TransactionsCompanion.insert(
          type: TxType.expense,
          amountCents: 1500,
          categoryId: groceries.id,
          accountId: defaultId,
          date: DateTime(2026, 1, 5),
        ),
      ]);
      // Saldo iniziale diverso da zero: non è un conto vuoto.
      await db.createAccount(
          name: 'Risparmi', iconKey: 'savings', color: 0, initialBalanceCents: 250000);
      await db.createAccount(name: 'Contanti', iconKey: 'cash', color: 0);

      final p = await plan(replace: false);
      expect(p.accounts.map((a) => a.targetName),
          ['Risparmi (Sossoldi)', 'Conto principale (Sossoldi)']);
      expect(p.accounts.any((a) => a.reusesExisting), isFalse);
      expect(p.otherAccounts.map((a) => a.name),
          ['Conto principale', 'Risparmi', 'Contanti']);

      final result = await db.importSossoldi(p);
      expect(result.balancesMatch, isTrue);
      final balances = await balancesByName();
      expect(balances['Conto principale'], -1500);
      expect(balances['Risparmi'], 250000);
      expect(balances['Contanti'], 0);
      expect(balances, hasLength(5));
    });

    test('sostituendo i dati spariscono anche i conti di esempio', () async {
      await db.createAccount(
          name: 'Contanti', iconKey: 'cash', color: 0, initialBalanceCents: 8000);
      await db.createAccount(
          name: 'Risparmi', iconKey: 'savings', color: 0, initialBalanceCents: 250000);
      final p = await plan(replace: true);
      expect(p.otherAccounts.map((a) => a.name),
          ['Conto principale', 'Contanti', 'Risparmi']);
      expect(p.accounts.any((a) => a.reusesExisting), isFalse);

      final result = await db.importSossoldi(p);
      expect(result.balancesMatch, isTrue);
      final export = SossoldiExport.parse(_csv);
      expect(await balancesByName(), {
        'Risparmi': export.balances[1],
        'Conto principale': export.balances[2],
      });
    });

    test('se il conto vuoto viene usato prima dell\'import, non cambia nulla', () async {
      final account = (await db.getAccounts()).single;
      final p = await plan(replace: false);
      expect(p.accounts.last.existingAccountId, account.id);
      await db.updateAccount(account.copyWith(initialBalanceCents: 100));

      await expectLater(db.importSossoldi(p), throwsA(isA<SossoldiImportException>()));
      final accounts = await db.getAccounts();
      expect(accounts.single.initialBalanceCents, 100);
      expect(await db.watchTransactionsBetween(DateTime(2000), DateTime(2100)).first,
          isEmpty);
    });
  });
}
