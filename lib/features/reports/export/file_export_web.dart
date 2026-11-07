import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_export_stub.dart' show ExportResult;

Future<ExportResult> saveFile(
  String fileName,
  Uint8List bytes,
  String mimeType,
) async {
  final blob = web.Blob(
    <web.BlobPart>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  // Lascia al browser il tempo di avviare il download prima di liberare l'URL.
  Future<void>.delayed(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
  return (saved: true, message: 'Download avviato: $fileName');
}
