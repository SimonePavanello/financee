import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_database.dart';
import 'backup/backup.dart';
import 'database_storage_stub.dart'
    if (dart.library.js_interop) 'database_storage_web.dart'
    if (dart.library.io) 'database_storage_io.dart' as storage;

/// Nome del database: file `financee.sqlite` nella cartella documenti
/// dell'app su Android/iOS, database `financee` nel browser.
const kDatabaseName = 'financee';

/// Nome del database quando l'app si chiamava Financiee.
const kLegacyDatabaseName = 'financiee';

/// Stato dello spostamento dal vecchio nome: `copied` (dati copiati nel
/// nuovo database, il vecchio forse è ancora da eliminare) oppure `done`.
const _moveKey = 'database_move_to_financee';

/// Apre il database SQLite dell'app.
/// - Android/iOS: file `<nome>.sqlite` nella cartella documenti dell'app.
/// - Web: SQLite compilato in WebAssembly (`web/sqlite3.wasm`) con
///   persistenza su OPFS o IndexedDB, gestito dal worker `web/drift_worker.js`.
QueryExecutor openAppDatabaseConnection([String name = kDatabaseName]) =>
    driftDatabase(
      name: name,
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );

/// Da chiamare all'avvio, prima di aprire il database. Se c'è ancora il
/// database col vecchio nome (Financiee) ne copia tutti i dati in quello
/// nuovo, controlla che la copia sia identica e solo allora elimina il
/// vecchio. Restituisce il nome del database da aprire: se qualcosa va
/// storto prima che la copia sia confermata si continua con il vecchio,
/// così nessun dato va perso, e al prossimo avvio si riprova.
Future<String> prepareAppDatabase(SharedPreferences prefs) async {
  final state = prefs.getString(_moveKey);
  if (state == 'done') return kDatabaseName;
  try {
    final legacyExists = await storage
        .databaseExists(kLegacyDatabaseName)
        .timeout(const Duration(seconds: 15));
    if (legacyExists && state != 'copied') {
      final from = AppDatabase(openAppDatabaseConnection(kLegacyDatabaseName));
      final to = AppDatabase(openAppDatabaseConnection());
      try {
        await copyDatabase(from: from, to: to);
      } finally {
        await from.close();
        await to.close();
      }
      await prefs.setString(_moveKey, 'copied');
    }
    if (legacyExists) {
      await storage
          .deleteDatabase(kLegacyDatabaseName)
          .timeout(const Duration(seconds: 10));
    }
    await prefs.setString(_moveKey, 'done');
    return kDatabaseName;
  } catch (e, s) {
    debugPrint('Spostamento del database non completato: $e\n$s');
    return prefs.getString(_moveKey) == 'copied'
        ? kDatabaseName
        : kLegacyDatabaseName;
  }
}
