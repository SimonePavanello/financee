import 'package:intl/intl.dart';

const _locale = 'it_IT';

final _currency =
    NumberFormat.currency(locale: _locale, symbol: '€', decimalDigits: 2);
final _percent = NumberFormat('#,##0.0', _locale);

/// "1.240,50 €"
String formatMoney(int cents) => _currency.format(cents / 100);

/// "+ 1.240,50 €" / "− 45,20 €"
String formatSignedMoney(int cents, {required bool isIncome}) =>
    '${isIncome ? '+' : '−'} ${formatMoney(cents.abs())}';

/// Formato compatto per gli assi dei grafici: "850", "1,2k", "15k".
String formatCompactEuro(double euros) {
  final v = euros.abs();
  if (v >= 1000000) return '${_trim(euros / 1000000)}M';
  if (v >= 1000) return '${_trim(euros / 1000)}k';
  return euros.round().toString();
}

String _trim(double v) {
  final s = v.toStringAsFixed(v.abs() >= 10 ? 0 : 1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s.replaceAll('.', ',');
}

/// 0.443 -> "44,3%"
String formatPercent(double ratio) => '${_percent.format(ratio * 100)}%';

/// "1 movimento" / "3 movimenti"
String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

String capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

/// "Novembre 2026"
String formatMonthYear(DateTime d) =>
    capitalize(DateFormat('MMMM yyyy', _locale).format(d));

/// "novembre"
String formatMonthName(DateTime d) => DateFormat('MMMM', _locale).format(d);

/// "nov"
String formatShortMonth(DateTime d) =>
    capitalize(DateFormat('MMM', _locale).format(d));

/// "06/11/2026"
String formatDate(DateTime d) => DateFormat('dd/MM/yyyy', _locale).format(d);

/// "6 nov"
String formatShortDate(DateTime d) => DateFormat('d MMM', _locale).format(d);

/// "Venerdì"
String formatWeekday(DateTime d) =>
    capitalize(DateFormat('EEEE', _locale).format(d));

/// Intestazione dei gruppi giornalieri: "Oggi", "Ieri", "Lunedì 3 novembre".
String formatDayHeader(DateTime d, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final day = _dateOnly(d);
  if (day == today) return 'Oggi';
  if (day == today.subtract(const Duration(days: 1))) return 'Ieri';
  final pattern = day.year == today.year ? 'EEEE d MMMM' : 'EEEE d MMMM yyyy';
  return capitalize(DateFormat(pattern, _locale).format(day));
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Converte l'input dell'utente ("12,50", "12.5", "1.200,00") in centesimi.
/// Restituisce `null` se l'input non è un importo valido.
int? parseAmountToCents(String input) {
  var s = input.trim().replaceAll(RegExp(r'[\s€]'), '');
  if (s.isEmpty) return null;

  final hasComma = s.contains(',');
  final hasDot = s.contains('.');
  if (hasComma && hasDot) {
    // Il separatore che compare per ultimo è quello decimale.
    if (s.lastIndexOf(',') > s.lastIndexOf('.')) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (hasComma) {
    s = s.replaceAll(',', '.');
  }
  if ('.'.allMatches(s).length > 1) s = s.replaceAll('.', '');

  final value = double.tryParse(s);
  if (value == null || value.isNaN || value.isInfinite || value < 0) {
    return null;
  }
  return (value * 100).round();
}

/// Centesimi -> testo modificabile nel campo importo ("12,50").
String centsToInput(int cents) =>
    (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
