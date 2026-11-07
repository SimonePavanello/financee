import 'package:financiee/core/utils/formatters.dart';
import 'package:financiee/core/utils/period.dart';
import 'package:financiee/data/app_database.dart';
import 'package:financiee/data/models.dart';
import 'package:financiee/domain/analytics.dart';
import 'package:financiee/features/reports/csv_report_builder.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:test/test.dart';

// Test di logica pura (nessuna dipendenza da Flutter): si eseguono con
// `dart test`, oppure con `flutter test` dove il motore Flutter può girare.

CategoryEntity _cat(int id, String name, TxType type) => CategoryEntity(
      id: id,
      name: name,
      type: type,
      iconKey: 'other',
      color: 0xFF6366F1,
      sortOrder: id,
      createdAt: DateTime(2026),
    );

AccountEntity _acc(int id, String name, [int initial = 0]) => AccountEntity(
      id: id,
      name: name,
      iconKey: 'bank',
      color: 0xFF6366F1,
      initialBalanceCents: initial,
      sortOrder: id,
      createdAt: DateTime(2026),
    );

final _main = _acc(1, 'Conto principale', 50000);
final _savings = _acc(2, 'Risparmi', 100000);

final _spesa = _cat(1, 'Spesa', TxType.expense);
final _casa = _cat(2, 'Casa', TxType.expense);
final _stipendio = _cat(3, 'Stipendio', TxType.income);

var _nextId = 1;
TransactionWithCategory _tx(
  CategoryEntity c,
  int cents,
  DateTime date, [
  String note = '',
  AccountEntity? account,
]) {
  final a = account ?? _main;
  return TransactionWithCategory(
    TransactionEntity(
      id: _nextId++,
      type: c.type,
      amountCents: cents,
      categoryId: c.id,
      accountId: a.id,
      date: date,
      note: note,
      createdAt: date,
    ),
    c,
    a,
  );
}

TransferWithAccounts _transfer(
  AccountEntity from,
  AccountEntity to,
  int cents,
  DateTime date, [
  String note = '',
]) =>
    TransferWithAccounts(
      TransferEntity(
        id: _nextId++,
        fromAccountId: from.id,
        toAccountId: to.id,
        amountCents: cents,
        date: date,
        note: note,
        createdAt: date,
      ),
      from,
      to,
    );

void main() {
  setUpAll(() async {
    Intl.defaultLocale = 'it_IT';
    await initializeDateFormatting('it_IT');
  });

  group('parseAmountToCents', () {
    test('accetta virgola e punto come separatore decimale', () {
      expect(parseAmountToCents('12,50'), 1250);
      expect(parseAmountToCents('12.5'), 1250);
      expect(parseAmountToCents('7'), 700);
      expect(parseAmountToCents('0,01'), 1);
    });

    test('gestisce i separatori delle migliaia', () {
      expect(parseAmountToCents('1.240,50'), 124050);
      expect(parseAmountToCents('1,240.50'), 124050);
      expect(parseAmountToCents('1.000.000'), 100000000);
    });

    test('rifiuta input non validi', () {
      expect(parseAmountToCents(''), isNull);
      expect(parseAmountToCents('abc'), isNull);
      expect(parseAmountToCents('-5'), isNull);
    });

    test('centsToInput è l\'inverso', () {
      expect(centsToInput(124050), '1240,50');
      expect(parseAmountToCents(centsToInput(999)), 999);
    });
  });

  group('Period', () {
    test('mese: inizio, fine e navigazione a cavallo d\'anno', () {
      final p = Period.month(DateTime(2026, 1, 15));
      expect(p.start, DateTime(2026, 1, 1));
      expect(p.end, DateTime(2026, 2, 1));
      expect(p.days, 31);
      expect(p.previous().start, DateTime(2025, 12, 1));
      expect(p.label, 'Gennaio 2026');
      expect(p.fileSlug, '2026-01');
    });

    test('periodo personalizzato include entrambi gli estremi', () {
      final p = Period.custom(DateTime(2026, 3, 10), DateTime(2026, 3, 20));
      expect(p.days, 11);
      expect(p.contains(DateTime(2026, 3, 20)), isTrue);
      expect(p.contains(DateTime(2026, 3, 21)), isFalse);
      expect(p.next().start, DateTime(2026, 3, 21));
      expect(p.next().days, 11);
    });

    test('la media giornaliera conta solo i giorni trascorsi', () {
      final p = Period.month(DateTime(2026, 11));
      expect(p.daysForAverage(DateTime(2026, 11, 6, 15)), 6);
      expect(p.daysForAverage(DateTime(2027, 1, 1)), 30);
    });
  });

  group('PeriodSummary', () {
    test('totali, saldo, risparmio e ripartizione per categoria', () {
      final items = [
        _tx(_stipendio, 200000, DateTime(2026, 11, 1)),
        _tx(_casa, 65000, DateTime(2026, 11, 3), 'Affitto'),
        _tx(_spesa, 5000, DateTime(2026, 11, 4)),
        _tx(_spesa, 3000, DateTime(2026, 11, 5)),
      ];
      final s = PeriodSummary.from(items);
      expect(s.incomeCents, 200000);
      expect(s.expenseCents, 73000);
      expect(s.balanceCents, 127000);
      expect(s.savingsRate, closeTo(0.635, 1e-9));
      expect(s.expenseByCategory.first.category.name, 'Casa');
      expect(s.expenseByCategory.last.count, 2);
      expect(s.expenseByCategory.last.averageCents, 4000);
      expect(s.biggestExpense?.tx.note, 'Affitto');
    });

    test('senza entrate il tasso di risparmio non è definito', () {
      final s = PeriodSummary.from([_tx(_spesa, 1000, DateTime(2026, 11, 1))]);
      expect(s.savingsRate, isNull);
    });

    test('bucketByMonth crea anche i mesi vuoti', () {
      final buckets = bucketByMonth(
        [_tx(_spesa, 1000, DateTime(2026, 9, 3))],
        DateTime(2026, 8),
        DateTime(2026, 11),
      );
      expect(buckets.map((b) => b.month.month), [8, 9, 10]);
      expect(buckets[1].expenseCents, 1000);
      expect(buckets[2].expenseCents, 0);
    });
  });

  group('CsvReportBuilder', () {
    final period = Period.month(DateTime(2026, 11));
    final items = [
      _tx(_spesa, 4520, DateTime(2026, 11, 4), 'Esselunga; spesa "grossa"'),
      _tx(_casa, 65000, DateTime(2026, 11, 3), 'Affitto'),
      _tx(_stipendio, 200000, DateTime(2026, 11, 1), '=SOMMA(A1)'),
    ]; // ordinati dal più recente, come dal database
    final transfers = [
      _transfer(_main, _savings, 20000, DateTime(2026, 11, 2), 'Accantonamento'),
    ];
    final data = ReportData.compute(
      period,
      items,
      transfers: transfers,
      accounts: [_main, _savings],
      startBalances: {_main.id: 50000, _savings.id: 100000},
      now: DateTime(2026, 11, 30),
    );
    final builder = CsvReportBuilder(generatedAt: DateTime(2026, 11, 30, 18, 5));

    test('report completo con sezioni e numeri all\'italiana', () {
      final csv = builder.buildFullReport(data);
      expect(csv, contains('Periodo;Novembre 2026'));
      expect(csv, contains('Entrate totali (€);2000,00;1 entrata'));
      expect(csv, contains('Uscite totali (€);695,20;2 uscite'));
      expect(csv, contains('Saldo del periodo (€);1304,80;'));
      expect(csv, contains('USCITE PER CATEGORIA'));
      expect(csv, contains('ENTRATE PER CATEGORIA'));
      expect(csv, contains('DETTAGLIO MOVIMENTI'));
      expect(csv, isNot(contains('ANDAMENTO MENSILE'))); // un solo mese
      expect(csv.contains('\r\n'), isTrue);
    });

    test('dettaglio in ordine cronologico con saldo progressivo', () {
      final lines = builder.buildFullReport(data).split('\r\n');
      final start = lines.indexOf('DETTAGLIO MOVIMENTI') + 2;
      expect(lines[start],
          startsWith('01/11/2026;Domenica;Entrata;Stipendio;Conto principale;'));
      expect(lines[start], endsWith(';2000,00;;2000,00'));
      expect(lines[start + 1], endsWith(';;650,00;1350,00'));
      expect(lines[start + 2], endsWith(';;45,20;1304,80'));
      expect(lines[start + 3], 'TOTALE;;;;;;2000,00;695,20;1304,80');
    });

    test('virgolette, separatori e formule nei testi vengono neutralizzati', () {
      final csv = builder.buildTransactionsTable(data);
      expect(csv, contains('"Esselunga; spesa ""grossa"""'));
      expect(csv, contains("'=SOMMA(A1)"));
      expect(csv, contains('04/11/2026;Uscita;Spesa;Conto principale;'));
      expect(csv, contains(';-45,20'));
    });

    test('saldi dei conti a inizio e fine periodo', () {
      final csv = builder.buildFullReport(data);
      expect(csv, contains('CONTI'));
      // principale: 500 + 2000 - 695,20 - 200 (trasferimento) = 1604,80
      expect(csv,
          contains('Conto principale;500,00;2000,00;695,20;-200,00;1604,80;1104,80'));
      expect(csv, contains('Risparmi;1000,00;0,00;0,00;200,00;1200,00;200,00'));
      expect(csv, contains('TOTALE (patrimonio);1500,00;2000,00;695,20;0,00;2804,80;1304,80'));
    });

    test('i trasferimenti sono elencati a parte e non sono entrate né uscite', () {
      final csv = builder.buildFullReport(data);
      expect(csv, contains('TRASFERIMENTI TRA CONTI'));
      expect(csv, contains('02/11/2026;Lunedì;Conto principale;Risparmi;Accantonamento;200,00'));
      expect(csv, contains('Trasferimenti tra conti (€);200,00;1 trasferimento'));
      expect(csv, contains('Uscite totali (€);695,20;2 uscite'));
      final table = builder.buildTransactionsTable(data);
      expect(table, contains('02/11/2026;Trasferimento in uscita;Trasferimento;Conto principale;Accantonamento;-200,00'));
      expect(table, contains('02/11/2026;Trasferimento in entrata;Trasferimento;Risparmi;Accantonamento;200,00'));
    });

    test('andamento mensile per periodi di più mesi', () {
      final year = ReportData.compute(Period.year(2026), items);
      final csv = builder.buildFullReport(year);
      expect(csv, contains('ANDAMENTO MENSILE'));
      expect(csv, contains('Novembre 2026;2000,00;695,20;1304,80;1304,80'));
    });

    test('nome del file', () {
      expect(reportFileName(period, full: true), 'report_finanze_2026-11.csv');
      expect(reportFileName(period, full: false), 'movimenti_2026-11.csv');
    });
  });
}
