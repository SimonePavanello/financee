import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../domain/savings_goals.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy.dart';
import '../debts/debt_widgets.dart';
import '../transactions/transaction_form_screen.dart';
import 'goal_editor_sheet.dart';
import 'goal_widgets.dart';

/// Dettaglio di un obiettivo di risparmio: quanto manca, se si è in linea
/// con la scadenza e come è cambiato il saldo del conto.
class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});

  final int goalId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    GoalSummary summary,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminare "${summary.goal.name}"?'),
        content: Text(
          'Il conto "${summary.account.name}" e i suoi movimenti restano.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final navigator = Navigator.of(context);
    await ref.read(databaseProvider).deleteSavingsGoal(summary.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(savingsGoalsProvider);
    final summary = goals.asData?.value
        .where((g) => g.id == goalId)
        .firstOrNull;
    if (summary == null) {
      return Scaffold(
        appBar: AppBar(),
        body: goals.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const Center(
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Obiettivo non trovato',
                  message: 'Forse è stato eliminato.',
                ),
              ),
      );
    }
    final accountCount =
        ref.watch(accountsProvider).asData?.value.length ?? 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final status = goalStatusLong(summary, context);
    final color = summary.isReached
        ? AppColors.income
        : Color(summary.account.color);

    return Scaffold(
      appBar: AppBar(
        title: Text(summary.goal.name),
        actions: [
          const PrivacyToggleButton(),
          IconButton(
            tooltip: 'Modifica obiettivo',
            onPressed: () => showGoalEditor(context, existing: summary.goal),
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: 'Elimina obiettivo',
            onPressed: () => _delete(context, ref, summary),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'goal-add',
        // Con più conti si sposta denaro sul conto dell'obiettivo; con un
        // solo conto si registra un'entrata.
        onPressed: () => accountCount >= 2
            ? openTransferForm(context, toAccountId: summary.accountId)
            : openTransactionForm(
                context,
                initialKind: MovementKind.income,
                accountId: summary.accountId,
              ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Aggiungi soldi'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
        children: [
          PageContainer(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GoalHeroCard(summary: summary, today: today),
                const SizedBox(height: 16),
                AppCard(
                  color: status.color.withValues(alpha: 0.08),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(status.icon, color: status.color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SensitiveText(
                          visibleText: status.visible,
                          hiddenText: status.hidden,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SectionHeader(
                        title: 'Andamento del saldo',
                        subtitle:
                            '"${summary.account.name}" nell\'ultimo anno, con '
                            'la linea dell\'obiettivo',
                      ),
                      const SizedBox(height: 16),
                      _GoalChart(
                        points: summary.history(today),
                        targetCents: summary.targetCents,
                        color: color,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalHeroCard extends StatelessWidget {
  const _GoalHeroCard({required this.summary, required this.today});

  final GoalSummary summary;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final reached = summary.isReached;
    final color = reached ? AppColors.income : Color(summary.account.color);
    final pace = summary.monthlySavingCents;
    final needed = summary.monthlyNeededCents(today);

    Widget label(String text) =>
        Text(text, style: theme.textTheme.labelMedium?.copyWith(color: muted));
    final valueStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w800,
    );
    Widget figure(String text, int cents, {String Function(int)? format}) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            label(text),
            SensitiveAmount(
              cents: cents,
              style: valueStyle,
              format: format ?? formatMoney,
            ),
          ],
        );
    Widget plain(String text, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        label(text),
        Text(value, style: valueStyle),
      ],
    );
    String perMonth(int c) => '${formatMoney(c)} al mese';
    String pacePerMonth(int c) => '${c > 0 ? '+' : ''}${perMonth(c)}';

    return AppCard(
      color: color.withValues(alpha: 0.07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar.account(summary.account, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reached
                          ? '${summary.account.name} · raggiunto'
                          : '${summary.account.name} · messi da parte',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: reached ? AppColors.income : muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SensitiveAmount(
                      cents: summary.balanceCents,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              if (reached)
                const Icon(
                  Icons.verified_rounded,
                  color: AppColors.income,
                  size: 30,
                )
              else
                Text(
                  formatPercent(summary.progress),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DebtProgressBar(progress: summary.progress, color: color, height: 12),
          const SizedBox(height: 16),
          Wrap(
            spacing: 32,
            runSpacing: 12,
            children: [
              figure('Obiettivo', summary.targetCents),
              if (!reached) figure('Mancano', summary.remainingCents),
              plain(
                'Scadenza',
                summary.deadline == null
                    ? 'Nessuna'
                    : formatDate(summary.deadline!),
              ),
              if (needed != null)
                figure('Servono', needed, format: perMonth),
              if (pace != null)
                figure('Ritmo (ultimi 3 mesi)', pace, format: pacePerMonth),
            ],
          ),
        ],
      ),
    );
  }
}

/// Saldo del conto nel tempo (a gradini) con la linea tratteggiata
/// dell'obiettivo.
class _GoalChart extends ConsumerWidget {
  const _GoalChart({
    required this.points,
    required this.targetCents,
    required this.color,
  });

  final List<BalancePoint> points;
  final int targetCents;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hidden = ref.watch(balancesHiddenProvider);
    final start = points.first.date;
    double x(DateTime d) => d.difference(start).inHours / 24;
    final endX = x(points.last.date);
    final maxX = math.max(endX, 1.0);
    final values = [for (final p in points) p.balanceCents, targetCents];
    final top = values.reduce(math.max) / 100;
    final bottom = math.min(0, values.reduce(math.min)) / 100;
    final pad = (top - bottom) * 0.08;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: bottom < 0 ? bottom - pad : 0,
          maxY: top + (pad <= 0 ? 1 : pad),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: scheme.outlineVariant,
              strokeWidth: 1,
              dashArray: const [4, 4],
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: targetCents / 100,
                color: AppColors.income,
                strokeWidth: 2,
                dashArray: const [8, 5],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.income,
                    fontWeight: FontWeight.w800,
                  ),
                  labelResolver: (_) => hidden
                      ? 'Obiettivo'
                      : 'Obiettivo ${formatMoney(targetCents)}',
                ),
              ),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: !hidden,
                reservedSize: 44,
                getTitlesWidget: (value, meta) => isAxisEdgeLabel(value, meta)
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        child: Text(formatCompactEuro(value), style: labelStyle),
                      ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxX,
                getTitlesWidget: (value, meta) => value > endX + 0.01
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                        child: Text(
                          formatShortDate(
                            start.add(Duration(hours: (value * 24).round())),
                          ),
                          style: labelStyle,
                        ),
                      ),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipBorderRadius: BorderRadius.circular(12),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${formatShortDate(points[s.spotIndex].date)}\n',
                    TextStyle(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text:
                            'Saldo ${hidden ? kHiddenAmount : formatMoney(points[s.spotIndex].balanceCents)}',
                        style: TextStyle(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final p in points)
                  FlSpot(x(p.date), p.balanceCents / 100),
              ],
              isStepLineChart: true,
              color: color,
              barWidth: 3,
              dotData: FlDotData(
                show: points.length <= 40,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                      radius: 3.5,
                      color: color,
                      strokeWidth: 2,
                      strokeColor: scheme.surface,
                    ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.24),
                    color.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      ),
    );
  }
}
