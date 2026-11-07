import '../core/utils/period.dart';
import '../data/app_database.dart';
import '../data/models.dart';

/// Totale di una categoria in un periodo.
class CategoryTotal {
  const CategoryTotal({
    required this.category,
    required this.totalCents,
    required this.count,
    required this.share,
  });

  final CategoryEntity category;
  final int totalCents;
  final int count;

  /// Quota sul totale del suo tipo (0..1).
  final double share;

  int get averageCents => count == 0 ? 0 : (totalCents / count).round();
}

/// Riepilogo di un insieme di movimenti.
class PeriodSummary {
  const PeriodSummary({
    required this.incomeCents,
    required this.expenseCents,
    required this.incomeCount,
    required this.expenseCount,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.biggestExpense,
  });

  factory PeriodSummary.from(Iterable<TransactionWithCategory> items) {
    var income = 0, expense = 0, incomeCount = 0, expenseCount = 0;
    TransactionWithCategory? biggest;
    for (final item in items) {
      if (item.isIncome) {
        income += item.tx.amountCents;
        incomeCount++;
      } else {
        expense += item.tx.amountCents;
        expenseCount++;
        if (biggest == null || item.tx.amountCents > biggest.tx.amountCents) {
          biggest = item;
        }
      }
    }
    return PeriodSummary(
      incomeCents: income,
      expenseCents: expense,
      incomeCount: incomeCount,
      expenseCount: expenseCount,
      expenseByCategory:
          _groupByCategory(items.where((i) => !i.isIncome), expense),
      incomeByCategory: _groupByCategory(items.where((i) => i.isIncome), income),
      biggestExpense: biggest,
    );
  }

  static const empty = PeriodSummary(
    incomeCents: 0,
    expenseCents: 0,
    incomeCount: 0,
    expenseCount: 0,
    expenseByCategory: [],
    incomeByCategory: [],
    biggestExpense: null,
  );

  final int incomeCents;
  final int expenseCents;
  final int incomeCount;
  final int expenseCount;
  final List<CategoryTotal> expenseByCategory;
  final List<CategoryTotal> incomeByCategory;
  final TransactionWithCategory? biggestExpense;

  int get balanceCents => incomeCents - expenseCents;
  int get count => incomeCount + expenseCount;
  bool get isEmpty => count == 0;

  /// Quota delle entrate non spesa. `null` se non ci sono entrate.
  double? get savingsRate =>
      incomeCents == 0 ? null : balanceCents / incomeCents;

  List<CategoryTotal> byType(TxType type) =>
      type == TxType.income ? incomeByCategory : expenseByCategory;

  int totalFor(TxType type) =>
      type == TxType.income ? incomeCents : expenseCents;
}

List<CategoryTotal> _groupByCategory(
  Iterable<TransactionWithCategory> items,
  int total,
) {
  final sums = <int, int>{};
  final counts = <int, int>{};
  final cats = <int, CategoryEntity>{};
  for (final item in items) {
    final id = item.category.id;
    cats[id] = item.category;
    sums[id] = (sums[id] ?? 0) + item.tx.amountCents;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  final result = [
    for (final id in sums.keys)
      CategoryTotal(
        category: cats[id]!,
        totalCents: sums[id]!,
        count: counts[id]!,
        share: total == 0 ? 0 : sums[id]! / total,
      ),
  ]..sort((a, b) => b.totalCents.compareTo(a.totalCents));
  return result;
}

/// Totali di un mese, per i grafici di andamento.
class MonthBucket {
  const MonthBucket(this.month, this.incomeCents, this.expenseCents);

  final DateTime month;
  final int incomeCents;
  final int expenseCents;

  int get balanceCents => incomeCents - expenseCents;
}

/// Raggruppa per mese di calendario tra [from] (incluso) e [to] (escluso).
List<MonthBucket> bucketByMonth(
  Iterable<TransactionWithCategory> items,
  DateTime from,
  DateTime to,
) {
  final income = <DateTime, int>{};
  final expense = <DateTime, int>{};
  for (final item in items) {
    final key = DateTime(item.tx.date.year, item.tx.date.month);
    final map = item.isIncome ? income : expense;
    map[key] = (map[key] ?? 0) + item.tx.amountCents;
  }
  final buckets = <MonthBucket>[];
  for (var m = DateTime(from.year, from.month);
      m.isBefore(to);
      m = DateTime(m.year, m.month + 1)) {
    buckets.add(MonthBucket(m, income[m] ?? 0, expense[m] ?? 0));
  }
  return buckets;
}

/// Dati della dashboard per il mese selezionato.
class DashboardData {
  const DashboardData({
    required this.period,
    required this.current,
    required this.previous,
    required this.trend,
    required this.recent,
    required this.averageDays,
  });

  /// [all] deve coprire i 6 mesi che terminano con [month]; [transfers] sono
  /// i trasferimenti del mese (mostrati tra gli ultimi movimenti).
  factory DashboardData.compute(
    DateTime month,
    List<TransactionWithCategory> all, {
    List<TransferWithAccounts> transfers = const [],
    DateTime? now,
  }) {
    final period = Period.month(month);
    final prev = period.previous();
    final currentItems =
        all.where((i) => period.contains(i.tx.date)).toList(growable: false);
    return DashboardData(
      period: period,
      current: PeriodSummary.from(currentItems),
      previous: PeriodSummary.from(all.where((i) => prev.contains(i.tx.date))),
      trend: bucketByMonth(
        all,
        DateTime(month.year, month.month - 5),
        period.end,
      ),
      recent: mergeMovements(
        currentItems,
        transfers.where((t) => period.contains(t.date)).toList(),
      ).take(5).toList(growable: false),
      averageDays: period.daysForAverage(now ?? DateTime.now()),
    );
  }

  final Period period;
  final PeriodSummary current;
  final PeriodSummary previous;
  final List<MonthBucket> trend;
  final List<Movement> recent;
  final int averageDays;

  int get dailyAverageExpense =>
      averageDays == 0 ? 0 : (current.expenseCents / averageDays).round();

  /// Variazione percentuale delle uscite rispetto al mese precedente.
  double? get expenseChange => previous.expenseCents == 0
      ? null
      : (current.expenseCents - previous.expenseCents) / previous.expenseCents;
}

/// Andamento di un conto in un periodo.
class AccountPeriodSummary {
  const AccountPeriodSummary({
    required this.account,
    required this.startCents,
    required this.incomeCents,
    required this.expenseCents,
    required this.transferInCents,
    required this.transferOutCents,
  });

  final AccountEntity account;

  /// Saldo all'inizio del periodo.
  final int startCents;
  final int incomeCents;
  final int expenseCents;
  final int transferInCents;
  final int transferOutCents;

  int get transferNetCents => transferInCents - transferOutCents;
  int get changeCents => incomeCents - expenseCents + transferNetCents;
  int get endCents => startCents + changeCents;
}

/// Dati della schermata Report per il periodo scelto.
class ReportData {
  const ReportData({
    required this.period,
    required this.summary,
    required this.months,
    required this.transactions,
    required this.transfers,
    required this.accounts,
    required this.averageDays,
  });

  /// [startBalances]: saldo di ogni conto all'inizio del periodo.
  factory ReportData.compute(
    Period period,
    List<TransactionWithCategory> items, {
    List<TransferWithAccounts> transfers = const [],
    List<AccountEntity> accounts = const [],
    Map<int, int> startBalances = const {},
    DateTime? now,
  }) {
    final accountSummaries = [
      for (final a in accounts)
        AccountPeriodSummary(
          account: a,
          startCents: startBalances[a.id] ?? a.initialBalanceCents,
          incomeCents: items
              .where((i) => i.isIncome && i.tx.accountId == a.id)
              .fold(0, (s, i) => s + i.tx.amountCents),
          expenseCents: items
              .where((i) => !i.isIncome && i.tx.accountId == a.id)
              .fold(0, (s, i) => s + i.tx.amountCents),
          transferInCents: transfers
              .where((t) => t.to.id == a.id)
              .fold(0, (s, t) => s + t.amountCents),
          transferOutCents: transfers
              .where((t) => t.from.id == a.id)
              .fold(0, (s, t) => s + t.amountCents),
        ),
    ];
    return ReportData(
      period: period,
      summary: PeriodSummary.from(items),
      months: bucketByMonth(items, period.start, period.end),
      transactions: items,
      transfers: transfers,
      accounts: accountSummaries,
      averageDays: period.daysForAverage(now ?? DateTime.now()),
    );
  }

  final Period period;
  final PeriodSummary summary;
  final List<MonthBucket> months;

  /// Ordinati dal più recente.
  final List<TransactionWithCategory> transactions;

  /// Ordinati dal più recente.
  final List<TransferWithAccounts> transfers;
  final List<AccountPeriodSummary> accounts;
  final int averageDays;

  bool get isEmpty => transactions.isEmpty && transfers.isEmpty;

  int get dailyAverageExpense =>
      averageDays == 0 ? 0 : (summary.expenseCents / averageDays).round();
}
