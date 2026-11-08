import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../domain/debts.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy.dart';
import 'debt_detail_screen.dart';
import 'debt_editor_sheet.dart';

/// Apre il dettaglio di un debito con tutti i suoi pagamenti.
Future<void> openDebtDetail(BuildContext context, int debtId) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => DebtDetailScreen(debtId: debtId)));

/// Barra di avanzamento animata: quanto del debito è stato restituito.
class DebtProgressBar extends StatelessWidget {
  const DebtProgressBar({
    super.key,
    required this.progress,
    required this.color,
    this.height = 8,
  });

  final double progress;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(
          value: v,
          minHeight: height,
          color: color,
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
        ),
      ),
    ),
  );
}

/// Riga di un debito: nome, quanto resta e barra di avanzamento.
class DebtProgressTile extends StatelessWidget {
  const DebtProgressTile({super.key, required this.summary, this.onTap});

  final DebtSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final debt = summary.debt;
    final paidOff = summary.isPaidOff;
    final color = paidOff ? AppColors.income : Color(debt.color);

    return Semantics(
      container: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CategoryAvatar.debt(debt, size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          debt.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (paidOff)
                          Text(
                            summary.isInstallments
                                ? 'Estinto · ${summary.installmentCount} rate'
                                : 'Estinto · ${plural(summary.paymentCount, 'pagamento', 'pagamenti')}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.income,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else if (summary.isInstallments)
                          SensitiveText(
                            visibleText:
                                '${installmentsLabel(summary)} · restano '
                                '${formatMoney(summary.remainingCents)}',
                            hiddenText:
                                '${installmentsLabel(summary)} · restano '
                                '$kHiddenAmount',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          )
                        else
                          SensitiveText(
                            visibleText:
                                'Restano ${formatMoney(summary.remainingCents)} '
                                'su ${formatMoney(summary.amountCents)}',
                            hiddenText: 'Restano $kHiddenAmount',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (paidOff)
                    const Icon(Icons.verified_rounded, color: AppColors.income)
                  else
                    Text(
                      formatPercent(summary.progress),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  if (onTap != null)
                    Icon(Icons.chevron_right_rounded, color: muted),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 58),
                child: DebtProgressBar(
                  progress: summary.progress,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Elenco dei debiti in una card, separati da divisori.
class _DebtList extends StatelessWidget {
  const _DebtList({required this.debts});

  final List<DebtSummary> debts;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (i, d) in debts.indexed) ...[
        if (i > 0) const Divider(indent: 62),
        DebtProgressTile(
          summary: d,
          onTap: () => openDebtDetail(context, d.id),
        ),
      ],
    ],
  );
}

/// Sezione "Debiti" della scheda Conti: tutti i debiti, anche estinti.
class DebtsSection extends ConsumerWidget {
  const DebtsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final debts = ref.watch(debtsProvider).asData?.value ?? const [];
    final remaining = totalRemainingCents(debts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Debiti',
          subtitle: debts.isEmpty
              ? 'Prestiti e rate da restituire'
              : remaining == 0
              ? 'Tutti estinti'
              : 'Restano ${formatMoney(remaining)} da restituire',
          hiddenSubtitle: debts.isEmpty || remaining == 0
              ? null
              : 'Restano $kHiddenAmount da restituire',
          trailing: TextButton.icon(
            onPressed: () => showDebtEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nuovo debito'),
          ),
        ),
        const SizedBox(height: 12),
        if (debts.isEmpty)
          AppCard(
            onTap: () => showDebtEditor(context),
            child: Row(
              children: [
                const CategoryAvatar.icon(
                  icon: Icons.request_quote_rounded,
                  color: AppColors.expense,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Crea un debito (es. un prestito) e collega le spese con '
                    'cui lo restituisci: vedrai quanto manca per estinguerlo.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: _DebtList(debts: debts),
          ),
      ],
    );
  }
}

/// Card della dashboard con i debiti ancora da estinguere.
class DebtsOverviewCard extends StatelessWidget {
  const DebtsOverviewCard({super.key, required this.debts});

  /// Solo i debiti non ancora estinti.
  final List<DebtSummary> debts;

  @override
  Widget build(BuildContext context) {
    final remaining = totalRemainingCents(debts);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Debiti',
            subtitle: 'Restano ${formatMoney(remaining)} da restituire',
            hiddenSubtitle: 'Restano $kHiddenAmount da restituire',
            trailing: const PrivacyToggleButton(size: 20),
          ),
          const SizedBox(height: 4),
          _DebtList(debts: debts),
        ],
      ),
    );
  }
}

/// Scelta del debito a cui collegare una spesa ("Nessuno" per nessuno).
class DebtPicker extends StatelessWidget {
  const DebtPicker({
    super.key,
    required this.debts,
    required this.selectedId,
    required this.onSelected,
    required this.onCreate,
  });

  final List<DebtSummary> debts;
  final int? selectedId;
  final ValueChanged<int?> onSelected;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget pill({
      required bool selected,
      required Color color,
      required VoidCallback onTap,
      required Widget child,
    }) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.12)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: child,
      ),
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        pill(
          selected: selectedId == null,
          color: scheme.primary,
          onTap: () => onSelected(null),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: Text(
              'Nessuno',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: selectedId == null
                    ? FontWeight.w700
                    : FontWeight.w600,
              ),
            ),
          ),
        ),
        for (final d in debts)
          pill(
            selected: d.id == selectedId,
            color: Color(d.debt.color),
            // Un secondo tocco sul debito scelto lo scollega.
            onTap: () => onSelected(d.id == selectedId ? null : d.id),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CategoryAvatar.debt(d.debt, size: 34),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.debt.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: d.id == selectedId
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    if (d.isPaidOff)
                      Text(
                        'Estinto',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppColors.income,
                        ),
                      )
                    else if (d.isInstallments)
                      Text(
                        'Restano ${plural(d.remainingInstallments, 'rata', 'rate')}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else
                      SensitiveText(
                        visibleText: 'Restano ${formatMoney(d.remainingCents)}',
                        hiddenText: 'Restano $kHiddenAmount',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        InkWell(
          onTap: onCreate,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outline, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text('Nuovo debito', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
