import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/utils/period.dart';
import 'core/utils/streams.dart';
import 'data/app_database.dart';
import 'data/connection.dart';
import 'data/models.dart';
import 'domain/analytics.dart';

// -----------------------------------------------------------------------------
// Infrastruttura
// -----------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(openAppDatabaseConnection());
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
