import 'package:drift/wasm.dart';

/// Web: il database può stare in OPFS o in IndexedDB; drift sa dove.
Future<WasmProbeResult> _probe(String name) => WasmDatabase.probe(
  sqlite3Uri: Uri.parse('sqlite3.wasm'),
  driftWorkerUri: Uri.parse('drift_worker.js'),
  databaseName: name,
);

Future<bool> databaseExists(String name) async =>
    (await _probe(name)).existingDatabases.any((d) => d.$2 == name);

Future<void> deleteDatabase(String name) async {
  final probe = await _probe(name);
  for (final d in probe.existingDatabases.where((d) => d.$2 == name)) {
    await probe.deleteDatabase(d);
  }
}
