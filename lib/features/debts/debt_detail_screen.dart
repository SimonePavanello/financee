import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../domain/debts.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy.dart';
import '../../widgets/transaction_tile.dart';
import '../transactions/transaction_form_screen.dart';
import 'debt_editor_sheet.dart';
import 'debt_widgets.dart';

/// Dettaglio di un debito: quanto resta, andamento e tutti i pagamenti
/// collegati.
class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({super.key, required this.debtId});

  final int debtId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    DebtSummary summary,
  ) async {
    final n = summary.paymentCount;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminare "${summary.debt.name}"?'),
        content: Text(
          n == 0
              ? 'Il debito non ha pagamenti collegati.'
              : '${n == 1 ? 'Il pagamento collegato resta' : 'I $n pagamenti collegati restano'} '
                    'tra i movimenti, senza debito.',
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
    await ref.read(databaseProvider).deleteDebt(summary.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtsProvider);
    final summary = debts.asData?.value
        .where((d) => d.id == debtId)
        .firstOrNull;
    if (summary == null) {
      return Scaffold(
        appBar: AppBar(),
        body: debts.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const Center(
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Debito non trovato',
                  message: 'Forse è stato eliminato.',
                ),
              ),
      );
    }
    final payments = ref.watch(debtMovementsProvider(debtId));

    return Scaffold(
      appBar: AppBar(
        title: Text(summary.debt.name),
        actions: [
          const PrivacyToggleButton(),
          IconButton(
            tooltip: 'Modifica debito',
            onPressed: () => showDebtEditor(context, existing: summary.debt),
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            tooltip: 'Elimina debito',
            onPressed: () => _delete(context, ref, summary),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: summary.isPaidOff
          ? null
          : FloatingActionButton.extended(
              heroTag: 'debt-payment',
              onPressed: () => openTransactionForm(context, debtId: debtId),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Registra un pagamento'),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
        children: [
          PageContainer(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DebtHeroCard(summary: summary),
                ...payments.when(
                  skipLoadingOnReload: true,
                  loading: () => const [
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
                  error: (e, _) => [ErrorView(error: e)],
                  data: (items) {
                    final points = debtTimeline(
                      // Le rate pagate prima di usare l'app sono già tolte
                      // dal punto di partenza.
                      amountCents: summary.amountCents - summary.priorPaidCents,
                      start: summary.debt.createdAt,
                      payments: [
                        for (final t in items) (t.tx.date, t.tx.amountCents),
                      ],
                    );
                    // Il grafico ha senso da quando c'è più di un giorno.
                    final now = DateTime.now();
                    final hasHistory =
                        items.isNotEmpty &&
                        points.first.date.isBefore(
                          DateTime(now.year, now.month, now.day),
                        );
                    return [
                      if (hasHistory) ...[
                        const SizedBox(height: 20),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SectionHeader(
                                title: 'Andamento',
                                subtitle: 'Quanto restava dopo ogni pagamento',
                              ),
                              const SizedBox(height: 16),
                              _DebtChart(
                                points: points,
                                color: summary.isPaidOff
                                    ? AppColors.income
                                    : Color(summary.debt.color),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SectionHeader(
                        title: 'Pagamenti',
                        subtitle: items.isEmpty
                            ? 'Nessun pagamento collegato'
                            : '${plural(items.length, 'pagamento', 'pagamenti')} · '
                                  'ultimo il ${formatDate(items.first.tx.date)}',
                      ),
                      const SizedBox(height: 12),
                      if (items.isEmpty)
                        const AppCard(
                          child: EmptyState(
                            icon: Icons.receipt_long_rounded,
                            title: 'Nessun pagamento',
                            message:
                                'Registra un pagamento da qui oppure, '
                                'quando inserisci una spesa, scegli questo '
                                'debito.',
                          ),
                        )
                      else
                        AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Column(
                            children: [
                              for (final (i, t) in items.indexed) ...[
                                if (i > 0) const Divider(indent: 64),
                                TransactionTile(
                                  item: t,
                                  showAccount: true,
                                  showDebt: false,
                                  onTap: () => openMovementForm(context, t),
                                ),
                              ],
                            ],
                          ),
                        ),
                    ];
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtHeroCard extends StatelessWidget {
  const _DebtHeroCard({required this.summary});

  final DebtSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final paidOff = summary.isPaidOff;
    final color = paidOff ? AppColors.income : Color(summary.debt.color);

    Widget figure(String label, int cents) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
        SensitiveAmount(
          cents: cents,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
    Widget plain(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );

    return AppCard(
      color: color.withValues(alpha: 0.07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar.debt(summary.debt, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      paidOff ? 'Debito estinto' : 'Restano',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: paidOff ? AppColors.income : muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (paidOff)
                      Row(
                        children: [
                          const Icon(
                            Icons.celebration_rounded,
                            color: AppColors.income,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Tutto restituito',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppColors.income,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      SensitiveAmount(
                        cents: summary.remainingCents,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: color,
                        ),
                      ),
                  ],
                ),
              ),
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
              figure('Restituiti', summary.repaidCents),
              figure('Totale del debito', summary.amountCents),
              if (summary.isInstallments) ...[
                figure('Rata', summary.installmentCents),
                plain(
                  'Rate pagate',
                  '${summary.paidInstallments} di ${summary.installmentCount}',
                ),
              ],
              plain('Pagamenti registrati', '${summary.paymentCount}'),
            ],
          ),
          if (summary.isInstallments && summary.debt.paidInstallments > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${plural(summary.debt.paidInstallments, 'rata pagata', 'rate pagate')} '
                'prima di registrare i pagamenti qui.',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (summary.overpaidCents > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SensitiveText(
                visibleText:
                    'Hai pagato ${formatMoney(summary.overpaidCents)} '
                    'più del totale del debito.',
                hiddenText: 'Hai pagato più del totale del debito.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.warning,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Grafico a gradini del residuo nel tempo.
class _DebtChart extends ConsumerWidget {
  const _DebtChart({required this.points, required this.color});

  final List<DebtPoint> points;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hidden = ref.watch(balancesHiddenProvider);
    final start = points.first.date;
    double x(DateTime d) => d.difference(start).inHours / 24;
    // La linea prosegue fino a oggi con l'ultimo residuo.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final shown = [
      ...points,
      if (today.isAfter(points.last.date))
        (date: today, remainingCents: points.last.remainingCents),
    ];
    final endX = x(shown.last.date);
    final maxX = math.max(endX, 1.0);
    final maxY =
        points.fold<int>(0, (m, p) => math.max(m, p.remainingCents)) /
        100 *
        1.08;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            drawVerticalLine: false,
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
                showTitles: !hidden,
                reservedSize: 44,
                getTitlesWidget: (value, meta) => isAxisEdgeLabel(value, meta)
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        child: Text(
                          formatCompactEuro(value),
                          style: labelStyle,
                        ),
                      ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxX,
                // Solo la prima e l'ultima data (niente etichetta oltre oggi).
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
                    '${formatShortDate(shown[s.spotIndex].date)}\n',
                    TextStyle(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    children: [
                      TextSpan(
                        text:
                            'Restano ${hidden ? kHiddenAmount : formatMoney(shown[s.spotIndex].remainingCents)}',
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
                for (final p in shown)
                  FlSpot(x(p.date), p.remainingCents / 100),
              ],
              isStepLineChart: true,
              color: color,
              barWidth: 3,
              dotData: FlDotData(
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
                    color.withValues(alpha: 0.28),
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
