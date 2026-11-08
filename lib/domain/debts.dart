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

  /// Totale del debito (per quelli a rate: rata × numero di rate).
  int get amountCents => debt.amountCents;

  /// `true` per un debito a rate con rata e numero di rate validi.
  bool get isInstallments =>
      debt.kind == DebtKind.installments &&
      (debt.installmentCents ?? 0) > 0 &&
      (debt.installmentCount ?? 0) > 0;

  /// Importo di una rata (0 se il debito non è a rate).
  int get installmentCents => isInstallments ? debt.installmentCents! : 0;

  /// Numero totale di rate (0 se il debito non è a rate).
  int get installmentCount => isInstallments ? debt.installmentCount! : 0;

  /// Quanto era già stato restituito prima di registrare i pagamenti
  /// nell'app: le rate già pagate indicate creando il debito.
  int get priorPaidCents => isInstallments
      ? installmentCents * debt.paidInstallments.clamp(0, installmentCount)
      : 0;

  /// Totale restituito: rate già pagate più spese collegate.
  int get repaidCents => priorPaidCents + paidCents;

  /// Quanto resta da restituire (mai sotto zero).
  int get remainingCents =>
      repaidCents >= amountCents ? 0 : amountCents - repaidCents;

  /// Quanto è stato pagato oltre il dovuto.
  int get overpaidCents =>
      repaidCents > amountCents ? repaidCents - amountCents : 0;

  /// Quota restituita (0..1).
  double get progress {
    if (amountCents <= 0) return 1;
    final p = repaidCents / amountCents;
    return p > 1 ? 1 : p;
  }

  bool get isPaidOff => repaidCents >= amountCents;

  /// Rate pagate, contate dall'importo restituito: una rata pagata con
  /// qualche centesimo in meno conta comunque (tolleranza del 5%), due rate
  /// pagate insieme contano due. 0 se il debito non è a rate.
  int get paidInstallments {
    if (!isInstallments) return 0;
    if (isPaidOff) return installmentCount;
    final paid = (repaidCents + installmentCents ~/ 20) ~/ installmentCents;
    return paid > installmentCount ? installmentCount : paid;
  }

  /// Rate ancora da pagare (0 se il debito non è a rate).
  int get remainingInstallments => installmentCount - paidInstallments;

  /// Il debito dopo un pagamento di [amountCents]. [alreadyLinkedCents] è la
  /// parte già contata (modificando un pagamento esistente dello stesso
  /// debito).
  DebtSummary afterPayment(int amountCents, {int alreadyLinkedCents = 0}) =>
      DebtSummary(
        debt: debt,
        paidCents: paidCents - alreadyLinkedCents + amountCents,
        paymentCount: paymentCount,
        lastPaymentDate: lastPaymentDate,
      );

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
/// Per un debito a rate [amountCents] è quanto restava dopo le rate già
/// pagate prima di usare l'app.
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
}) =>
    debt
        .afterPayment(amountCents, alreadyLinkedCents: alreadyLinkedCents)
        .remainingCents;

/// Testo breve sulle rate: "14 rate su 60 pagate".
String installmentsLabel(DebtSummary d) =>
    '${d.paidInstallments} ${d.paidInstallments == 1 ? 'rata' : 'rate'} '
    'su ${d.installmentCount} '
    '${d.paidInstallments == 1 ? 'pagata' : 'pagate'}';
