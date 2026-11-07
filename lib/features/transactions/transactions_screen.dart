import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/transaction_tile.dart';
import 'transaction_form_screen.dart';

enum _TypeFilter { all, expense, income, transfer }

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _search = TextEditingController();
  String _query = '';
  _TypeFilter _filter = _TypeFilter.all;

  /// Voci appena eliminate con lo swipe, nascoste finché il DB non emette la
  /// lista aggiornata (o finché l'utente non annulla).
  final _hidden = <Movement>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool _matches(Movement m, int? accountId) {
    if (_hidden.any((h) => _sameMovement(h, m))) return false;
    final q = _query.trim().toLowerCase();
    switch (m) {
      case TransactionWithCategory t:
        if (_filter == _TypeFilter.transfer) return false;
        if (_filter == _TypeFilter.expense && t.isIncome) return false;
        if (_filter == _TypeFilter.income && !t.isIncome) return false;
        if (accountId != null && !t.involves(accountId)) return false;
        return q.isEmpty ||
            t.tx.note.toLowerCase().contains(q) ||
            t.category.name.toLowerCase().contains(q) ||
            t.accountLabel.toLowerCase().contains(q) ||
            (t.debt?.name.toLowerCase().contains(q) ?? false);
      case TransferWithAccounts t:
        if (_filter == _TypeFilter.expense || _filter == _TypeFilter.income) {
          return false;
        }
        if (accountId != null && !t.involves(accountId)) return false;
        return q.isEmpty ||
            'trasferimento'.contains(q) ||
            t.transfer.note.toLowerCase().contains(q) ||
            t.from.name.toLowerCase().contains(q) ||
            t.to.name.toLowerCase().contains(q);
    }
  }

  static bool _sameMovement(Movement a, Movement b) => switch ((a, b)) {
        (TransactionWithCategory x, TransactionWithCategory y) =>
          x.tx.id == y.tx.id,
        (TransferWithAccounts x, TransferWithAccounts y) =>
          x.transfer.id == y.transfer.id,
        _ => false,
      };

  Future<void> _deleteWithUndo(Movement m) async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _hidden.add(m));
    final String label;
    switch (m) {
      case TransactionWithCategory t:
        await db.deleteTransaction(t.tx.id);
        label = t.title;
      case TransferWithAccounts t:
        await db.deleteTransfer(t.transfer.id);
        label = t.title;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('"$label" eliminato'),
          action: SnackBarAction(
            label: 'Annulla',
            onPressed: () async {
              switch (m) {
                case TransactionWithCategory t:
                  await db.restoreTransaction(t.tx);
                case TransferWithAccounts t:
                  await db.restoreTransfer(t.transfer);
              }
              if (mounted) setState(() => _hidden.remove(m));
            },
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    final monthNotifier = ref.read(selectedMonthProvider.notifier);
    final async = ref.watch(monthMovementsProvider);
    final accounts = ref.watch(accountsProvider).asData?.value ?? const [];
    final accountId = ref.watch(accountFilterProvider);
    final filteredAccount =
        accounts.where((a) => a.id == accountId).firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Movimenti')),
      body: Column(
        children: [
          PageContainer(
            maxWidth: 900,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PeriodNavigator(
                      label: formatMonthYear(month),
                      onPrevious: monthNotifier.previous,
                      onNext: monthNotifier.next,
                      onTapLabel: monthNotifier.reset,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: 'Cerca per descrizione, categoria, conto o debito',
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
                  _ChipRow(
                    children: [
                      for (final (label, f) in [
                        ('Tutti', _TypeFilter.all),
                        ('Uscite', _TypeFilter.expense),
                        ('Entrate', _TypeFilter.income),
                        ('Trasferimenti', _TypeFilter.transfer),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                    ],
                  ),
                  if (accounts.length > 1) ...[
                    const SizedBox(height: 8),
                    _ChipRow(
                      children: [
                        ChoiceChip(
                          avatar: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                          label: const Text('Tutti i conti'),
                          selected: accountId == null,
                          onSelected: (_) =>
                              ref.read(accountFilterProvider.notifier).set(null),
                        ),
                        for (final a in accounts)
                          ChoiceChip(
                            avatar: CategoryAvatar.account(a, size: 22),
                            label: Text(a.name),
                            selected: accountId == a.id,
                            onSelected: (_) =>
                                ref.read(accountFilterProvider.notifier).set(a.id),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: async.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(error: e),
              data: (items) => _MovementList(
                items: items.where((m) => _matches(m, accountId)).toList(),
                isFiltered: _query.isNotEmpty || _filter != _TypeFilter.all,
                account: filteredAccount,
                showAccount: accounts.length > 1 && accountId == null,
                onTap: (m) => openMovementForm(context, m),
                onDelete: _deleteWithUndo,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => children[i],
        ),
      );
}

class _MovementList extends StatelessWidget {
  const _MovementList({
    required this.items,
    required this.isFiltered,
    required this.account,
    required this.showAccount,
    required this.onTap,
    required this.onDelete,
  });

  final List<Movement> items;
  final bool isFiltered;
  final AccountEntity? account;
  final bool showAccount;
  final ValueChanged<Movement> onTap;
  final ValueChanged<Movement> onDelete;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      final filtered = isFiltered || account != null;
      return Center(
        child: EmptyState(
          icon: filtered ? Icons.search_off_rounded : Icons.receipt_long_rounded,
          title: filtered ? 'Nessun risultato' : 'Nessun movimento',
          message: filtered
              ? 'Prova a cambiare i filtri, il conto o il testo di ricerca.'
              : 'Non ci sono movimenti in questo mese. Tocca + per aggiungerne uno.',
        ),
      );
    }

    final groups = <DateTime, List<Movement>>{};
    for (final m in items) {
      final d = DateTime(m.date.year, m.date.month, m.date.day);
      groups.putIfAbsent(d, () => []).add(m);
    }
    final days = groups.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
      itemCount: days.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return PageContainer(
            maxWidth: 900,
            child: _SummaryStrip(
              items: items,
              account: account,
              isFiltered: isFiltered,
            ),
          );
        }
        final day = days[index - 1];
        return PageContainer(
          maxWidth: 900,
          child: _DayGroup(
            day: day,
            items: groups[day]!,
            accountId: account?.id,
            showAccount: showAccount,
            onTap: onTap,
            onDelete: onDelete,
          ),
        );
      },
    );
  }
}

/// Netto di una voce: per i trasferimenti conta solo se la lista è filtrata
/// su uno dei due conti; per le spese pagate in parte con i buoni, con il
/// filtro su un conto conta solo la parte di quel conto.
int _netOf(Movement m, int? accountId) => switch (m) {
      TransactionWithCategory t => t.signedCentsFor(accountId),
      TransferWithAccounts t => t.signedCentsFor(accountId),
    };

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.items,
    required this.account,
    required this.isFiltered,
  });

  final List<Movement> items;
  final AccountEntity? account;
  final bool isFiltered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final txs = items.whereType<TransactionWithCategory>();
    final income = txs
        .where((t) => t.isIncome)
        .fold<int>(0, (s, t) => s + t.centsFor(account?.id));
    final expense = txs
        .where((t) => !t.isIncome)
        .fold<int>(0, (s, t) => s + t.centsFor(account?.id));
    final transfersNet = items
        .whereType<TransferWithAccounts>()
        .fold<int>(0, (s, t) => s + t.signedCentsFor(account?.id));
    final hasTransfers = account != null && items.any((m) => m is TransferWithAccounts);

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

    final caption = [
      if (account != null) 'Conto: ${account!.name}',
      if (isFiltered) plural(items.length, 'voce filtrata', 'voci filtrate'),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            if (caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  caption,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Row(
              children: [
                cell('Entrate', formatMoney(income), AppColors.income),
                cell('Uscite', formatMoney(expense), AppColors.expense),
                if (hasTransfers)
                  cell(
                    'Trasferimenti',
                    formatSignedMoney(transfersNet, isIncome: transfersNet >= 0),
                    AppColors.transfer,
                  ),
                cell(
                  account == null ? 'Saldo' : 'Variazione',
                  formatMoney(income - expense + transfersNet),
                  null,
                ),
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
    required this.accountId,
    required this.showAccount,
    required this.onTap,
    required this.onDelete,
  });

  final DateTime day;
  final List<Movement> items;
  final int? accountId;
  final bool showAccount;
  final ValueChanged<Movement> onTap;
  final ValueChanged<Movement> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = items.fold<int>(0, (sum, m) => sum + _netOf(m, accountId));
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
                if (net != 0)
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
                for (final (i, m) in items.indexed) ...[
                  if (i > 0) const Divider(indent: 64),
                  Dismissible(
                    key: ValueKey(switch (m) {
                      TransactionWithCategory t => 'tx-${t.tx.id}',
                      TransferWithAccounts t => 'tr-${t.transfer.id}',
                    }),
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
                    onDismissed: (_) => onDelete(m),
                    child: MovementTile(
                      movement: m,
                      showDate: false,
                      showAccount: showAccount,
                      accountFilter: accountId,
                      onTap: () => onTap(m),
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
