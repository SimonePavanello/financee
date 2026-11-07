import 'dart:math' as math;

import '../data/app_database.dart';

/// Giorni medi in un mese, per passare da giorni a mesi.
const _daysPerMonth = 30.4375;

/// Quanti giorni guardare indietro per il ritmo di risparmio (circa 3 mesi).
const kGoalPaceWindowDays = 91;

/// Sotto questi giorni di movimenti il ritmo non è significativo.
const _minPaceDays = 28;

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// A che punto è un obiettivo rispetto alla scadenza e al ritmo di risparmio.
enum GoalStatus {
  /// Il saldo ha raggiunto l'obiettivo.
  reached,

  /// La scadenza è passata senza raggiungerlo.
  overdue,

  /// Al ritmo attuale si arriva in tempo (o, senza scadenza, si sta
  /// mettendo da parte qualcosa).
  onTrack,

  /// Al ritmo attuale non si arriva entro la scadenza.
  behind,

  /// Negli ultimi mesi il saldo è fermo o è sceso.
  stalled,

  /// Il conto ha troppo pochi movimenti per stimare un ritmo.
  unknown,
}

/// Un punto dell'andamento del saldo: il saldo a fine giornata.
typedef BalancePoint = ({DateTime date, int balanceCents});

/// Un obiettivo con il saldo del suo conto e il ritmo di risparmio recente.
class GoalSummary {
  const GoalSummary({
    required this.goal,
    required this.account,
    required this.balanceCents,
    required this.deltas,
    this.monthlySavingCents,
  });

  final SavingsGoalEntity goal;
  final AccountEntity account;

  /// Saldo attuale del conto (come nella scheda Conti).
  final int balanceCents;

  /// Variazioni del saldo del conto, dalla più vecchia.
  final List<BalanceDelta> deltas;

  /// Quanto entra in media ogni mese sul conto negli ultimi 3 mesi (al
  /// netto delle uscite). Nullo se il conto ha meno di un mese di movimenti.
  final int? monthlySavingCents;

  int get id => goal.id;
  int get accountId => goal.accountId;
  int get targetCents => goal.targetCents;
  DateTime? get deadline => goal.deadline;

  bool get isReached => balanceCents >= targetCents;

  /// Quanto manca per arrivare all'obiettivo (zero se raggiunto).
  int get remainingCents => isReached ? 0 : targetCents - balanceCents;

  /// Quanto oltre l'obiettivo si è andati.
  int get extraCents => isReached ? balanceCents - targetCents : 0;

  /// Quota raggiunta (0..1); un saldo negativo conta come zero.
  double get progress {
    if (targetCents <= 0 || isReached) return 1;
    if (balanceCents <= 0) return 0;
    return balanceCents / targetCents;
  }

  /// Mesi che restano fino alla scadenza (almeno 1 se non è passata, 0 se
  /// è passata), nullo senza scadenza.
  int? monthsLeft(DateTime today) {
    final d = deadline;
    return d == null ? null : monthsUntil(today, d);
  }

  /// Quanto mettere da parte ogni mese per arrivare in tempo. Nullo se non
  /// c'è scadenza, se è passata o se l'obiettivo è già raggiunto.
  int? monthlyNeededCents(DateTime today) {
    final months = monthsLeft(today);
    if (months == null || months == 0 || isReached) return null;
    return (remainingCents / months).ceil();
  }

  /// Quando si raggiungerebbe l'obiettivo continuando al ritmo attuale.
  /// Nullo se è già raggiunto, se il ritmo non è positivo o se servirebbero
  /// più di 100 anni.
  DateTime? projectedDate(DateTime today) {
    final pace = monthlySavingCents;
    if (isReached || pace == null || pace <= 0) return null;
    final months = remainingCents / pace;
    if (months > 1200) return null;
    return _day(today).add(Duration(days: (months * _daysPerMonth).ceil()));
  }

  GoalStatus status(DateTime today) {
    if (isReached) return GoalStatus.reached;
    final months = monthsLeft(today);
    if (months == 0) return GoalStatus.overdue;
    final pace = monthlySavingCents;
    if (pace == null) return GoalStatus.unknown;
    if (pace <= 0) return GoalStatus.stalled;
    if (months == null) {
      return projectedDate(today) == null
          ? GoalStatus.stalled
          : GoalStatus.onTrack;
    }
    return pace >= monthlyNeededCents(today)! ? GoalStatus.onTrack : GoalStatus.behind;
  }

  /// Andamento del saldo nell'ultimo anno (o dal giorno prima del primo
  /// movimento, per partire dal saldo iniziale), un punto per ogni giorno
  /// con variazioni, fino a oggi.
  List<BalancePoint> history(DateTime today, {int days = 365}) =>
      balanceHistory(
        initialBalanceCents: account.initialBalanceCents,
        deltas: deltas,
        start: _historyStart(today, days),
        today: today,
      );

  DateTime _historyStart(DateTime today, int days) {
    final yearAgo = _day(today).subtract(Duration(days: days));
    var first = _day(goal.createdAt);
    final created = _day(account.createdAt);
    if (created.isBefore(first)) first = created;
    if (deltas.isNotEmpty && _day(deltas.first.$1).isBefore(first)) {
      first = _day(deltas.first.$1);
    }
    return first.isBefore(yearAgo)
        ? yearAgo
        : first.subtract(const Duration(days: 1));
  }

  /// Unisce obiettivi, conti e variazioni dei saldi: prima gli obiettivi da
  /// raggiungere, poi quelli raggiunti, ciascun gruppo nell'ordine dei conti.
  static List<GoalSummary> combine({
    required List<SavingsGoalEntity> goals,
    required List<AccountEntity> accounts,
    required Map<int, List<BalanceDelta>> deltas,
    required DateTime today,
  }) {
    final byId = {for (final a in accounts) a.id: a};
    final order = {for (final (i, a) in accounts.indexed) a.id: i};
    final all = <GoalSummary>[];
    for (final g in goals) {
      final account = byId[g.accountId];
      if (account == null) continue;
      final list = deltas[g.accountId] ?? const <BalanceDelta>[];
      all.add(
        GoalSummary(
          goal: g,
          account: account,
          balanceCents:
              account.initialBalanceCents + list.fold(0, (s, d) => s + d.$2),
          deltas: list,
          monthlySavingCents: monthlySaving(list, today),
        ),
      );
    }
    all.sort((a, b) => order[a.accountId]!.compareTo(order[b.accountId]!));
    return [
      ...all.where((g) => !g.isReached),
      ...all.where((g) => g.isReached),
    ];
  }
}

/// Mesi di calendario da [today] a [deadline], contando quello in corso se
/// la scadenza cade più avanti nel mese: dall'8 novembre all'8 febbraio sono
/// 3, al 31 dicembre dell'anno dopo 14. Almeno 1 fino alla scadenza
/// compresa, 0 quando è passata.
int monthsUntil(DateTime today, DateTime deadline) {
  final from = _day(today);
  final to = _day(deadline);
  if (to.isBefore(from)) return 0;
  final months = (to.year - from.year) * 12 +
      to.month -
      from.month +
      (to.day > from.day ? 1 : 0);
  return math.max(1, months);
}

/// Ritmo di risparmio: variazione media mensile del saldo negli ultimi
/// [windowDays] giorni (o da quando il conto ha movimenti, se più tardi).
/// Nullo se i movimenti coprono meno di 4 settimane.
int? monthlySaving(
  List<BalanceDelta> deltas,
  DateTime today, {
  int windowDays = kGoalPaceWindowDays,
}) {
  if (deltas.isEmpty) return null;
  final end = _day(today);
  var start = end.subtract(Duration(days: windowDays));
  final first = _day(deltas.first.$1);
  if (first.isAfter(start)) start = first;
  final span = end.difference(start).inDays;
  if (span < _minPaceDays) return null;
  var net = 0;
  for (final (date, cents) in deltas) {
    final d = _day(date);
    if (!d.isBefore(start) && !d.isAfter(end)) net += cents;
  }
  return (net * _daysPerMonth / span).round();
}

/// Saldo giorno per giorno da [start]: il saldo di quel giorno, poi un
/// punto per ogni giorno con variazioni e infine oggi (o l'ultimo giorno con
/// variazioni, se nel futuro).
List<BalancePoint> balanceHistory({
  required int initialBalanceCents,
  required List<BalanceDelta> deltas,
  required DateTime start,
  required DateTime today,
}) {
  final from = _day(start);
  var balance = initialBalanceCents;
  final byDay = <DateTime, int>{};
  for (final (date, cents) in deltas) {
    final d = _day(date);
    if (d.isAfter(from)) {
      byDay[d] = (byDay[d] ?? 0) + cents;
    } else {
      balance += cents;
    }
  }
  final points = <BalancePoint>[(date: from, balanceCents: balance)];
  for (final d in byDay.keys.toList()..sort()) {
    balance += byDay[d]!;
    points.add((date: d, balanceCents: balance));
  }
  final end = _day(today);
  if (points.last.date.isBefore(end)) {
    points.add((date: end, balanceCents: balance));
  }
  return points;
}
