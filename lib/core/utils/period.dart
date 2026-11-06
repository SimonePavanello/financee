import 'formatters.dart';

enum PeriodKind { month, year, custom }

/// Intervallo temporale [start, end) usato da dashboard e report.
class Period {
  const Period._(this.start, this.end, this.kind);

  factory Period.month(DateTime d) => Period._(
        DateTime(d.year, d.month),
        DateTime(d.year, d.month + 1),
        PeriodKind.month,
      );

  factory Period.year(int year) =>
      Period._(DateTime(year), DateTime(year + 1), PeriodKind.year);

  /// [from] e [to] sono entrambi inclusi.
  factory Period.custom(DateTime from, DateTime to) => Period._(
        DateTime(from.year, from.month, from.day),
        DateTime(to.year, to.month, to.day + 1),
        PeriodKind.custom,
      );

  final DateTime start;
  final DateTime end;
  final PeriodKind kind;

  /// Ultimo giorno incluso nel periodo.
  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  int get days => daysBetween(start, end);

  /// Numero di mesi di calendario toccati dal periodo.
  int get monthSpan =>
      (lastDay.year - start.year) * 12 + lastDay.month - start.month + 1;

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  Period previous() => switch (kind) {
        PeriodKind.month => Period.month(DateTime(start.year, start.month - 1)),
        PeriodKind.year => Period.year(start.year - 1),
        PeriodKind.custom => Period.custom(
            DateTime(start.year, start.month, start.day - days),
            DateTime(start.year, start.month, start.day - 1),
          ),
      };

  Period next() => switch (kind) {
        PeriodKind.month => Period.month(DateTime(start.year, start.month + 1)),
        PeriodKind.year => Period.year(start.year + 1),
        PeriodKind.custom => Period.custom(
            end,
            DateTime(end.year, end.month, end.day + days - 1),
          ),
      };

  String get label => switch (kind) {
        PeriodKind.month => formatMonthYear(start),
        PeriodKind.year => 'Anno ${start.year}',
        PeriodKind.custom => '${formatDate(start)} – ${formatDate(lastDay)}',
      };

  /// Usato nei nomi dei file esportati.
  String get fileSlug {
    String two(int v) => v.toString().padLeft(2, '0');
    String iso(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
    return switch (kind) {
      PeriodKind.month => '${start.year}-${two(start.month)}',
      PeriodKind.year => '${start.year}',
      PeriodKind.custom => '${iso(start)}_${iso(lastDay)}',
    };
  }

  /// Giorni su cui calcolare le medie: se il periodo è in corso si contano
  /// solo i giorni trascorsi, oggi compreso.
  int daysForAverage(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (!today.isBefore(end) || today.isBefore(start)) return days;
    return daysBetween(start, today) + 1;
  }

  @override
  bool operator ==(Object other) =>
      other is Period &&
      other.start == start &&
      other.end == end &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(start, end, kind);

  @override
  String toString() => 'Period($label)';
}

/// Differenza in giorni di calendario, immune ai cambi di ora legale.
int daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;
