import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../domain/savings_goals.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy.dart';
import '../debts/debt_widgets.dart';
import 'goal_detail_screen.dart';
import 'goal_editor_sheet.dart';

/// Apre il dettaglio di un obiettivo di risparmio.
Future<void> openGoalDetail(BuildContext context, int goalId) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => GoalDetailScreen(goalId: goalId)));

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// Descrizione dello stato di un obiettivo: icona, colore e testo (con e
/// senza importi, per la modalità privacy).
typedef GoalStatusInfo = ({
  IconData icon,
  Color color,
  String visible,
  String hidden,
});

/// Stato breve, per le righe delle liste.
GoalStatusInfo goalStatusShort(GoalSummary g, BuildContext context) {
  final today = _today();
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  final deadline = g.deadline;
  final projected = g.projectedDate(today);
  GoalStatusInfo same(IconData icon, Color color, String text) =>
      (icon: icon, color: color, visible: text, hidden: text);
  return switch (g.status(today)) {
    GoalStatus.reached => same(
      Icons.verified_rounded,
      AppColors.income,
      'Obiettivo raggiunto',
    ),
    GoalStatus.overdue => same(
      Icons.event_busy_rounded,
      AppColors.warning,
      'Scadenza passata il ${formatDate(deadline!)}',
    ),
    GoalStatus.onTrack when deadline != null => same(
      Icons.trending_up_rounded,
      AppColors.income,
      'In linea per il ${formatDate(deadline)}',
    ),
    GoalStatus.onTrack => same(
      Icons.trending_up_rounded,
      AppColors.income,
      'Al ritmo attuale: ${formatMonthYear(projected!).toLowerCase()}',
    ),
    GoalStatus.behind => same(
      Icons.trending_down_rounded,
      AppColors.warning,
      'In ritardo per il ${formatDate(deadline!)}',
    ),
    GoalStatus.stalled => same(
      Icons.trending_flat_rounded,
      AppColors.warning,
      'Saldo fermo negli ultimi mesi',
    ),
    GoalStatus.unknown => same(
      Icons.flag_rounded,
      muted,
      deadline == null ? 'Nessuna scadenza' : 'Entro il ${formatDate(deadline)}',
    ),
  };
}

/// Stato completo, per il dettaglio dell'obiettivo.
GoalStatusInfo goalStatusLong(GoalSummary g, BuildContext context) {
  final today = _today();
  final muted = Theme.of(context).colorScheme.onSurfaceVariant;
  final deadline = g.deadline;
  final needed = g.monthlyNeededCents(today);
  final pace = g.monthlySavingCents;
  final projected = g.projectedDate(today);
  final when = projected == null
      ? null
      : formatMonthYear(projected).toLowerCase();
  return switch (g.status(today)) {
    GoalStatus.reached => (
      icon: Icons.celebration_rounded,
      color: AppColors.income,
      visible: g.extraCents > 0
          ? 'Obiettivo raggiunto, con ${formatMoney(g.extraCents)} in più. '
                'Puoi alzarlo o crearne uno nuovo.'
          : 'Obiettivo raggiunto! Puoi alzarlo o crearne uno nuovo.',
      hidden: 'Obiettivo raggiunto! Puoi alzarlo o crearne uno nuovo.',
    ),
    GoalStatus.overdue => (
      icon: Icons.event_busy_rounded,
      color: AppColors.warning,
      visible: 'La scadenza del ${formatDate(deadline!)} è passata e mancano '
          'ancora ${formatMoney(g.remainingCents)}. Puoi spostarla dalla '
          'modifica dell\'obiettivo.',
      hidden: 'La scadenza del ${formatDate(deadline)} è passata. Puoi '
          'spostarla dalla modifica dell\'obiettivo.',
    ),
    GoalStatus.onTrack when deadline != null => (
      icon: Icons.trending_up_rounded,
      color: AppColors.income,
      visible: 'Sei in linea: per arrivare al ${formatDate(deadline)} servono '
          '${formatMoney(needed!)} al mese e negli ultimi 3 mesi ne hai '
          'messi da parte in media ${formatMoney(pace!)}'
          '${when == null ? '' : ' (al ritmo attuale ci arrivi a $when)'}.',
      hidden: 'Sei in linea per arrivare al ${formatDate(deadline)}'
          '${when == null ? '' : ' (al ritmo attuale ci arrivi a $when)'}.',
    ),
    GoalStatus.onTrack => (
      icon: Icons.trending_up_rounded,
      color: AppColors.income,
      visible: 'Negli ultimi 3 mesi hai messo da parte in media '
          '${formatMoney(pace!)} al mese: a questo ritmo lo raggiungi a $when.',
      hidden: 'A questo ritmo lo raggiungi a $when.',
    ),
    GoalStatus.behind => (
      icon: Icons.trending_down_rounded,
      color: AppColors.warning,
      visible: 'Per arrivare al ${formatDate(deadline!)} servono '
          '${formatMoney(needed!)} al mese, ma negli ultimi 3 mesi ne hai '
          'messi da parte in media ${formatMoney(pace!)}'
          '${when == null ? '' : ': a questo ritmo ci arrivi a $when'}.',
      hidden: 'Al ritmo attuale non arrivi entro il ${formatDate(deadline)}'
          '${when == null ? '' : ' (ci arrivi a $when)'}.',
    ),
    GoalStatus.stalled => (
      icon: Icons.trending_flat_rounded,
      color: AppColors.warning,
      visible: needed == null
          ? 'Negli ultimi 3 mesi il saldo del conto non è cresciuto.'
          : 'Negli ultimi 3 mesi il saldo del conto non è cresciuto: per '
                'arrivare al ${formatDate(deadline!)} servono '
                '${formatMoney(needed)} al mese.',
      hidden: 'Negli ultimi 3 mesi il saldo del conto non è cresciuto.',
    ),
    GoalStatus.unknown => (
      icon: Icons.info_outline_rounded,
      color: muted,
      visible: needed == null
          ? 'Mancano ${formatMoney(g.remainingCents)}. Dopo qualche settimana '
                'di movimenti vedrai a che ritmo stai risparmiando.'
          : 'Per arrivare al ${formatDate(deadline!)} servono '
                '${formatMoney(needed)} al mese.',
      hidden: needed == null
          ? 'Dopo qualche settimana di movimenti vedrai a che ritmo stai '
                'risparmiando.'
          : 'Scadenza: ${formatDate(deadline!)}.',
    ),
  };
}

/// Riga di un obiettivo: nome, conto, quanto manca e barra di avanzamento.
class GoalProgressTile extends StatelessWidget {
  const GoalProgressTile({super.key, required this.summary, this.onTap});

  final GoalSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final reached = summary.isReached;
    final color = reached ? AppColors.income : Color(summary.account.color);
    final status = goalStatusShort(summary, context);

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
                  CategoryAvatar.account(summary.account, size: 44),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.goal.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SensitiveText(
                          visibleText:
                              '${summary.account.name} · '
                              '${formatMoney(summary.balanceCents)} su '
                              '${formatMoney(summary.targetCents)}',
                          hiddenText:
                              '${summary.account.name} · $kHiddenAmount',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (reached)
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DebtProgressBar(progress: summary.progress, color: color),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(status.icon, size: 16, color: status.color),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            status.visible,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: status.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalList extends StatelessWidget {
  const _GoalList({required this.goals});

  final List<GoalSummary> goals;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (i, g) in goals.indexed) ...[
        if (i > 0) const Divider(indent: 62),
        GoalProgressTile(summary: g, onTap: () => openGoalDetail(context, g.id)),
      ],
    ],
  );
}

/// Sezione "Obiettivi di risparmio" della scheda Conti.
class SavingsGoalsSection extends ConsumerWidget {
  const SavingsGoalsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final goals = ref.watch(savingsGoalsProvider).asData?.value ?? const [];
    final reached = goals.where((g) => g.isReached).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Obiettivi di risparmio',
          subtitle: goals.isEmpty
              ? 'Un traguardo per il saldo di un conto'
              : reached == goals.length
              ? 'Tutti raggiunti'
              : '${goals.length - reached} da raggiungere'
                    '${reached > 0 ? ', ${plural(reached, 'raggiunto', 'raggiunti')}' : ''}',
          trailing: TextButton.icon(
            // Senza conti liberi l'editor propone di crearne uno.
            onPressed: () => showGoalEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nuovo obiettivo'),
          ),
        ),
        const SizedBox(height: 12),
        if (goals.isEmpty)
          AppCard(
            onTap: () => showGoalEditor(context),
            child: Row(
              children: [
                const CategoryAvatar.icon(
                  icon: Icons.savings_rounded,
                  color: AppColors.income,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Dai un obiettivo a un conto (es. 5.000 € su "Risparmi" '
                    'entro fine anno): vedrai quanto manca, quanto mettere da '
                    'parte ogni mese e se sei in linea.',
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
            child: _GoalList(goals: goals),
          ),
      ],
    );
  }
}

/// Card della dashboard con gli obiettivi di risparmio.
class GoalsOverviewCard extends StatelessWidget {
  const GoalsOverviewCard({super.key, required this.goals});

  final List<GoalSummary> goals;

  @override
  Widget build(BuildContext context) {
    final open = goals.where((g) => !g.isReached).length;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Obiettivi di risparmio',
            subtitle: open == 0
                ? 'Tutti raggiunti'
                : open == 1
                ? '1 da raggiungere'
                : '$open da raggiungere',
            trailing: const PrivacyToggleButton(size: 20),
          ),
          const SizedBox(height: 4),
          _GoalList(goals: goals),
        ],
      ),
    );
  }
}
