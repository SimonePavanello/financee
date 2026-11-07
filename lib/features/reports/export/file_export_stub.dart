import 'dart:typed_data';

/// Esito di un salvataggio: [saved] è falso se l'utente ha annullato.
typedef ExportResult = ({bool saved, String message});

Future<ExportResult> saveFile(
  String fileName,
  Uint8List bytes,
  String mimeType,
) =>
    throw UnsupportedError('Esportazione non supportata su questa piattaforma');
