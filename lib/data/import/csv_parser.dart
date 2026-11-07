/// Parser CSV (RFC 4180): campi tra virgolette, virgolette raddoppiate,
/// a capo dentro i campi, righe CRLF o LF, BOM iniziale.
List<List<String>> parseCsv(String input, {String separator = ','}) {
  var text = input;
  if (text.startsWith('﻿')) text = text.substring(1);

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    // Le righe completamente vuote vengono ignorate.
    if (!(row.length == 1 && row.first.isEmpty)) rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final c = text[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
      } else {
        field.write(c);
      }
      i++;
      continue;
    }
    if (c == '"' && field.isEmpty) {
      inQuotes = true;
    } else if (c == separator) {
      endField();
    } else if (c == '\r') {
      if (i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else if (c == '\n') {
      endRow();
    } else {
      field.write(c);
    }
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
