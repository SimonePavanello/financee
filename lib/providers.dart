import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/utils/period.dart';
import 'core/utils/streams.dart';
import 'data/app_database.dart';
import 'data/connection.dart';
import 'data/models.dart';
import 'domain/analytics.dart';
import 'domain/debts.dart';
import 'domain/meal_vouchers.dart';
import 'domain/savings_goals.dart';

// -----------------------------------------------------------------------------
// Infrastruttura
// -----------------------------------------------------------------------------

/// Nome del database da aprire (vedi [prepareAppDatabase], in `main()`).
final databaseNameProvider = Provider<String>((ref) => kDatabaseName);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(
    openAppDatabaseConnection(ref.watch(databaseNameProvider)),
  );
  ref.onDispose(db.close);
  return db;
});

/// Sovrascritto in `main()` con l'istanza già caricata.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('SharedPreferences non inizializzate'),
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(sharedPreferencesProvider).setString(_key, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

// -----------------------------------------------------------------------------
// Privacy: saldi nascosti
// -----------------------------------------------------------------------------

const _hideOnStartKey = 'hide_balances_on_start';

/// Impostazione salvata: all'apertura dell'app saldi e conti sono nascosti.
class HideBalancesOnStartNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_hideOnStartKey) ?? true;

  void set(bool value) {
    state = value;
    ref.read(sharedPreferencesProvider).setBool(_hideOnStartKey, value);
    // Applica subito la scelta anche alla sessione in corso.
    ref.read(balancesHiddenProvider.notifier).set(value);
  }
}

final hideBalancesOnStartProvider =
    NotifierProvider<HideBalancesOnStartNotifier, bool>(
  HideBalancesOnStartNotifier.new,
);

/// Stato della sessione: `true` se saldi e conti sono coperti da "••••".
/// Parte dall'impostazione salvata; l'icona a occhio lo inverte.
class BalancesHiddenNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(_hideOnStartKey) ?? true;

  void toggle() => state = !state;
  void set(bool value) => state = value;
}

final balancesHiddenProvider =
    NotifierProvider<BalancesHiddenNotifier, bool>(BalancesHiddenNotifier.new);

// -----------------------------------------------------------------------------
// Backup
// -----------------------------------------------------------------------------

/// Data dell'ultimo backup esportato (o ripristinato), `null` se mai fatto.
class LastBackupNotifier extends Notifier<DateTime?> {
  static const _key = 'last_backup_at';

  @override
  DateTime? build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return saved == null ? null : DateTime.tryParse(saved);
  }

  void set(DateTime date) {
    state = date;
    ref.read(sharedPreferencesProvider).setString(_key, date.toIso8601String());
  }
}

final lastBackupProvider =
    NotifierProvider<LastBackupNotifier, DateTime?>(LastBackupNotifier.new);

/// Fino a quando non mostrare il promemoria del backup in dashboard.
class BackupReminderSnoozeNotifier extends Notifier<DateTime?> {
  static const _key = 'backup_reminder_snoozed_until';

  @override
  DateTime? build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return saved == null ? null : DateTime.tryParse(saved);
  }

  void snooze(Duration duration) {
    final until = DateTime.now().add(duration);
    state = until;
    ref.read(sharedPreferencesProvider).setString(_key, until.toIso8601String());
  }
}

final backupReminderSnoozeProvider =
    NotifierProvider<BackupReminderSnoozeNotifier, DateTime?>(
  BackupReminderSnoozeNotifier.new,
);

// -----------------------------------------------------------------------------
// Conti
// -----------------------------------------------------------------------------

final accountsProvider = StreamProvider<List<AccountEntity>>(
  (ref) => ref.watch(databaseProvider).watchAccounts(),
);

/// Saldo attuale di ogni conto (id -> centesimi).
final accountBalancesProvider = StreamProvider<Map<int, int>>(
  (ref) => ref.watch(databaseProvider).watchAccountBalances(),
);

/// Numero di movimenti e trasferimenti per conto.
final accountUsageProvider = StreamProvider<Map<int, int>>(
  (ref) => ref.watch(databaseProvider).watchAccountUsage(),
);

// -----------------------------------------------------------------------------
// Buoni pasto
// -----------------------------------------------------------------------------

/// Valore di un buono pasto in centesimi (impostazione, predefinito 8 €).
class MealVoucherValueNotifier extends Notifier<int> {
  static const _key = 'meal_voucher_value_cents';

  @override
  int build() =>
      ref.watch(sharedPreferencesProvider).getInt(_key) ??
      kDefaultMealVoucherValueCents;

  void set(int cents) {
    if (cents <= 0) return;
    state = cents;
    ref.read(sharedPreferencesProvider).setInt(_key, cents);
  }
}

final mealVoucherValueProvider =
    NotifierProvider<MealVoucherValueNotifier, int>(MealVoucherValueNotifier.new);

/// Il conto dei buoni pasto, se è stato attivato nelle impostazioni.
final mealVoucherAccountProvider = Provider<AccountEntity?>(
  (ref) => ref
      .watch(accountsProvider)
      .asData
      ?.value
      .where((a) => a.kind == AccountKind.mealVoucher)
      .firstOrNull,
);

// -----------------------------------------------------------------------------
// Obiettivi di risparmio
// -----------------------------------------------------------------------------

/// Obiettivi con il saldo del conto e il ritmo di risparmio: prima quelli
/// da raggiungere.
final savingsGoalsProvider = StreamProvider<List<GoalSummary>>((ref) {
  final db = ref.watch(databaseProvider);
  return combineLatestAll([
    db.watchSavingsGoals(),
    db.watchAccounts(),
    db.watchGoalAccountDeltas(),
  ]).map(
    (v) => GoalSummary.combine(
      goals: v[0] as List<SavingsGoalEntity>,
      accounts: v[1] as List<AccountEntity>,
      deltas: v[2] as Map<int, List<BalanceDelta>>,
      today: DateTime.now(),
    ),
  );
});

// -----------------------------------------------------------------------------
// Debiti
// -----------------------------------------------------------------------------

/// Debiti con quanto è stato restituito: prima quelli da estinguere.
final debtsProvider = StreamProvider<List<DebtSummary>>((ref) {
  final db = ref.watch(databaseProvider);
  return combineLatest2(
    db.watchDebts(),
    db.watchDebtPayments(),
    DebtSummary.combine,
  );
});

/// Tutti i pagamenti collegati a un debito, dal più recente.
final debtMovementsProvider = StreamProvider.autoDispose
    .family<List<TransactionWithCategory>, int>(
  (ref, debtId) => ref.watch(databaseProvider).watchDebtTransactions(debtId),
);

/// Conto su cui è filtrata la lista movimenti (`null` = tutti).
class AccountFilterNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? accountId) => state = accountId;
}

final accountFilterProvider =
    NotifierProvider<AccountFilterNotifier, int?>(AccountFilterNotifier.new);

// -----------------------------------------------------------------------------
// Categorie
// -----------------------------------------------------------------------------

final categoriesProvider = StreamProvider<List<CategoryEntity>>(
  (ref) => ref.watch(databaseProvider).watchCategories(),
);

final categoryUsageProvider = StreamProvider<Map<int, int>>(
  (ref) => ref.watch(databaseProvider).watchCategoryUsage(),
);

// -----------------------------------------------------------------------------
// Mese selezionato (condiviso da Dashboard e Movimenti)
// -----------------------------------------------------------------------------

class SelectedMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  void previous() => state = DateTime(state.year, state.month - 1);
  void next() => state = DateTime(state.year, state.month + 1);
  void reset() => state = build();
}

final selectedMonthProvider =
    NotifierProvider<SelectedMonthNotifier, DateTime>(SelectedMonthNotifier.new);

final transactionCountProvider = StreamProvider<int>(
  (ref) => ref.watch(databaseProvider).watchTransactionCount(),
);

/// Movimenti e trasferimenti del mese selezionato.
final monthMovementsProvider =
    StreamProvider.autoDispose<List<Movement>>((ref) {
  final period = Period.month(ref.watch(selectedMonthProvider));
  return ref
      .watch(databaseProvider)
      .watchMovementsBetween(period.start, period.end);
});

final dashboardProvider = StreamProvider.autoDispose<DashboardData>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final db = ref.watch(databaseProvider);
  final current = Period.month(month);
  return combineLatest2(
    db.watchTransactionsBetween(
      DateTime(month.year, month.month - 5),
      current.end,
    ),
    db.watchTransfersBetween(current.start, current.end),
    (all, transfers) =>
        DashboardData.compute(month, all, transfers: transfers),
  );
});

// -----------------------------------------------------------------------------
// Report
// -----------------------------------------------------------------------------

class ReportPeriodNotifier extends Notifier<Period> {
  @override
  Period build() => Period.month(DateTime.now());

  void setKind(PeriodKind kind) {
    final now = DateTime.now();
    state = switch (kind) {
      PeriodKind.month => Period.month(
          state.kind == PeriodKind.year && state.start.year == now.year
              ? now
              : state.start,
        ),
      PeriodKind.year => Period.year(state.start.year),
      PeriodKind.custom => Period.custom(state.start, state.lastDay),
    };
  }

  void previous() => state = state.previous();
  void next() => state = state.next();
  void setCustom(DateTime from, DateTime to) =>
      state = Period.custom(from, to);
}

final reportPeriodProvider =
    NotifierProvider<ReportPeriodNotifier, Period>(ReportPeriodNotifier.new);

final reportDataProvider = StreamProvider.autoDispose<ReportData>((ref) {
  final period = ref.watch(reportPeriodProvider);
  final db = ref.watch(databaseProvider);
  return combineLatestAll([
    db.watchTransactionsBetween(period.start, period.end),
    db.watchTransfersBetween(period.start, period.end),
    db.watchAccounts(),
    db.watchAccountBalances(before: period.start),
  ]).map(
    (v) => ReportData.compute(
      period,
      v[0] as List<TransactionWithCategory>,
      transfers: v[1] as List<TransferWithAccounts>,
      accounts: v[2] as List<AccountEntity>,
      startBalances: v[3] as Map<int, int>,
    ),
  );
});
