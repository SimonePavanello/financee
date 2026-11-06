import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

/// Apre il database SQLite dell'app.
/// - Android/iOS: file `financiee.sqlite` nella cartella documenti dell'app.
/// - Web: SQLite compilato in WebAssembly (`web/sqlite3.wasm`) con
///   persistenza su OPFS o IndexedDB, gestito dal worker `web/drift_worker.js`.
QueryExecutor openAppDatabaseConnection() => driftDatabase(
      name: 'financiee',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
