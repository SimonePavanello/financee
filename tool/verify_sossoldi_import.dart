// Prova l'import di un export di Sossoldi in un database temporaneo (in
// memoria) e controlla che saldi e totali tornino. Non modifica nulla.
//   dart run tool/verify_sossoldi_import.dart <file.csv>
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:financiee/core/utils/formatters.dart';
import 'package:financiee/data/app_database.dart';
import 'package:financiee/data/import/sossoldi_import.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Uso: dart run tool/verify_sossoldi_import.dart <file.csv>');
    exitCode = 64;
    return;
  }
  Intl.defaultLocale = 'it_IT';
  await initializeDateFormatting('it_IT');

  final csv = utf8.decode(File(args.first).readAsBytesSync(), allowMalformed: true);
  final export = SossoldiExport.parse(csv);
  final db = AppDatabase(NativeDatabase.memory());
  final plan = SossoldiImportPlan.build(
    export,
    existingCategories: await db.getCategories(),
    existingAccounts: await db.getAccounts(),
    replaceExisting: true,
  );

  stdout.writeln('Periodo: ${formatDate(plan.firstDate!)} - ${formatDate(plan.lastDate!)}');
  stdout.writeln('Movimenti: ${plan.transactionCount}, trasferimenti: ${plan.transferCount}');
  stdout.writeln('\nCONTI');
  for (final a in plan.accounts) {
    stdout.writeln('  ${a.source.name} -> ${a.targetName}: iniziale '
        '${formatMoney(a.source.startingCents)}, saldo atteso ${formatMoney(a.expectedBalanceCents)}');
  }
  for (final a in plan.skippedAccounts) {
    stdout.writeln('  ${a.name}: saltato (disattivato, nessun movimento)');
  }
  stdout.writeln('\nCATEGORIE');
  for (final c in plan.categories) {
    stdout.writeln('  ${c.type == TxType.income ? 'E' : 'U'} '
        '${(c.sourceName ?? '(senza categoria)').padRight(22)} -> '
        '${c.targetName.padRight(18)} ${c.exists ? '         ' : '(nuova)  '}'
        '${c.count.toString().padLeft(4)} mov.  ${formatMoney(c.totalCents)}');
  }

  final result = await db.importSossoldi(plan);
  stdout.writeln('\nVERIFICA SALDI DOPO L\'IMPORT');
  for (final c in result.checks) {
    stdout.writeln('  ${c.ok ? 'OK ' : 'KO '} ${c.name}: atteso '
        '${formatMoney(c.expectedCents)}, ottenuto ${formatMoney(c.actualCents)}');
  }

  // Totali entrate/uscite: Sossoldi vs database.
  final all = await db.watchTransactionsBetween(DateTime(1900), DateTime(2200)).first;
  final transfers = await db.watchTransfersBetween(DateTime(1900), DateTime(2200)).first;
  int sum(Iterable<int> v) => v.fold(0, (a, b) => a + b);
  final expIn = sum(export.movements
      .where((m) => m.type == SossoldiMovementType.income)
      .map((m) => m.amountCents));
  final expOut = sum(export.movements
      .where((m) => m.type == SossoldiMovementType.expense)
      .map((m) => m.amountCents));
  final gotIn = sum(all.where((t) => t.isIncome).map((t) => t.tx.amountCents));
  final gotOut = sum(all.where((t) => !t.isIncome).map((t) => t.tx.amountCents));
  stdout.writeln('  ${expIn == gotIn ? 'OK ' : 'KO '} Entrate: ${formatMoney(expIn)} / ${formatMoney(gotIn)}');
  stdout.writeln('  ${expOut == gotOut ? 'OK ' : 'KO '} Uscite: ${formatMoney(expOut)} / ${formatMoney(gotOut)}');
  stdout.writeln('  ${all.length == plan.transactionCount && transfers.length == plan.transferCount ? 'OK ' : 'KO '} '
      'Righe: ${all.length} movimenti, ${transfers.length} trasferimenti');
  stdout.writeln(result.balancesMatch && expIn == gotIn && expOut == gotOut
      ? '\nTUTTO TORNA'
      : '\nATTENZIONE: qualcosa non torna');
  await db.close();
}
