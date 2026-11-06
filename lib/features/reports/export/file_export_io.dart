import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<String> saveFile(String fileName, Uint8List bytes, String mimeType) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');
  await file.writeAsBytes(bytes, flush: true);
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mimeType, name: fileName)],
      subject: fileName,
      fileNameOverrides: [fileName],
    ),
  );
  return switch (result.status) {
    ShareResultStatus.success => 'File condiviso: $fileName',
    ShareResultStatus.dismissed => 'Condivisione annullata',
    ShareResultStatus.unavailable => 'File pronto: $fileName',
  };
}
