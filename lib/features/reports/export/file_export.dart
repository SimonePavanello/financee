import 'dart:convert';
import 'dart:typed_data';

import 'file_export_stub.dart'
    if (dart.library.js_interop) 'file_export_web.dart'
    if (dart.library.io) 'file_export_io.dart' as impl;

/// Salva (web: scarica; Android: apre il menu di condivisione) un file CSV.
/// Aggiunge il BOM UTF-8 così Excel mostra correttamente accenti e "€".
/// Restituisce un messaggio da mostrare all'utente.
Future<String> exportCsv(String fileName, String csv) {
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);
  return impl.saveFile(fileName, bytes, 'text/csv');
}
