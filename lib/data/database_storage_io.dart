import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Android/iOS: il database è il file `<nome>.sqlite` nella cartella
/// documenti dell'app (come in `driftDatabase`).
Future<File> _file(String name) async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}${Platform.pathSeparator}$name.sqlite');
}

Future<bool> databaseExists(String name) async => (await _file(name)).exists();

/// Elimina il file del database e quelli di appoggio di SQLite.
Future<void> deleteDatabase(String name) async {
  final file = await _file(name);
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('${file.path}$suffix');
    if (await f.exists()) await f.delete();
  }
}
