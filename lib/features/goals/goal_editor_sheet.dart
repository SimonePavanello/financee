import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../domain/savings_goals.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy.dart';
import '../accounts/account_editor_sheet.dart';
import '../transactions/transaction_form_screen.dart';

/// Apre l'editor di un obiettivo di risparmio. Con [accountId] il conto è
/// già scelto. Restituisce l'id dell'obiettivo salvato.
Future<int?> showGoalEditor(
  BuildContext context, {
  SavingsGoalEntity? existing,
  int? accountId,
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => GoalEditorSheet(existing: existing, accountId: accountId),
    );

/// Conti su cui si può creare un obiettivo: i conti normali senza un
/// obiettivo (più quello dell'obiettivo che si sta modificando).
List<AccountEntity> goalEligibleAccounts(
  List<AccountEntity> accounts,
  Iterable<int> accountsWithGoal, {
  int? keep,
}) {
  final taken = accountsWithGoal.toSet()..remove(keep);
  return [
    for (final a in accounts)
      if (a.kind == AccountKind.standard && !taken.contains(a.id)) a,
  ];
}

class GoalEditorSheet extends ConsumerStatefulWidget {
  const GoalEditorSheet({super.key, this.existing, this.accountId});

  final SavingsGoalEntity? existing;
  final int? accountId;

  @override
  ConsumerState<GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends ConsumerState<GoalEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  int? _accountId;
  DateTime? _deadline;
  String? _nameError;
  String? _targetError;
  bool _accountError = false;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _target = TextEditingController(
      text: e == null ? '' : centsToInput(e.targetCents),
    );
    _accountId = e?.accountId ?? widget.accountId;
    _deadline = e?.deadline;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _deadline ?? DateTime(now.year + 1, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: _deadline != null && _deadline!.isBefore(today)
          ? _deadline!
          : today,
      lastDate: DateTime(now.year + 50),
      helpText: 'Entro quando vuoi raggiungerlo?',
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _newAccount() async {
    final id = await showAccountEditor(context);
    if (id != null && mounted) {
      setState(() {
        _accountId = id;
        _accountError = false;
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final cents = parseAmountToCents(_target.text);
    setState(() {
      _nameError = name.isEmpty ? 'Dai un nome all\'obiettivo' : null;
      _targetError = cents == null || cents <= 0
          ? 'Inserisci un importo maggiore di zero'
          : null;
      _accountError = _accountId == null;
    });
    if (_nameError != null || _targetError != null || _accountError) return;

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    final int id;
    if (_isNew) {
      id = await db.createSavingsGoal(
        accountId: _accountId!,
        name: name,
        targetCents: cents!,
        deadline: _deadline,
      );
    } else {
      id = widget.existing!.id;
      await db.updateSavingsGoal(
        widget.existing!.copyWith(
          accountId: _accountId,
          name: name,
          targetCents: cents,
          deadline: Value(_deadline),
        ),
      );
    }
    navigator.pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final allAccounts = ref.watch(accountsProvider).asData?.value ?? const [];
    final balances =
        ref.watch(accountBalancesProvider).asData?.value ?? const {};
    final goals = ref.watch(savingsGoalsProvider).asData?.value ?? const [];
    final accounts = goalEligibleAccounts(
      allAccounts,
      goals.map((g) => g.accountId),
      keep: widget.existing?.accountId ?? _accountId,
    );
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    final color = account == null ? scheme.primary : Color(account.color);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isNew ? 'Nuovo obiettivo di risparmio' : 'Modifica obiettivo',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Scegli il conto su cui metti da parte i soldi: il suo saldo è '
              'quanto hai già risparmiato.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            SectionLabel(
              'Conto',
              error: _accountError ? 'Scegli un conto' : null,
            ),
            if (accounts.isEmpty)
              AppCard(
                color: color.withValues(alpha: 0.06),
                child: EmptyState(
                  icon: Icons.savings_rounded,
                  title: 'Tutti i conti hanno già un obiettivo',
                  message: 'Crea un conto dedicato, ad esempio "Risparmi" o '
                      '"Vacanze", e collega lì il nuovo obiettivo.',
                  actions: [
                    FilledButton.icon(
                      onPressed: _newAccount,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Crea un conto'),
                    ),
                  ],
                ),
              )
            else
              AccountPicker(
                accounts: accounts,
                balances: balances,
                selectedId: _accountId,
                onSelected: (id) => setState(() {
                  _accountId = id;
                  _accountError = false;
                }),
                onCreate: _newAccount,
              ),
            const SizedBox(height: 20),
            const SectionLabel('Nome'),
            TextField(
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Es. Fondo emergenza, Vacanze, Auto nuova',
                errorText: _nameError,
                counterText: '',
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 16),
            const SectionLabel('Saldo da raggiungere'),
            TextField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (oldValue, newValue) =>
                      RegExp(r'^\d{0,9}([.,]\d{0,2})?$').hasMatch(newValue.text)
                      ? newValue
                      : oldValue,
                ),
              ],
              decoration: InputDecoration(
                hintText: '0,00',
                prefixText: '€ ',
                errorText: _targetError,
              ),
              onChanged: (_) => setState(() => _targetError = null),
            ),
            const SizedBox(height: 20),
            const SectionLabel('Scadenza (facoltativa)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDeadline,
                  icon: const Icon(Icons.event_rounded),
                  label: Text(
                    _deadline == null
                        ? 'Scegli una data'
                        : 'Entro il ${formatDate(_deadline!)}',
                  ),
                ),
                if (_deadline != null)
                  TextButton.icon(
                    onPressed: () => setState(() => _deadline = null),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Nessuna scadenza'),
                  ),
              ],
            ),
            if (account != null)
              _Preview(
                account: account,
                balanceCents: balances[account.id] ?? account.initialBalanceCents,
                targetCents: parseAmountToCents(_target.text),
                deadline: _deadline,
              ),
            const SizedBox(height: 28),
            GradientButton(
              label: _isNew ? 'Crea obiettivo' : 'Salva modifiche',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Anteprima: quanto c'è già sul conto e quanto manca.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.account,
    required this.balanceCents,
    required this.targetCents,
    required this.deadline,
  });

  final AccountEntity account;
  final int balanceCents;
  final int? targetCents;
  final DateTime? deadline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = targetCents;
    final String visible;
    final String hidden;
    if (target == null || target <= 0) {
      visible = 'Su "${account.name}" ci sono già ${formatMoney(balanceCents)}.';
      hidden = 'Il saldo di "${account.name}" conta già per l\'obiettivo.';
    } else if (balanceCents >= target) {
      visible = 'Con ${formatMoney(balanceCents)} su "${account.name}" '
          'l\'obiettivo è già raggiunto.';
      hidden = 'Con il saldo attuale l\'obiettivo è già raggiunto.';
    } else {
      final remaining = target - balanceCents;
      var perMonth = '';
      if (deadline case final d?) {
        final months = monthsUntil(DateTime.now(), d);
        if (months > 0) {
          perMonth = ': circa ${formatMoney((remaining / months).ceil())} '
              'al mese fino al ${formatDate(d)}';
        }
      }
      visible = 'Hai già ${formatMoney(balanceCents)}, '
          'mancano ${formatMoney(remaining)}$perMonth.';
      hidden = 'Il saldo attuale del conto conta già per l\'obiettivo.';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Color(account.color).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            CategoryAvatar.account(account, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: SensitiveText(
                visibleText: visible,
                hiddenText: hidden,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (target != null && target > 0 && balanceCents >= target)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.verified_rounded, color: AppColors.income),
              ),
          ],
        ),
      ),
    );
  }
}
