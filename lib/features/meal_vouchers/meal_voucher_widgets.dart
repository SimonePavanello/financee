import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../data/default_categories.dart';
import '../../domain/analytics.dart';
import '../../domain/meal_vouchers.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy.dart';

// -----------------------------------------------------------------------------
// Impostazioni
// -----------------------------------------------------------------------------

/// Card "Buoni pasto" delle impostazioni: valore di un buono, conto dei buoni
/// e caricamento dei buoni ricevuti.
class MealVoucherSettingsCard extends ConsumerWidget {
  const MealVoucherSettingsCard({super.key});

  Future<void> _editValue(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final cents = await showDialog<int>(
      context: context,
      builder: (_) => _VoucherValueDialog(initialCents: current),
    );
    if (cents != null) ref.read(mealVoucherValueProvider.notifier).set(cents);
  }

  Future<void> _activate(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(databaseProvider).enableMealVouchers();
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Conto "Buoni pasto" pronto: aggiungi i buoni che hai e usali nelle spese',
        ),
        action: SnackBarAction(
          label: 'Aggiungi buoni',
          onPressed: () {
            if (context.mounted) showAddVouchersSheet(context);
          },
        ),
      ),
    );
  }

  Future<void> _pickAccount(
    BuildContext context,
    WidgetRef ref,
    AccountEntity current,
  ) async {
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    final accounts = await db.getAccounts();
    if (!context.mounted) return;
    // -1 = nessun conto (buoni disattivati).
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Conto dei buoni pasto'),
        children: [
          for (final a in accounts)
            ListTile(
              leading: CategoryAvatar.account(a, size: 36),
              title: Text(a.name),
              trailing: a.id == current.id
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(context, a.id),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.block_rounded),
            title: const Text('Nessuno: disattiva i buoni'),
            subtitle: const Text('Il conto e i suoi movimenti restano'),
            onTap: () => Navigator.pop(context, -1),
          ),
        ],
      ),
    );
    if (picked == null || picked == current.id) return;
    await db.setMealVoucherAccount(picked == -1 ? null : picked);
    if (picked == -1) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Buoni pasto disattivati. "${current.name}" resta tra i tuoi conti.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final value = ref.watch(mealVoucherValueProvider);
    final account = ref.watch(mealVoucherAccountProvider);
    final balance = account == null
        ? 0
        : ref.watch(accountBalancesProvider).asData?.value[account.id] ??
              account.initialBalanceCents;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SectionHeader(
              title: 'Buoni pasto',
              subtitle: account == null
                  ? 'Gestiscili come un conto e usali per pagare una parte delle spese'
                  : 'Nelle spese puoi pagare una parte con i buoni',
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.confirmation_number_rounded),
            title: const Text('Valore di un buono'),
            subtitle: const Text('Serve a contare i buoni nelle spese'),
            trailing: Text(
              formatMoney(value),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            onTap: () => _editValue(context, ref, value),
          ),
          if (account == null)
            ListTile(
              leading: const Icon(Icons.add_card_rounded),
              title: const Text('Attiva i buoni pasto'),
              subtitle: const Text(
                'Crea il conto "Buoni pasto" su cui caricare i buoni ricevuti',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _activate(context, ref),
            )
          else ...[
            ListTile(
              leading: CategoryAvatar.account(account, size: 36),
              title: Text('Conto dei buoni: ${account.name}'),
              subtitle: SensitiveText(
                visibleText:
                    '${formatVoucherCount(balance, value)} · ${formatMoney(balance)}',
                hiddenText: 'Saldo $kHiddenAmount',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickAccount(context, ref, account),
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline_rounded),
              title: const Text('Aggiungi buoni ricevuti'),
              subtitle: const Text(
                'Es. i buoni del mese: entrano nel conto come entrata',
              ),
              onTap: () => showAddVouchersSheet(context),
            ),
          ],
        ],
      ),
    );
  }
}

class _VoucherValueDialog extends StatefulWidget {
  const _VoucherValueDialog({required this.initialCents});

  final int initialCents;

  @override
  State<_VoucherValueDialog> createState() => _VoucherValueDialogState();
}

class _VoucherValueDialogState extends State<_VoucherValueDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: centsToInput(widget.initialCents),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final cents = parseAmountToCents(_controller.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = 'Inserisci un valore maggiore di zero');
      return;
    }
    Navigator.pop(context, cents);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Valore di un buono'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_amountFormatter],
      decoration: InputDecoration(
        prefixText: '€ ',
        hintText: '8,00',
        errorText: _error,
        helperText: 'Quanto vale un singolo buono pasto',
      ),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annulla'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Salva')),
    ],
  );
}

final _amountFormatter = TextInputFormatter.withFunction(
  (oldValue, newValue) =>
      RegExp(r'^\d{0,6}([.,]\d{0,2})?$').hasMatch(newValue.text)
      ? newValue
      : oldValue,
);

// -----------------------------------------------------------------------------
// Buoni ricevuti
// -----------------------------------------------------------------------------

/// Registra i buoni ricevuti (es. quelli del mese) come entrata sul conto dei
/// buoni pasto.
Future<void> showAddVouchersSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => const _AddVouchersSheet(),
    );

class _AddVouchersSheet extends ConsumerStatefulWidget {
  const _AddVouchersSheet();

  @override
  ConsumerState<_AddVouchersSheet> createState() => _AddVouchersSheetState();
}

class _AddVouchersSheetState extends ConsumerState<_AddVouchersSheet> {
  static const _lastCountKey = 'meal_voucher_last_load';

  late int _count;
  late DateTime _date;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _count = ref.read(sharedPreferencesProvider).getInt(_lastCountKey) ?? 20;
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Data in cui hai ricevuto i buoni',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(AccountEntity account, int value) async {
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final categoryId = await db.ensureMealVoucherCategory();
    await db.addTransaction(
      type: TxType.income,
      amountCents: _count * value,
      categoryId: categoryId,
      accountId: account.id,
      date: _date,
      note: _note.text.trim(),
    );
    await ref.read(sharedPreferencesProvider).setInt(_lastCountKey, _count);
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Aggiunti ${plural(_count, 'buono', 'buoni')} '
          '(${formatMoney(_count * value)}) a "${account.name}"',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final account = ref.watch(mealVoucherAccountProvider);
    final value = ref.watch(mealVoucherValueProvider);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Buoni ricevuti',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              account == null
                  ? 'Attiva prima i buoni pasto nelle impostazioni.'
                  : 'Entrano nel conto "${account.name}" come entrata della '
                        'categoria Buoni pasto.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (account != null) ...[
              const SizedBox(height: 20),
              AppCard(
                color: Color(account.color).withValues(alpha: 0.06),
                child: VoucherCounter(
                  title: plural(_count, 'buono', 'buoni'),
                  subtitle:
                      '${formatMoney(_count * value)} · ${formatMoney(value)} l\'uno',
                  onRemove: _count > 1 ? () => setState(() => _count--) : null,
                  onAdd: _count < 999 ? () => setState(() => _count++) : null,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Oggi'),
                    selected: _date == todayDate,
                    onSelected: (_) => setState(() => _date = todayDate),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: Text(
                      _date == todayDate
                          ? 'Altra data'
                          : '${formatWeekday(_date)} ${formatDate(_date)}',
                    ),
                    onPressed: _pickDate,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Es. Buoni di ${formatMonthName(_date)}',
                  prefixIcon: const Icon(Icons.notes_rounded),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 20),
              GradientButton(
                label: 'Aggiungi ${plural(_count, 'buono', 'buoni')}',
                icon: Icons.add_rounded,
                loading: _saving,
                onPressed: () => _save(account, value),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Componenti
// -----------------------------------------------------------------------------

/// Contatore "− 17 buoni +".
class VoucherCounter extends StatelessWidget {
  const VoucherCounter({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onRemove,
    required this.onAdd,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onRemove;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton.filledTonal(
          tooltip: 'Un buono in meno',
          onPressed: onRemove,
          icon: const Icon(Icons.remove_rounded),
        ),
        Expanded(
          child: Column(
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Un buono in più',
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// Sezione del form di una spesa: quanta parte pagare con i buoni pasto e
/// come si divide l'importo tra i due conti.
class VoucherPaymentSection extends StatelessWidget {
  const VoucherPaymentSection({
    super.key,
    required this.voucherAccount,
    required this.otherAccount,
    required this.valueCents,
    required this.availableCents,
    required this.amountCents,
    required this.enabled,
    required this.voucherCents,
    required this.onEnabledChanged,
    required this.onVoucherCentsChanged,
    this.error,
  });

  final AccountEntity voucherAccount;

  /// Conto scelto per il resto della spesa (nullo se non ancora scelto).
  final AccountEntity? otherAccount;
  final int valueCents;

  /// Saldo disponibile sul conto dei buoni.
  final int availableCents;

  /// Importo totale della spesa (nullo se non ancora inserito).
  final int? amountCents;
  final bool enabled;
  final int voucherCents;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<int> onVoucherCentsChanged;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(voucherAccount.color);
    final amount = amountCents;
    final maxCents = amount == null || amount <= 0
        ? null
        : suggestedVoucherCents(
            amountCents: amount,
            valueCents: valueCents,
            availableCents: availableCents,
          );

    return AppCard(
      padding: EdgeInsets.fromLTRB(16, 12, 12, enabled ? 16 : 12),
      color: enabled ? color.withValues(alpha: 0.06) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CategoryAvatar.account(voucherAccount, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paga in parte con i buoni',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SensitiveText(
                      visibleText:
                          'Disponibili: '
                          '${formatVoucherCount(availableCents, valueCents)}',
                      hiddenText: 'Disponibili: $kHiddenAmount',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: enabled, onChanged: onEnabledChanged),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !enabled
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 14),
                      VoucherCounter(
                        title: formatVoucherCount(voucherCents, valueCents),
                        subtitle:
                            '${formatMoney(voucherCents)} · '
                            '${formatMoney(valueCents)} l\'uno',
                        onRemove: voucherCents > 0
                            ? () => onVoucherCentsChanged(
                                removeVoucher(voucherCents, valueCents),
                              )
                            : null,
                        onAdd: () => onVoucherCentsChanged(
                          addVoucher(voucherCents, valueCents),
                        ),
                      ),
                      if (maxCents != null &&
                          maxCents <= amount! &&
                          maxCents != voucherCents)
                        Center(
                          child: TextButton.icon(
                            onPressed: () => onVoucherCentsChanged(maxCents),
                            icon: const Icon(
                              Icons.auto_fix_high_rounded,
                              size: 18,
                            ),
                            label: Text(
                              'Usa il massimo: '
                              '${formatVoucherCount(maxCents, valueCents)}',
                            ),
                          ),
                        ),
                      const Divider(height: 24),
                      _ShareRow(
                        leading: CategoryAvatar.account(
                          voucherAccount,
                          size: 28,
                        ),
                        label: voucherAccount.name,
                        value: formatMoney(voucherCents),
                      ),
                      const SizedBox(height: 8),
                      _ShareRow(
                        leading: otherAccount == null
                            ? CategoryAvatar.icon(
                                icon: Icons.account_balance_wallet_outlined,
                                color: scheme.outline,
                                size: 28,
                              )
                            : CategoryAvatar.account(otherAccount!, size: 28),
                        label: otherAccount?.name ?? 'Conto scelto sopra',
                        value: amount == null
                            ? '—'
                            : formatMoney(math.max(0, amount - voucherCents)),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            error!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.expense,
                            ),
                          ),
                        )
                      else if (amount != null && voucherCents == amount)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Tutta la spesa è pagata con i buoni: verrà '
                            'registrata sul conto "${voucherAccount.name}".',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else if (voucherCents > availableCents)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: SensitiveText(
                            visibleText:
                                'Sul conto ci sono solo '
                                '${formatVoucherCount(math.max(0, availableCents), valueCents)}: '
                                'il saldo dei buoni andrà sotto zero.',
                            hiddenText:
                                'Stai usando più buoni di quelli '
                                'disponibili: il saldo andrà sotto zero.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.warning,
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

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.leading,
    required this.label,
    required this.value,
  });

  final Widget leading;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        leading,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.expense,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Dashboard: quanto delle spese copri con i buoni
// -----------------------------------------------------------------------------

/// Card della dashboard: per ogni categoria pagata con i buoni nel mese,
/// "Hai speso 300,00 € di cui 140,00 € in buoni pasto"; toccando la riga si
/// vede la percentuale coperta dai buoni.
class MealVoucherCoverageCard extends ConsumerStatefulWidget {
  const MealVoucherCoverageCard({
    super.key,
    required this.summary,
    required this.month,
  });

  final PeriodSummary summary;
  final DateTime month;

  @override
  ConsumerState<MealVoucherCoverageCard> createState() =>
      _MealVoucherCoverageCardState();
}

class _MealVoucherCoverageCardState
    extends ConsumerState<MealVoucherCoverageCard> {
  /// Categorie di cui è aperta la percentuale.
  final _open = <int>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = ref.watch(mealVoucherValueProvider);
    final account = ref.watch(mealVoucherAccountProvider);
    final color = Color(account?.color ?? kMealVoucherAccount.color);
    final rows = widget.summary.voucherCategories;
    final total = widget.summary.voucherCents;
    final month = formatMonthName(widget.month);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Buoni pasto',
            subtitle: rows.isEmpty
                ? 'Quanto delle spese di $month copri con i buoni'
                : '${formatMoney(total)} in buoni a $month · tocca una '
                      'categoria per la percentuale',
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'A $month non hai pagato spese con i buoni pasto.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            for (final (i, c) in rows.indexed) ...[
              if (i > 0) const Divider(indent: 52),
              _CoverageRow(
                total: c,
                color: color,
                valueCents: value,
                open: _open.contains(c.category.id),
                onTap: () => setState(() {
                  if (!_open.remove(c.category.id)) _open.add(c.category.id);
                }),
              ),
            ],
        ],
      ),
    );
  }
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow({
    required this.total,
    required this.color,
    required this.valueCents,
    required this.open,
    required this.onTap,
  });

  final CategoryTotal total;
  final Color color;
  final int valueCents;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    const bold = TextStyle(fontWeight: FontWeight.w800);
    final share = total.voucherShare;

    // Ogni riga è un elemento a sé per i lettori di schermo.
    return Semantics(
      container: true,
      expanded: open,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CategoryAvatar.of(total.category, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          total.category.name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Hai speso '),
                              TextSpan(
                                text: formatMoney(total.totalCents),
                                style: bold,
                              ),
                              const TextSpan(text: ' di cui '),
                              TextSpan(
                                text: formatMoney(total.voucherCents),
                                style: bold.copyWith(color: color),
                              ),
                              const TextSpan(text: ' in buoni pasto'),
                            ],
                          ),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: !open
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(52, 14, 0, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  formatPercent(share),
                                  style: theme.textTheme.headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: color,
                                      ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'della spesa per ${total.category.name} '
                                    'coperto dai buoni',
                                    style: muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // La percentuale è già scritta sopra.
                            ExcludeSemantics(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: share),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, v, _) =>
                                      LinearProgressIndicator(
                                        value: v,
                                        minHeight: 10,
                                        color: color,
                                        backgroundColor:
                                            scheme.surfaceContainerHighest,
                                      ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 16,
                              runSpacing: 6,
                              children: [
                                _LegendDot(
                                  color: color,
                                  text:
                                      'Buoni ${formatMoney(total.voucherCents)} '
                                      '(${formatVoucherCount(total.voucherCents, valueCents)})',
                                ),
                                _LegendDot(
                                  color: scheme.outlineVariant,
                                  text:
                                      'Dai conti ${formatMoney(total.totalCents - total.voucherCents)}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
