// Genera un report CSV di esempio (dati fittizi) per vedere il formato
// senza avviare l'app:
//   dart run tool/generate_sample_report.dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:financiee/core/utils/period.dart';
import 'package:financiee/data/app_database.dart';
import 'package:financiee/data/sample_data.dart';
import 'package:financiee/domain/analytics.dart';
import 'package:financiee/features/reports/csv_report_builder.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Future<void> main() async {
  Intl.defaultLocale = 'it_IT';
  await initializeDateFormatting('it_IT');

  final now = DateTime(2026, 11, 30);
  final db = AppDatabase(NativeDatabase.memory());
  await insertSampleData(db, now: now);

  final period = Period.custom(DateTime(2026, 6, 1), DateTime(2026, 11, 30));
  final items =
      await db.watchTransactionsBetween(period.start, period.end).first;
  final data = ReportData.compute(
    period,
    items,
    transfers: await db.watchTransfersBetween(period.start, period.end).first,
    accounts: await db.getAccounts(),
    startBalances: await db.watchAccountBalances(before: period.start).first,
    now: now,
  );
  final builder = CsvReportBuilder(generatedAt: now);

  final out = Directory('docs/esempi')..createSync(recursive: true);
  void write(String name, String csv) {
    File('${out.path}/$name')
        .writeAsBytesSync([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
    stdout.writeln('Scritto ${out.path}/$name');
  }

  write('report_finanze_esempio.csv', builder.buildFullReport(data));
  write('movimenti_esempio.csv', builder.buildTransactionsTable(data));
  await db.close();
}
