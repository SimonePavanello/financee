import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/period.dart';
import '../../domain/analytics.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import '../dashboard/dashboard_widgets.dart';
import 'csv_report_builder.dart';
import 'export/file_export.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(reportPeriodProvider);
    final async = ref.watch(reportDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
        children: [
          PageContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PeriodControls(period: period),
                const SizedBox(height: 20),
                async.when(
                  skipLoadingOnReload: true,
                  loading: () => const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => ErrorView(error: e),
                  data: (data) => _ReportBody(data: data),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodControls extends ConsumerWidget {
  const _PeriodControls({required this.period});

  final Period period;

  Future<void> _pickRange(BuildContext context, WidgetRef ref) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: period.start, end: period.lastDay),
      helpText: 'Scegli il periodo',
      saveText: 'Applica',
    );
    if (range != null) {
      ref.read(reportPeriodProvider.notifier).setCustom(range.start, range.end);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(reportPeriodProvider.notifier);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<PeriodKind>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: PeriodKind.month, label: Text('Mese')),
            ButtonSegment(value: PeriodKind.year, label: Text('Anno')),
            ButtonSegment(value: PeriodKind.custom, label: Text('Intervallo')),
          ],
          selected: {period.kind},
          onSelectionChanged: (s) {
            notifier.setKind(s.first);
            if (s.first == PeriodKind.custom) _pickRange(context, ref);
          },
        ),
        PeriodNavigator(
          label: period.label,
          onPrevious: notifier.previous,
          onNext: notifier.next,
          onTapLabel: period.kind == PeriodKind.custom
              ? () => _pickRange(context, ref)
              : null,
        ),
        if (period.kind == PeriodKind.custom)
          IconButton.filledTonal(
            tooltip: 'Cambia periodo',
            onPressed: () => _pickRange(context, ref),
            icon: const Icon(Icons.date_range_rounded),
          ),
      ],
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.data});

  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final s = data.summary;
    const gap = SizedBox(height: 20, width: 20);

    final kpis = _KpiGrid(data: data);
    final expenses = _CategoryCard(
      title: 'Uscite per categoria',
      totals: s.expenseByCategory,
      total: s.expenseCents,
      emptyText: 'Nessuna uscita nel periodo.',
    );
    final incomes = _CategoryCard(
      title: 'Entrate per categoria',
      totals: s.incomeByCategory,
      total: s.incomeCents,
      emptyText: 'Nessuna entrata nel periodo.',
    );
    final trend = data.months.length > 1
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TrendCard(
                buckets: data.months,
                title: 'Andamento mensile',
                subtitle: data.period.label,
              ),
              gap,
              _MonthlyTable(months: data.months),
            ],
          )
        : null;
    final export = _ExportCard(data: data);
    final accounts = data.accounts.length > 1 ? _AccountsCard(data: data) : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            kpis,
            gap,
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: expenses),
                  gap,
                  Expanded(child: incomes),
                ],
              )
            else ...[
              expenses,
              gap,
              incomes,
            ],
            if (accounts != null) ...[gap, accounts],
            if (trend != null) ...[gap, trend],
            gap,
            export,
          ],
        );
      },
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.data});

  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final s = data.summary;
    final rate = s.savingsRate;
    final biggest = s.biggestExpense;
    final tiles = [
      StatTile(
        icon: Icons.arrow_upward_rounded,
        color: AppColors.income,
        label: 'Entrate',
        value: formatMoney(s.incomeCents),
        valueColor: AppColors.income,
        caption: plural(s.incomeCount, 'movimento', 'movimenti'),
      ),
      StatTile(
        icon: Icons.arrow_downward_rounded,
        color: AppColors.expense,
        label: 'Uscite',
        value: formatMoney(s.expenseCents),
        valueColor: AppColors.expense,
        caption: plural(s.expenseCount, 'movimento', 'movimenti'),
      ),
      StatTile(
        icon: Icons.account_balance_wallet_rounded,
        color: AppColors.indigo,
        label: 'Saldo',
        value: formatMoney(s.balanceCents),
        caption: s.balanceCents >= 0 ? 'Risparmiati' : 'In negativo',
      ),
      StatTile(
        icon: Icons.savings_rounded,
        color: AppColors.violet,
        label: 'Tasso di risparmio',
        value: rate == null ? '—' : formatPercent(rate),
        caption: rate == null ? 'Nessuna entrata' : 'delle entrate',
      ),
      StatTile(
        icon: Icons.calendar_today_rounded,
        color: const Color(0xFF0EA5E9),
        label: 'Spesa media al giorno',
        value: formatMoney(data.dailyAverageExpense),
        caption: 'su ${plural(data.averageDays, 'giorno', 'giorni')}',
      ),
      StatTile(
        icon: Icons.local_fire_department_rounded,
        color: AppColors.warning,
        label: 'Spesa più alta',
        value: biggest == null ? '—' : formatMoney(biggest.tx.amountCents),
        caption: biggest == null
            ? 'Nessuna spesa'
            : '${biggest.title} · ${formatShortDate(biggest.tx.date)}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 6
            : constraints.maxWidth >= 560
                ? 3
                : 2;
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

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.title,
    required this.totals,
    required this.total,
    required this.emptyText,
  });

  final String title;
  final List<CategoryTotal> totals;
  final int total;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SectionHeader(
              title: title,
              subtitle: 'Totale ${formatMoney(total)}',
            ),
          ),
          const SizedBox(height: 12),
          if (totals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                emptyText,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (final t in totals)
              CategoryShareRow(
                category: t.category,
                totalCents: t.totalCents,
                share: t.share,
                caption:
                    '${plural(t.count, 'movimento', 'movimenti')} · media ${formatMoney(t.averageCents)}',
              ),
        ],
      ),
    );
  }
}

class _MonthlyTable extends StatelessWidget {
  const _MonthlyTable({required this.months});

  final List<MonthBucket> months;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final head = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final cell = theme.textTheme.bodyMedium;

    Widget row(List<Widget> cells) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(
            children: [
              Expanded(flex: 3, child: cells[0]),
              for (final c in cells.skip(1))
                Expanded(flex: 3, child: Align(alignment: Alignment.centerRight, child: c)),
            ],
          ),
        );

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SectionHeader(title: 'Mese per mese'),
          ),
          const SizedBox(height: 8),
          row([
            Text('Mese', style: head),
            Text('Entrate', style: head),
            Text('Uscite', style: head),
            Text('Saldo', style: head),
          ]),
          const Divider(),
          for (final m in months)
            row([
              Text(formatMonthYear(m.month), style: cell?.copyWith(fontWeight: FontWeight.w600)),
              FittedBox(child: Text(formatMoney(m.incomeCents), style: cell?.copyWith(color: AppColors.income))),
              FittedBox(child: Text(formatMoney(m.expenseCents), style: cell?.copyWith(color: AppColors.expense))),
              FittedBox(
                child: Text(
                  formatMoney(m.balanceCents),
                  style: cell?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ]),
        ],
      ),
    );
  }
}

class _ExportCard extends StatefulWidget {
  const _ExportCard({required this.data});

  final ReportData data;

  @override
  State<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends State<_ExportCard> {
  bool _busy = false;

  Future<void> _export({required bool full}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final builder = CsvReportBuilder();
      final csv = full
          ? builder.buildFullReport(widget.data)
          : builder.buildTransactionsTable(widget.data);
      final message = await exportCsv(
        reportFileName(widget.data.period, full: full),
        csv,
      );
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Esportazione non riuscita: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final empty = widget.data.isEmpty;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: AppColors.buttonGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.file_download_rounded, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: SectionHeader(
                  title: 'Esporta in CSV',
                  subtitle:
                      '${widget.data.period.label} · ${plural(widget.data.transactions.length + widget.data.transfers.length, 'voce', 'voci')} · pronto per Excel, Numbers e Google Sheets',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final options = [
                _ExportOption(
                  icon: Icons.summarize_rounded,
                  title: 'Report completo',
                  description:
                      'Riepilogo con spiegazioni, saldi dei conti, totali per categoria, andamento mensile, trasferimenti e tutti i movimenti con saldo progressivo.',
                  onTap: empty || _busy ? null : () => _export(full: true),
                ),
                _ExportOption(
                  icon: Icons.table_rows_rounded,
                  title: 'Solo movimenti',
                  description:
                      'Una riga per movimento con conto e importo positivo o negativo: ideale per filtri e tabelle pivot.',
                  onTap: empty || _busy ? null : () => _export(full: false),
                ),
              ];
              if (constraints.maxWidth >= 640) {
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: options[0]),
                      const SizedBox(width: 12),
                      Expanded(child: options[1]),
                    ],
                  ),
                );
              }
              return Column(
                children: [options[0], const SizedBox(height: 12), options[1]],
              );
            },
          ),
          if (empty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Non ci sono movimenti da esportare in questo periodo.',
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

class _ExportOption extends StatelessWidget {
  const _ExportOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.download_rounded, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Saldi dei conti a inizio e fine periodo.
class _AccountsCard extends StatelessWidget {
  const _AccountsCard({required this.data});

  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final start = data.accounts.fold<int>(0, (s, a) => s + a.startCents);
    final end = data.accounts.fold<int>(0, (s, a) => s + a.endCents);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SectionHeader(
              title: 'Conti',
              subtitle:
                  'Patrimonio da ${formatMoney(start)} a ${formatMoney(end)}',
            ),
          ),
          const SizedBox(height: 8),
          for (final a in data.accounts)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  CategoryAvatar.account(a.account, size: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.account.name,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          [
                            '+${formatMoney(a.incomeCents)}',
                            '−${formatMoney(a.expenseCents)}',
                            if (a.transferNetCents != 0)
                              '⇄ ${formatSignedMoney(a.transferNetCents, isIncome: a.transferNetCents > 0)}',
                          ].join('  ·  '),
                          style: theme.textTheme.labelSmall?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatMoney(a.endCents),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: a.endCents < 0 ? AppColors.expense : null,
                        ),
                      ),
                      Text(
                        a.changeCents == 0
                            ? 'invariato'
                            : formatSignedMoney(a.changeCents,
                                isIncome: a.changeCents > 0),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: a.changeCents > 0
                              ? AppColors.income
                              : a.changeCents < 0
                                  ? AppColors.expense
                                  : muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
