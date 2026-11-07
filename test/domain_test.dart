import 'package:financiee/core/utils/formatters.dart';
import 'package:financiee/core/utils/period.dart';
import 'package:financiee/data/app_database.dart';
import 'package:financiee/data/models.dart';
import 'package:financiee/domain/analytics.dart';
import 'package:financiee/domain/debts.dart';
import 'package:financiee/domain/meal_vouchers.dart';
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
      kind: AccountKind.standard,
    );

final _main = _acc(1, 'Conto principale', 50000);
final _savings = _acc(2, 'Risparmi', 100000);
final _vouchers = _acc(3, 'Buoni pasto', 16000);

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
      voucherCents: 0,
      date: date,
      note: note,
      createdAt: date,
    ),
    c,
    a,
  );
}

/// Spesa pagata in parte con i buoni: [voucherCents] dal conto dei buoni,
/// il resto da [_main].
TransactionWithCategory _split(
  CategoryEntity c,
  int cents,
  int voucherCents,
  DateTime date, [
  String note = '',
]) =>
    TransactionWithCategory(
      TransactionEntity(
        id: _nextId++,
        type: c.type,
        amountCents: cents,
        categoryId: c.id,
        accountId: _main.id,
        voucherAccountId: _vouchers.id,
        voucherCents: voucherCents,
        date: date,
        note: note,
        createdAt: date,
      ),
      c,
      _main,
      _vouchers,
    );

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

  group('Buoni pasto', () {
    test('ripartizione canonica tra conto scelto e conto dei buoni', () {
      expect(
        normalizeVoucherSplit(amountCents: 18000, accountId: 1, voucherAccountId: 3, voucherCents: 14000),
        (accountId: 1, voucherAccountId: 3, voucherCents: 14000),
      );
      // Nessun buono, o buoni dallo stesso conto: spesa normale.
      expect(
        normalizeVoucherSplit(amountCents: 18000, accountId: 1, voucherAccountId: 3),
        (accountId: 1, voucherAccountId: null, voucherCents: 0),
      );
      expect(
        normalizeVoucherSplit(amountCents: 18000, accountId: 3, voucherAccountId: 3, voucherCents: 800),
        (accountId: 3, voucherAccountId: null, voucherCents: 0),
      );
      // I buoni coprono tutto: la spesa va interamente sul conto dei buoni.
      expect(
        normalizeVoucherSplit(amountCents: 1600, accountId: 1, voucherAccountId: 3, voucherCents: 1600),
        (accountId: 3, voucherAccountId: null, voucherCents: 0),
      );
    });

    test('conteggio dei buoni e proposta per una spesa', () {
      expect(formatVoucherCount(800, 800), '1 buono');
      expect(formatVoucherCount(13600, 800), '17 buoni');
      expect(formatVoucherCount(14000, 800), '17,5 buoni');
      expect(formatVoucherCount(0, 800), '0 buoni');
      // 180 € di spesa, buoni da 8 €: al massimo 22 buoni (176 €)...
      expect(suggestedVoucherCents(amountCents: 18000, valueCents: 800, availableCents: 100000), 17600);
      // ...ma non più di quelli disponibili.
      expect(suggestedVoucherCents(amountCents: 18000, valueCents: 800, availableCents: 4000), 4000);
      // Senza importo o con buoni esauriti si parte da un buono.
      expect(suggestedVoucherCents(amountCents: 0, valueCents: 800, availableCents: 0), 800);
      expect(addVoucher(13600, 800), 14400);
      expect(addVoucher(14000, 800), 14400);
      expect(removeVoucher(13600, 800), 12800);
      expect(removeVoucher(14000, 800), 13600);
      expect(removeVoucher(800, 800), 0);
      expect(removeVoucher(0, 800), 0);
    });

    test('una spesa divisa pesa su ciascun conto solo per la sua parte', () {
      final t = _split(_spesa, 18000, 14000, DateTime(2026, 11, 7), 'Spesa grande');
      expect(t.usesVouchers, isTrue);
      expect(t.accountCents, 4000);
      expect(t.centsFor(null), 18000);
      expect(t.signedCentsFor(_main.id), -4000);
      expect(t.signedCentsFor(_vouchers.id), -14000);
      expect(t.signedCentsFor(_savings.id), 0);
      expect(t.involves(_vouchers.id), isTrue);
      expect(t.involves(_savings.id), isFalse);
      expect(t.accountLabel, 'Conto principale + Buoni pasto');
    });

    test('quota della categoria coperta dai buoni nel mese', () {
      final s = PeriodSummary.from([
        _split(_spesa, 18000, 14000, DateTime(2026, 11, 7)),
        _tx(_spesa, 12000, DateTime(2026, 11, 12)),
        _tx(_casa, 65000, DateTime(2026, 11, 3)),
        _split(_casa, 5000, 1600, DateTime(2026, 11, 9)),
      ]);
      // "Hai speso 300 € di spesa, di cui 140 € in buoni pasto": 46,7%.
      final spesa = s.expenseByCategory.firstWhere((c) => c.category.id == _spesa.id);
      expect(spesa.totalCents, 30000);
      expect(spesa.voucherCents, 14000);
      expect(formatPercent(spesa.voucherShare), '46,7%');
      expect(s.voucherCents, 15600);
      // Dalla categoria più coperta dai buoni; senza buoni non compare.
      expect(s.voucherCategories.map((c) => c.category.name), ['Spesa', 'Casa']);
      expect(PeriodSummary.from([_tx(_spesa, 1000, DateTime(2026, 11, 1))])
          .voucherCategories, isEmpty);
    });

    test('report e CSV: categoria per intero, conti per la loro parte', () {
      final items = [
        _split(_spesa, 18000, 14000, DateTime(2026, 11, 7), 'Spesa grande'),
        _tx(_stipendio, 200000, DateTime(2026, 11, 1)),
      ];
      final data = ReportData.compute(
        Period.month(DateTime(2026, 11)),
        items,
        accounts: [_main, _vouchers],
        startBalances: {_main.id: 50000, _vouchers.id: 16000},
        now: DateTime(2026, 11, 30),
      );
      expect(data.summary.expenseCents, 18000);
      expect(data.summary.expenseByCategory.single.totalCents, 18000);
      expect(data.summary.expenseByCategory.single.count, 1);
      final main = data.accounts.firstWhere((a) => a.account.id == _main.id);
      final vouchers = data.accounts.firstWhere((a) => a.account.id == _vouchers.id);
      expect(main.expenseCents, 4000);
      expect(main.endCents, 50000 + 200000 - 4000);
      expect(vouchers.expenseCents, 14000);
      expect(vouchers.endCents, 2000);

      final builder = CsvReportBuilder(generatedAt: DateTime(2026, 11, 30));
      final full = builder.buildFullReport(data);
      expect(full, contains('Conto principale 40,00 € + Buoni pasto 140,00 €;Spesa grande;;180,00;'));
      expect(full, contains('Buoni pasto;160,00;0,00;140,00;0,00;20,00;-140,00'));
      final table = builder.buildTransactionsTable(data);
      expect(table, contains('07/11/2026;Uscita;Spesa;Conto principale;Spesa grande;-40,00'));
      expect(table, contains('07/11/2026;Uscita;Spesa;Buoni pasto;Spesa grande;-140,00'));
    });
  });

  group('Debiti', () {
    DebtEntity debt(int id, String name, int cents) => DebtEntity(
          id: id,
          name: name,
          amountCents: cents,
          iconKey: 'loan',
          color: 0xFFF43F5E,
          sortOrder: id,
          createdAt: DateTime(2026, 9, 1),
        );

    test('residuo, avanzamento ed estinzione', () {
      final auto = DebtSummary(debt: debt(1, 'Auto', 500000), paidCents: 180000, paymentCount: 9);
      expect(auto.remainingCents, 320000);
      expect(auto.progress, closeTo(0.36, 1e-9));
      expect(formatPercent(auto.progress), '36,0%');
      expect(auto.isPaidOff, isFalse);
      expect(auto.overpaidCents, 0);

      final marco = DebtSummary(debt: debt(2, 'Marco', 10000), paidCents: 12000);
      expect(marco.isPaidOff, isTrue);
      expect(marco.remainingCents, 0);
      expect(marco.progress, 1);
      expect(marco.overpaidCents, 2000);
    });

    test('prima i debiti da estinguere, poi quelli estinti', () {
      final list = DebtSummary.combine(
        [debt(1, 'Marco', 10000), debt(2, 'Auto', 500000), debt(3, 'Telefono', 60000)],
        {
          1: (paidCents: 10000, count: 2, lastDate: DateTime(2026, 10, 1)),
          2: (paidCents: 50000, count: 1, lastDate: DateTime(2026, 11, 1)),
        },
      );
      expect(list.map((d) => d.debt.name), ['Auto', 'Telefono', 'Marco']);
      expect(list.last.paymentCount, 2);
      expect(list[1].paidCents, 0);
      expect(totalRemainingCents(list), 450000 + 60000);
    });

    test('quanto resta dopo un pagamento, anche modificandone uno', () {
      final auto = DebtSummary(debt: debt(1, 'Auto', 500000), paidCents: 180000);
      expect(remainingAfterPayment(auto, 20000), 300000);
      expect(remainingAfterPayment(auto, 400000), 0);
      // Una rata da 200 € già contata portata a 250 €.
      expect(remainingAfterPayment(auto, 25000, alreadyLinkedCents: 20000), 315000);
    });

    test('andamento del residuo giorno per giorno', () {
      final points = debtTimeline(
        amountCents: 100000,
        start: DateTime(2026, 9, 1, 15, 30),
        payments: [
          (DateTime(2026, 11, 1), 30000),
          (DateTime(2026, 10, 1), 20000),
          (DateTime(2026, 11, 1), 10000),
        ],
      );
      expect(points.map((p) => (p.date, p.remainingCents)), [
        (DateTime(2026, 9, 1), 100000),
        (DateTime(2026, 10, 1), 80000),
        (DateTime(2026, 11, 1), 40000),
      ]);
      // Un pagamento precedente alla creazione sposta indietro l'inizio.
      final early = debtTimeline(
        amountCents: 5000,
        start: DateTime(2026, 9, 1),
        payments: [(DateTime(2026, 8, 20), 6000)],
      );
      expect(early.first.date, DateTime(2026, 8, 20));
      expect(early.last.remainingCents, 0);
    });
  });
}
