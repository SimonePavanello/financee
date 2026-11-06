import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../data/models.dart';
import '../../domain/analytics.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';

/// Card principale con gradiente: saldo del mese, entrate e uscite.
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = data.current;
    final rate = s.savingsRate;
    final change = data.expenseChange;
    final monthName = formatMonthName(data.period.start);
    final prevName = formatMonthName(data.period.previous().start);

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.violet.withValues(alpha: 0.35),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            const Positioned(right: -50, top: -60, child: _Bubble(size: 200)),
            const Positioned(right: 70, bottom: -80, child: _Bubble(size: 150)),
            const Positioned(left: -30, bottom: -40, child: _Bubble(size: 90)),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Saldo di $monthName',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (rate != null)
                        _GlassPill(
                          icon: Icons.savings_rounded,
                          text: 'Risparmio ${formatPercent(rate.clamp(-9.99, 1))}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: _AnimatedMoney(
                      cents: s.balanceCents,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _FlowTile(
                          label: 'Entrate',
                          cents: s.incomeCents,
                          icon: Icons.arrow_upward_rounded,
                          color: AppColors.income,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FlowTile(
                          label: 'Uscite',
                          cents: s.expenseCents,
                          icon: Icons.arrow_downward_rounded,
                          color: AppColors.expense,
                        ),
                      ),
                    ],
                  ),
                  if (change != null) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(
                          change > 0
                              ? Icons.trending_up_rounded
                              : Icons.trending_down_rounded,
                          size: 18,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            change == 0
                                ? 'Spese uguali a $prevName'
                                : 'Spese ${change > 0 ? '+' : '−'}${formatPercent(change.abs())} rispetto a $prevName',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.07),
        ),
      );
}

class _GlassPill extends StatelessWidget {
  const _GlassPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      );
}

class _FlowTile extends StatelessWidget {
  const _FlowTile({
    required this.label,
    required this.cents,
    required this.icon,
    required this.color,
  });

  final String label;
  final int cents;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: _AnimatedMoney(
                    cents: cents,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
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

class _AnimatedMoney extends StatelessWidget {
  const _AnimatedMoney({required this.cents, this.style});

  final int cents;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: cents.toDouble()),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, value, _) =>
            Text(formatMoney(value.round()), style: style),
      );
}

/// Piccole card con indicatori sintetici.
class QuickStats extends StatelessWidget {
  const QuickStats({super.key, required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final s = data.current;
    final top = s.expenseByCategory.firstOrNull;
    final biggest = s.biggestExpense;
    final tiles = [
      StatTile(
        icon: Icons.calendar_today_rounded,
        color: AppColors.indigo,
        label: 'Media giornaliera',
        value: formatMoney(data.dailyAverageExpense),
        caption: 'su ${plural(data.averageDays, 'giorno', 'giorni')}',
      ),
      StatTile(
        icon: Icons.receipt_long_rounded,
        color: const Color(0xFF0EA5E9),
        label: 'Movimenti',
        value: '${s.count}',
        caption:
            '${plural(s.incomeCount, 'entrata', 'entrate')} · ${plural(s.expenseCount, 'uscita', 'uscite')}',
      ),
      StatTile(
        icon: Icons.local_fire_department_rounded,
        color: AppColors.expense,
        label: 'Spesa più alta',
        value: biggest == null ? '—' : formatMoney(biggest.tx.amountCents),
        caption: biggest?.title ?? 'Nessuna spesa',
      ),
      StatTile(
        icon: Icons.donut_large_rounded,
        color: AppColors.violet,
        label: 'Categoria top',
        value: top?.category.name ?? '—',
        caption: top == null ? 'Nessuna spesa' : '${formatPercent(top.share)} delle uscite',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 640 ? 4 : 2;
        const spacing = 12.0;
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.caption,
    this.valueColor,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? caption;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(height: 12),
          Text(label, style: theme.textTheme.labelMedium?.copyWith(color: muted)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: muted),
            ),
        ],
      ),
    );
  }
}

/// Card "Dove vanno i tuoi soldi" con ciambella e legenda.
class CategoryBreakdownCard extends StatefulWidget {
  const CategoryBreakdownCard({super.key, required this.summary});

  final PeriodSummary summary;

  @override
  State<CategoryBreakdownCard> createState() => _CategoryBreakdownCardState();
}

class _CategoryBreakdownCardState extends State<CategoryBreakdownCard> {
  TxType _type = TxType.expense;
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final totals = widget.summary.byType(_type);
    final total = widget.summary.totalFor(_type);
    final isExpense = _type == TxType.expense;

    final donut = CategoryDonut(
      totals: totals,
      totalCents: total,
      centerLabel: isExpense ? 'Uscite' : 'Entrate',
      touchedIndex: _touched,
      onTouched: (i) => setState(() => _touched = i == _touched ? null : i),
      size: 190,
    );

    final legend = totals.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              isExpense
                  ? 'Nessuna spesa registrata in questo mese.'
                  : 'Nessuna entrata registrata in questo mese.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          )
        : Column(
            children: [
              for (final (i, t) in totals.indexed)
                CategoryShareRow(
                  category: t.category,
                  totalCents: t.totalCents,
                  share: t.share,
                  highlighted: i == _touched,
                  onTap: () => setState(() => _touched = i == _touched ? null : i),
                ),
            ],
          );

    final toggle = SegmentedButton<TxType>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: const [
        ButtonSegment(value: TxType.expense, label: Text('Uscite')),
        ButtonSegment(value: TxType.income, label: Text('Entrate')),
      ],
      selected: {_type},
      onSelectionChanged: (s) => setState(() {
        _type = s.first;
        _touched = null;
      }),
    );
    const header = SectionHeader(
      title: 'Dove vanno i tuoi soldi',
      subtitle: 'Ripartizione per categoria',
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth < 440
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [header, const SizedBox(height: 12), toggle],
                  )
                : Row(
                    children: [const Expanded(child: header), toggle],
                  ),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 560) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    donut,
                    const SizedBox(width: 24),
                    Expanded(child: legend),
                  ],
                );
              }
              return Column(
                children: [donut, const SizedBox(height: 16), legend],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Card "Andamento" con il grafico degli ultimi mesi.
class TrendCard extends StatelessWidget {
  const TrendCard({
    super.key,
    required this.buckets,
    this.title = 'Andamento',
    this.subtitle = 'Ultimi 6 mesi',
  });

  final List<MonthBucket> buckets;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final withData = buckets.where((b) => b.incomeCents + b.expenseCents > 0);
    final n = withData.isEmpty ? 1 : withData.length;
    final avgIncome = withData.fold<int>(0, (s, b) => s + b.incomeCents) ~/ n;
    final avgExpense = withData.fold<int>(0, (s, b) => s + b.expenseCents) ~/ n;
    final theme = Theme.of(context);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: title,
            subtitle: subtitle,
            trailing: const Wrap(
              spacing: 12,
              children: [
                LegendDot(color: AppColors.income, label: 'Entrate'),
                LegendDot(color: AppColors.expense, label: 'Uscite'),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TrendBarChart(buckets: buckets),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _AverageChip(
                  label: 'Media entrate / mese',
                  value: formatMoney(avgIncome),
                  color: AppColors.income,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AverageChip(
                  label: 'Media uscite / mese',
                  value: formatMoney(avgExpense),
                  color: AppColors.expense,
                ),
              ),
            ],
          ),
          if (withData.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Il grafico si riempirà man mano che registri movimenti.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _AverageChip extends StatelessWidget {
  const _AverageChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

/// Card "Ultimi movimenti".
class RecentTransactionsCard extends StatelessWidget {
  const RecentTransactionsCard({
    super.key,
    required this.items,
    required this.onSeeAll,
    required this.onTapItem,
  });

  final List<TransactionWithCategory> items;
  final VoidCallback onSeeAll;
  final ValueChanged<TransactionWithCategory> onTapItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: SectionHeader(
              title: 'Ultimi movimenti',
              trailing: TextButton(
                onPressed: onSeeAll,
                child: const Text('Vedi tutti'),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Nessun movimento in questo mese.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (final item in items)
              TransactionTile(item: item, onTap: () => onTapItem(item)),
        ],
      ),
    );
  }
}
