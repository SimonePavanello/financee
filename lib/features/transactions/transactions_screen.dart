import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../data/models.dart';
import '../../domain/analytics.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import 'transaction_form_screen.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  String _query = '';
  TxType? _filter;

  /// Movimenti appena eliminati con lo swipe, nascosti finché il DB non
  /// emette la lista aggiornata (o finché l'utente non annulla).
  final _hidden = <int>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<TransactionWithCategory> _apply(List<TransactionWithCategory> items) {
    final q = _query.trim().toLowerCase();
    return items.where((i) {
      if (_hidden.contains(i.tx.id)) return false;
      if (_filter != null && i.tx.type != _filter) return false;
      if (q.isEmpty) return true;
      return i.tx.note.toLowerCase().contains(q) ||
          i.category.name.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _deleteWithUndo(TransactionWithCategory item) async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _hidden.add(item.tx.id));
    await db.deleteTransaction(item.tx.id);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('"${item.title}" eliminato'),
          action: SnackBarAction(
            label: 'Annulla',
            onPressed: () async {
              await db.restoreTransaction(item.tx);
              if (mounted) setState(() => _hidden.remove(item.tx.id));
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    final monthNotifier = ref.read(selectedMonthProvider.notifier);
    final async = ref.watch(monthTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Movimenti')),
      body: Column(
        children: [
          PageContainer(
            maxWidth: 900,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      PeriodNavigator(
                        label: formatMonthYear(month),
                        onPrevious: monthNotifier.previous,
                        onNext: monthNotifier.next,
                        onTapLabel: monthNotifier.reset,
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Cerca per descrizione o categoria',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Cancella ricerca',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final (label, type) in [
                          ('Tutti', null),
                          ('Uscite', TxType.expense),
                          ('Entrate', TxType.income),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label),
                              selected: _filter == type,
                              onSelected: (_) => setState(() => _filter = type),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(error: e),
              data: (items) {
                final filtered = _apply(items);
                return _TransactionList(
                  items: filtered,
                  isFiltered: _query.isNotEmpty || _filter != null,
                  onTap: (i) => openTransactionForm(context, existing: i),
                  onDelete: _deleteWithUndo,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionList extends StatelessWidget {
  const _TransactionList({
    required this.items,
    required this.isFiltered,
    required this.onTap,
    required this.onDelete,
  });

  final List<TransactionWithCategory> items;
  final bool isFiltered;
  final ValueChanged<TransactionWithCategory> onTap;
  final ValueChanged<TransactionWithCategory> onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: EmptyState(
          icon: isFiltered ? Icons.search_off_rounded : Icons.receipt_long_rounded,
          title: isFiltered ? 'Nessun risultato' : 'Nessun movimento',
          message: isFiltered
              ? 'Prova a cambiare i filtri o il testo di ricerca.'
              : 'Non ci sono movimenti in questo mese. Tocca + per aggiungerne uno.',
        ),
      );
    }

    final summary = PeriodSummary.from(items);
    final groups = <DateTime, List<TransactionWithCategory>>{};
    for (final i in items) {
      final d = DateTime(i.tx.date.year, i.tx.date.month, i.tx.date.day);
      groups.putIfAbsent(d, () => []).add(i);
    }
    final days = groups.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      itemCount: days.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return PageContainer(
            maxWidth: 900,
            child: _SummaryStrip(summary: summary, isFiltered: isFiltered),
          );
        }
        final day = days[index - 1];
        final dayItems = groups[day]!;
        return PageContainer(
          maxWidth: 900,
          child: _DayGroup(
            day: day,
            items: dayItems,
            onTap: onTap,
            onDelete: onDelete,
          ),
        );
      },
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary, required this.isFiltered});

  final PeriodSummary summary;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget cell(String label, String value, Color? color) => Expanded(
          child: Column(
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            if (isFiltered)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  summary.count == 1
                      ? 'Totale dell\'unico movimento filtrato'
                      : 'Totali dei ${summary.count} movimenti filtrati',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Row(
              children: [
                cell('Entrate', formatMoney(summary.incomeCents), AppColors.income),
                cell('Uscite', formatMoney(summary.expenseCents), AppColors.expense),
                cell('Saldo', formatMoney(summary.balanceCents), null),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayGroup extends StatelessWidget {
  const _DayGroup({
    required this.day,
    required this.items,
    required this.onTap,
    required this.onDelete,
  });

  final DateTime day;
  final List<TransactionWithCategory> items;
  final ValueChanged<TransactionWithCategory> onTap;
  final ValueChanged<TransactionWithCategory> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = items.fold<int>(0, (sum, i) => sum + i.signedCents);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    formatDayHeader(day),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Text(
                  formatSignedMoney(net, isIncome: net >= 0),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              children: [
                for (final (i, item) in items.indexed) ...[
                  if (i > 0) const Divider(indent: 64),
                  Dismissible(
                    key: ValueKey(item.tx.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(
                        color: AppColors.expense.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.expense,
                      ),
                    ),
                    onDismissed: (_) => onDelete(item),
                    child: TransactionTile(
                      item: item,
                      showDate: false,
                      onTap: () => onTap(item),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
