import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/connection.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final ofl = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Plus Jakarta Sans (font)'], ofl);
  });
  Intl.defaultLocale = 'it_IT';
  await initializeDateFormatting('it_IT');
  final prefs = await SharedPreferences.getInstance();
  // Sposta i dati dal database col vecchio nome dell'app, se c'è ancora.
  final databaseName = await prepareAppDatabase(prefs);

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        databaseNameProvider.overrideWithValue(databaseName),
      ],
      child: const FinanceApp(),
    ),
  );
}
