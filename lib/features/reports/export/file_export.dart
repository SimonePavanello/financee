import 'dart:convert';
import 'dart:typed_data';

import 'file_export_stub.dart' show ExportResult;
import 'file_export_stub.dart'
    if (dart.library.js_interop) 'file_export_web.dart'
    if (dart.library.io) 'file_export_io.dart' as impl;

export 'file_export_stub.dart' show ExportResult;

/// Salva (web: scarica; Android: apre il menu di condivisione) un file CSV.
/// Aggiunge il BOM UTF-8 così Excel mostra correttamente accenti e "€".
/// Restituisce un messaggio da mostrare all'utente.
Future<String> exportCsv(String fileName, String csv) async {
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
  return (await impl.saveFile(fileName, bytes, 'text/csv')).message;
}

/// Salva un file JSON (es. un backup), come [exportCsv].
Future<ExportResult> exportJson(String fileName, String json) =>
    impl.saveFile(fileName, utf8.encode(json), 'application/json');
