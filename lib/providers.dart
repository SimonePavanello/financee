import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/utils/period.dart';
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

final monthTransactionsProvider =
    StreamProvider.autoDispose<List<TransactionWithCategory>>((ref) {
  final period = Period.month(ref.watch(selectedMonthProvider));
  return ref
      .watch(databaseProvider)
      .watchTransactionsBetween(period.start, period.end);
});

final dashboardProvider = StreamProvider.autoDispose<DashboardData>((ref) {
  final month = ref.watch(selectedMonthProvider);
  final from = DateTime(month.year, month.month - 5);
  final to = DateTime(month.year, month.month + 1);
  return ref
      .watch(databaseProvider)
      .watchTransactionsBetween(from, to)
      .map((all) => DashboardData.compute(month, all));
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
  return ref
      .watch(databaseProvider)
      .watchTransactionsBetween(period.start, period.end)
      .map((items) => ReportData.compute(period, items));
});
