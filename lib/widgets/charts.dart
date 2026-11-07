import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../domain/analytics.dart';

/// Grafico a barre affiancate entrate/uscite per mese.
class TrendBarChart extends StatelessWidget {
  const TrendBarChart({super.key, required this.buckets, this.height = 220});

  final List<MonthBucket> buckets;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxCents = buckets.fold<int>(
      0,
      (m, b) => math.max(m, math.max(b.incomeCents, b.expenseCents)),
    );
    // 4 righe della griglia con valori "tondi" (es. 1k, 2k, 3k, 4k).
    final interval = _niceCeil(maxCents / 100 * 1.08 / 4);
    final top = interval * 4;
    final barWidth = buckets.length > 8 ? 7.0 : 11.0;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: top,
          minY: 0,
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant,
              strokeWidth: 1,
              dashArray: const [4, 4],
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                interval: interval,
                getTitlesWidget: (value, meta) => Text(
                  formatCompactEuro(value),
                  style: labelStyle,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= buckets.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(formatShortMonth(buckets[i].month), style: labelStyle),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBorderRadius: BorderRadius.circular(12),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              maxContentWidth: 160,
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final b = buckets[group.x];
                return BarTooltipItem(
                  '${formatMonthYear(b.month)}\n',
                  TextStyle(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: rodIndex == 0
                          ? 'Entrate ${formatMoney(b.incomeCents)}'
                          : 'Uscite ${formatMoney(b.expenseCents)}',
                      style: TextStyle(
                        color: rodIndex == 0 ? AppColors.income : AppColors.expense,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          barGroups: [
            for (final (i, b) in buckets.indexed)
              BarChartGroupData(
                x: i,
                barsSpace: 4,
                barRods: [
                  _rod(b.incomeCents / 100, AppColors.income, barWidth),
                  _rod(b.expenseCents / 100, AppColors.expense, barWidth),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  static BarChartRodData _rod(double y, Color color, double width) =>
      BarChartRodData(
        toY: y,
        width: width,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.75), color],
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
        ),
      );

  /// Arrotonda verso l'alto a un valore "tondo" (1, 2, 2.5, 5 × 10^n).
  static double _niceCeil(double v) {
    if (v <= 0) return 25;
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1.0, 2.0, 2.5, 5.0, 10.0]) {
      if (v <= m * exp) return m * exp;
    }
    return 10 * exp;
  }
}

/// Grafico a ciambella delle categorie con totale al centro.
class CategoryDonut extends StatelessWidget {
  const CategoryDonut({
    super.key,
    required this.totals,
    required this.totalCents,
    required this.centerLabel,
    this.touchedIndex,
    this.onTouched,
    this.size = 200,
  });

  final List<CategoryTotal> totals;
  final int totalCents;
  final String centerLabel;
  final int? touchedIndex;
  final ValueChanged<int?>? onTouched;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final touched = touchedIndex != null && touchedIndex! < totals.length
        ? totals[touchedIndex!]
        : null;
    final ring = size * 0.13;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 3,
              centerSpaceRadius: size / 2 - ring - 6,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (onTouched == null) return;
                  if (!event.isInterestedForInteractions ||
                      response?.touchedSection == null) {
                    return;
                  }
                  final i = response!.touchedSection!.touchedSectionIndex;
                  onTouched!(i < 0 ? null : i);
                },
              ),
              sections: totals.isEmpty
                  ? [
                      PieChartSectionData(
                        value: 1,
                        color: scheme.surfaceContainerHighest,
                        radius: ring,
                        showTitle: false,
                      ),
                    ]
                  : [
                      for (final (i, t) in totals.indexed)
                        PieChartSectionData(
                          value: t.totalCents.toDouble(),
                          color: Color(t.category.color),
                          radius: i == touchedIndex ? ring + 6 : ring,
                          showTitle: false,
                        ),
                    ],
            ),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          ),
          Padding(
            padding: EdgeInsets.all(ring + 16),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Column(
                key: ValueKey(touched?.category.id),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    touched?.category.name ?? centerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      formatMoney(touched?.totalCents ?? totalCents),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (touched != null)
                    Text(
                      formatPercent(touched.share),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Color(touched.category.color),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pallino + etichetta per le legende.
class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      );
}

/// `true` per l'etichetta dell'asse sul minimo o sul massimo del grafico
/// quando non cade su un multiplo dell'intervallo: finirebbe sovrapposta a
/// quella vicina (es. "1,1k" appena sopra "1k").
bool isAxisEdgeLabel(double value, TitleMeta meta) {
  if (value != meta.max && value != meta.min) return false;
  final step = meta.appliedInterval;
  if (step <= 0) return false;
  final steps = value / step;
  return (steps - steps.roundToDouble()).abs() > 1e-6;
}
