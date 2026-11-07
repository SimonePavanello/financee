import '../core/utils/formatters.dart';

/// Valore predefinito di un buono pasto: 8 €.
const kDefaultMealVoucherValueCents = 800;

/// Buoni interi contenuti in [cents].
int wholeVouchers(int cents, int valueCents) =>
    valueCents <= 0 || cents <= 0 ? 0 : cents ~/ valueCents;

/// "1 buono", "17 buoni" oppure, se l'importo non è un multiplo del valore
/// (es. dopo averlo cambiato), "17,5 buoni".
String formatVoucherCount(int cents, int valueCents) {
  if (valueCents <= 0) return '0 buoni';
  if (cents % valueCents == 0) {
    return plural(cents ~/ valueCents, 'buono', 'buoni');
  }
  final n = (cents / valueCents).toStringAsFixed(1).replaceAll('.', ',');
  return '$n buoni';
}

/// Buoni da proporre per una spesa di [amountCents]: il massimo che non
/// supera l'importo (i buoni non danno resto) né, se ce ne sono, i buoni
/// disponibili ([availableCents]). Almeno uno se la spesa lo consente.
int suggestedVoucherCents({
  required int amountCents,
  required int valueCents,
  required int availableCents,
}) {
  if (valueCents <= 0) return 0;
  var n = wholeVouchers(amountCents, valueCents);
  final available = wholeVouchers(availableCents, valueCents);
  if (available > 0 && available < n) n = available;
  if (n == 0) n = 1;
  return n * valueCents;
}

/// Un buono in più (arrotondando a un numero intero di buoni).
int addVoucher(int cents, int valueCents) =>
    (wholeVouchers(cents, valueCents) + 1) * valueCents;

/// Un buono in meno (arrotondando a un numero intero di buoni), mai sotto 0.
int removeVoucher(int cents, int valueCents) {
  if (valueCents <= 0 || cents <= 0) return 0;
  final whole = cents ~/ valueCents;
  // 17,5 buoni → 17; 17 buoni → 16.
  final n = cents % valueCents == 0 ? whole - 1 : whole;
  return n < 0 ? 0 : n * valueCents;
}
