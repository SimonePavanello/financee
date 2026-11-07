import '../data/app_database.dart';

/// Un debito con i suoi pagamenti: quanto è stato restituito e quanto resta.
class DebtSummary {
  const DebtSummary({
    required this.debt,
    this.paidCents = 0,
    this.paymentCount = 0,
    this.lastPaymentDate,
  });

  final DebtEntity debt;

  /// Somma delle spese collegate al debito.
  final int paidCents;
  final int paymentCount;
  final DateTime? lastPaymentDate;

  int get id => debt.id;
  int get amountCents => debt.amountCents;

  /// Quanto resta da restituire (mai sotto zero).
  int get remainingCents =>
      paidCents >= amountCents ? 0 : amountCents - paidCents;

  /// Quanto è stato pagato oltre il dovuto.
  int get overpaidCents =>
      paidCents > amountCents ? paidCents - amountCents : 0;

  /// Quota restituita (0..1).
  double get progress {
    if (amountCents <= 0) return 1;
    final p = paidCents / amountCents;
    return p > 1 ? 1 : p;
  }

  bool get isPaidOff => paidCents >= amountCents;

  /// Unisce i debiti con i loro pagamenti: prima quelli da estinguere, poi
  /// quelli estinti, ciascun gruppo nell'ordine di creazione.
  static List<DebtSummary> combine(
    List<DebtEntity> debts,
    Map<int, DebtPayments> payments,
  ) {
    final all = [
      for (final d in debts)
        DebtSummary(
          debt: d,
          paidCents: payments[d.id]?.paidCents ?? 0,
          paymentCount: payments[d.id]?.count ?? 0,
          lastPaymentDate: payments[d.id]?.lastDate,
        ),
    ];
    return [
      ...all.where((d) => !d.isPaidOff),
      ...all.where((d) => d.isPaidOff),
    ];
  }
}

/// Un punto dell'andamento di un debito: quanto restava in quel giorno.
typedef DebtPoint = ({DateTime date, int remainingCents});

/// Andamento del residuo: l'importo iniziale a [start] (o al primo
/// pagamento, se precedente) e poi un punto per ogni giorno con pagamenti.
/// [payments] sono coppie (data, importo) in qualsiasi ordine.
List<DebtPoint> debtTimeline({
  required int amountCents,
  required DateTime start,
  required Iterable<(DateTime, int)> payments,
}) {
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final byDay = <DateTime, int>{};
  for (final (date, cents) in payments) {
    byDay[day(date)] = (byDay[day(date)] ?? 0) + cents;
  }
  final days = byDay.keys.toList()..sort();
  var first = day(start);
  if (days.isNotEmpty && days.first.isBefore(first)) first = days.first;
  final points = <DebtPoint>[(date: first, remainingCents: amountCents)];
  var paid = 0;
  for (final d in days) {
    paid += byDay[d]!;
    final remaining = paid >= amountCents ? 0 : amountCents - paid;
    points.add((date: d, remainingCents: remaining));
  }
  return points;
}

/// Totale ancora da restituire su tutti i debiti.
int totalRemainingCents(Iterable<DebtSummary> debts) =>
    debts.fold(0, (s, d) => s + d.remainingCents);

/// Quanto resterebbe da restituire su [debt] dopo un pagamento di
/// [amountCents]. [alreadyLinkedCents] è la parte già contata nel debito
/// (quando si modifica un pagamento esistente dello stesso debito).
int remainingAfterPayment(
  DebtSummary debt,
  int amountCents, {
  int alreadyLinkedCents = 0,
}) {
  final paid = debt.paidCents - alreadyLinkedCents + amountCents;
  return paid >= debt.amountCents ? 0 : debt.amountCents - paid;
}
