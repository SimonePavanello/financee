import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/period.dart';
import '../../data/models.dart';
import '../../domain/analytics.dart';

/// Costruisce CSV "parlanti", pensati per essere aperti in Excel/Numbers/
/// Google Sheets con impostazioni italiane:
/// - separatore `;` (la virgola è il separatore decimale);
/// - importi senza separatore delle migliaia (`1240,50`), così restano numeri;
/// - date `gg/mm/aaaa`;
/// - righe CRLF. Il BOM UTF-8 viene aggiunto al salvataggio del file.
class CsvReportBuilder {
  CsvReportBuilder({DateTime? generatedAt})
      : generatedAt = generatedAt ?? DateTime.now();

  final DateTime generatedAt;

  static const separator = ';';
  static const _eol = '\r\n';

  final _amount = NumberFormat('0.00', 'it_IT');

  /// Report completo: intestazione, riepilogo, conti, categorie, andamento
  /// mensile, trasferimenti e dettaglio dei movimenti con saldo progressivo.
  String buildFullReport(ReportData data) {
    final s = data.summary;
    final rows = <List<Object?>>[];
    final ascending = data.transactions.reversed.toList();
    final transfersAsc = data.transfers.reversed.toList();
    final transfersTotal =
        data.transfers.fold<int>(0, (sum, t) => sum + t.amountCents);

    // Intestazione
    rows
      ..add(['REPORT FINANZE PERSONALI'])
      ..add(['Periodo', data.period.label])
      ..add(['Dal', formatDate(data.period.start), 'Al', formatDate(data.period.lastDay)])
      ..add(['Generato il', DateFormat('dd/MM/yyyy HH:mm').format(generatedAt)])
      ..add([]);

    // Riepilogo
    rows
      ..add(['RIEPILOGO'])
      ..add(['Voce', 'Valore', 'Spiegazione'])
      ..add([
        'Entrate totali (€)',
        _money(s.incomeCents),
        plural(s.incomeCount, 'entrata', 'entrate'),
      ])
      ..add([
        'Uscite totali (€)',
        _money(s.expenseCents),
        plural(s.expenseCount, 'uscita', 'uscite'),
      ])
      ..add([
        'Saldo del periodo (€)',
        _money(s.balanceCents),
        s.balanceCents >= 0
            ? 'Hai messo da parte ${formatMoney(s.balanceCents)}'
            : 'Hai speso ${formatMoney(-s.balanceCents)} più di quanto hai incassato',
      ])
      ..add([
        'Tasso di risparmio',
        s.savingsRate == null ? 'n.d.' : formatPercent(s.savingsRate!),
        s.savingsRate == null
            ? 'Nessuna entrata nel periodo'
            : 'Quota delle entrate non spesa',
      ])
      ..add([
        'Spesa media giornaliera (€)',
        _money(data.dailyAverageExpense),
        'Uscite divise per ${plural(data.averageDays, 'giorno', 'giorni')}',
      ]);
    final biggest = s.biggestExpense;
    if (biggest != null) {
      rows.add([
        'Spesa più alta (€)',
        _money(biggest.tx.amountCents),
        '${biggest.title} (${biggest.category.name}, ${biggest.accountLabel}) del ${formatDate(biggest.tx.date)}',
      ]);
    }
    final top = s.expenseByCategory.firstOrNull;
    if (top != null) {
      rows.add([
        'Categoria di spesa principale',
        top.category.name,
        '${formatPercent(top.share)} delle uscite (${formatMoney(top.totalCents)})',
      ]);
    }
    if (data.transfers.isNotEmpty) {
      rows.add([
        'Trasferimenti tra conti (€)',
        _money(transfersTotal),
        '${plural(data.transfers.length, 'trasferimento', 'trasferimenti')}: '
            'spostano denaro tra i tuoi conti, non sono né entrate né uscite',
      ]);
    }
    rows.add([]);

    // Conti
    if (data.accounts.isNotEmpty) {
      rows
        ..add(['CONTI'])
        ..add([
          'Conto',
          'Saldo a inizio periodo (€)',
          'Entrate (€)',
          'Uscite (€)',
          'Trasferimenti netti (€)',
          'Saldo a fine periodo (€)',
          'Variazione (€)',
        ]);
      for (final a in data.accounts) {
        rows.add([
          _text(a.account.name),
          _money(a.startCents),
          _money(a.incomeCents),
          _money(a.expenseCents),
          _money(a.transferNetCents),
          _money(a.endCents),
          _money(a.changeCents),
        ]);
      }
      int sum(int Function(AccountPeriodSummary a) f) =>
          data.accounts.fold(0, (s, a) => s + f(a));
      rows
        ..add([
          'TOTALE (patrimonio)',
          _money(sum((a) => a.startCents)),
          _money(sum((a) => a.incomeCents)),
          _money(sum((a) => a.expenseCents)),
          _money(sum((a) => a.transferNetCents)),
          _money(sum((a) => a.endCents)),
          _money(sum((a) => a.changeCents)),
        ])
        ..add([]);
    }

    // Categorie
    _addCategorySection(rows, 'USCITE PER CATEGORIA', s.expenseByCategory,
        s.expenseCents, 'uscite');
    _addCategorySection(rows, 'ENTRATE PER CATEGORIA', s.incomeByCategory,
        s.incomeCents, 'entrate');

    // Andamento mensile
    if (data.months.length > 1) {
      rows
        ..add(['ANDAMENTO MENSILE'])
        ..add([
          'Mese',
          'Entrate (€)',
          'Uscite (€)',
          'Saldo del mese (€)',
          'Saldo cumulato (€)',
        ]);
      var cumulative = 0;
      for (final m in data.months) {
        cumulative += m.balanceCents;
        rows.add([
          formatMonthYear(m.month),
          _money(m.incomeCents),
          _money(m.expenseCents),
          _money(m.balanceCents),
          _money(cumulative),
        ]);
      }
      rows.add([]);
    }

    // Trasferimenti
    if (transfersAsc.isNotEmpty) {
      rows
        ..add(['TRASFERIMENTI TRA CONTI'])
        ..add(['Data', 'Giorno', 'Da', 'A', 'Descrizione', 'Importo (€)']);
      for (final t in transfersAsc) {
        rows.add([
          formatDate(t.date),
          formatWeekday(t.date),
          _text(t.from.name),
          _text(t.to.name),
          _text(t.transfer.note),
          _money(t.amountCents),
        ]);
      }
      rows
        ..add(['TOTALE', '', '', '', '', _money(transfersTotal)])
        ..add([]);
    }

    // Dettaglio movimenti
    rows
      ..add(['DETTAGLIO MOVIMENTI'])
      ..add([
        'Data',
        'Giorno',
        'Tipo',
        'Categoria',
        'Conto',
        'Descrizione',
        'Entrata (€)',
        'Uscita (€)',
        'Saldo progressivo (€)',
      ]);
    if (ascending.isEmpty) {
      rows.add(['Nessun movimento nel periodo']);
    }
    var running = 0;
    for (final t in ascending) {
      running += t.signedCents;
      rows.add([
        formatDate(t.tx.date),
        formatWeekday(t.tx.date),
        t.isIncome ? 'Entrata' : 'Uscita',
        _text(t.category.name),
        _text(_accountWithShares(t)),
        _text(t.tx.note),
        t.isIncome ? _money(t.tx.amountCents) : '',
        t.isIncome ? '' : _money(t.tx.amountCents),
        _money(running),
      ]);
    }
    if (ascending.isNotEmpty) {
      rows.add([
        'TOTALE',
        '',
        '',
        '',
        '',
        '',
        _money(s.incomeCents),
        _money(s.expenseCents),
        _money(s.balanceCents),
      ]);
    }

    return _encode(rows);
  }

  /// Tabella semplice, una riga per movimento: ideale per filtri e tabelle
  /// pivot. L'importo ha il segno (negativo = uscita). Ogni trasferimento
  /// diventa due righe (uscita dal conto di origine, entrata in quello di
  /// destinazione) e così una spesa pagata in parte con i buoni pasto (una
  /// riga per conto con la sua parte): i totali per conto e per categoria
  /// tornano.
  String buildTransactionsTable(ReportData data) {
    final rows = <List<Object?>>[
      ['Data', 'Tipo', 'Categoria', 'Conto', 'Descrizione', 'Importo (€)'],
    ];
    final movements = mergeMovements(data.transactions, data.transfers).reversed;
    for (final m in movements) {
      switch (m) {
        case TransactionWithCategory t:
          for (final account in [t.account, ?t.voucherAccount]) {
            final cents = t.signedCentsFor(account.id);
            if (cents == 0 && account != t.account) continue;
            rows.add([
              formatDate(t.tx.date),
              t.isIncome ? 'Entrata' : 'Uscita',
              _text(t.category.name),
              _text(account.name),
              _text(t.tx.note),
              _money(cents),
            ]);
          }
        case TransferWithAccounts t:
          final note = t.transfer.note.trim().isEmpty
              ? '${t.from.name} → ${t.to.name}'
              : t.transfer.note;
          rows
            ..add([
              formatDate(t.date),
              'Trasferimento in uscita',
              'Trasferimento',
              _text(t.from.name),
              _text(note),
              _money(-t.amountCents),
            ])
            ..add([
              formatDate(t.date),
              'Trasferimento in entrata',
              'Trasferimento',
              _text(t.to.name),
              _text(note),
              _money(t.amountCents),
            ]);
      }
    }
    return _encode(rows);
  }

  void _addCategorySection(
    List<List<Object?>> rows,
    String title,
    List<CategoryTotal> totals,
    int total,
    String noun,
  ) {
    rows
      ..add([title])
      ..add([
        'Categoria',
        'Totale (€)',
        '% sulle $noun',
        'N. movimenti',
        'Importo medio (€)',
      ]);
    if (totals.isEmpty) {
      rows.add(['Nessun movimento']);
    }
    for (final t in totals) {
      rows.add([
        _text(t.category.name),
        _money(t.totalCents),
        formatPercent(t.share),
        t.count,
        _money(t.averageCents),
      ]);
    }
    if (totals.isNotEmpty) {
      rows.add([
        'TOTALE',
        _money(total),
        '100%',
        totals.fold<int>(0, (s, t) => s + t.count),
        '',
      ]);
    }
    rows.add([]);
  }

  String _money(int cents) => _amount.format(cents / 100);

  /// "Conto principale" oppure, per una spesa pagata in parte con i buoni,
  /// "Conto principale 40,00 € + Buoni pasto 140,00 €".
  String _accountWithShares(TransactionWithCategory t) => t.usesVouchers
      ? '${t.account.name} ${_money(t.accountCents)} € + '
          '${t.voucherAccount!.name} ${_money(t.voucherCents)} €'
      : t.account.name;

  /// Evita che testi liberi vengano interpretati come formule dal foglio
  /// di calcolo (CSV injection).
  String _text(String value) {
    final v = value.trim();
    if (v.isNotEmpty && '=+-@\t\r'.contains(v[0])) return "'$v";
    return v;
  }

  String _encode(List<List<Object?>> rows) {
    final buffer = StringBuffer();
    for (final row in rows) {
      buffer
        ..write(row.map(_escape).join(separator))
        ..write(_eol);
    }
    return buffer.toString();
  }

  static String _escape(Object? value) {
    final s = value?.toString() ?? '';
    final needsQuotes = s.contains(separator) ||
        s.contains('"') ||
        s.contains('\n') ||
        s.contains('\r');
    return needsQuotes ? '"${s.replaceAll('"', '""')}"' : s;
  }
}

/// Nome file suggerito, es. `report_finanze_2026-11.csv`.
String reportFileName(Period period, {required bool full}) =>
    '${full ? 'report_finanze' : 'movimenti'}_${period.fileSlug}.csv';
