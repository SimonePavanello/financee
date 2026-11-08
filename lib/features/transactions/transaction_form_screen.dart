import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../data/models.dart';
import '../../domain/debts.dart';
import '../../domain/meal_vouchers.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import '../../widgets/privacy.dart';
import '../accounts/account_editor_sheet.dart';
import '../categories/category_editor_sheet.dart';
import '../debts/debt_editor_sheet.dart';
import '../debts/debt_widgets.dart';
import '../meal_vouchers/meal_voucher_widgets.dart';

enum MovementKind { expense, income, transfer }

/// Apre il form per una nuova spesa/entrata (o per modificarne una).
/// Restituisce `true` se il movimento è stato salvato.
Future<bool?> openTransactionForm(
  BuildContext context, {
  TransactionWithCategory? existing,
  MovementKind initialKind = MovementKind.expense,
  int? accountId,
  int? debtId,
}) =>
    _open(
      context,
      MovementFormScreen(
        existingTransaction: existing,
        initialKind: initialKind,
        initialAccountId: accountId,
        initialDebtId: debtId,
      ),
    );

/// Apre il form per un nuovo trasferimento tra conti (o per modificarne uno).
Future<bool?> openTransferForm(
  BuildContext context, {
  TransferWithAccounts? existing,
  int? fromAccountId,
  int? toAccountId,
}) =>
    _open(
      context,
      MovementFormScreen(
        existingTransfer: existing,
        initialKind: MovementKind.transfer,
        initialAccountId: fromAccountId,
        initialToAccountId: toAccountId,
      ),
    );

/// Apre il form adatto alla voce della lista movimenti.
Future<bool?> openMovementForm(BuildContext context, Movement movement) =>
    switch (movement) {
      TransactionWithCategory t => openTransactionForm(context, existing: t),
      TransferWithAccounts t => openTransferForm(context, existing: t),
    };

Future<bool?> _open(BuildContext context, Widget screen) =>
    Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => screen),
    );

class MovementFormScreen extends ConsumerStatefulWidget {
  const MovementFormScreen({
    super.key,
    this.existingTransaction,
    this.existingTransfer,
    this.initialKind = MovementKind.expense,
    this.initialAccountId,
    this.initialToAccountId,
    this.initialDebtId,
  });

  final TransactionWithCategory? existingTransaction;
  final TransferWithAccounts? existingTransfer;
  final MovementKind initialKind;

  /// Conto preselezionato (es. aprendo il form da un conto filtrato).
  final int? initialAccountId;

  /// Conto di destinazione preselezionato per un trasferimento (es. dal
  /// dettaglio di un obiettivo di risparmio).
  final int? initialToAccountId;

  /// Debito preselezionato (aprendo il form dal dettaglio di un debito).
  final int? initialDebtId;

  @override
  ConsumerState<MovementFormScreen> createState() => _MovementFormScreenState();
}

class _MovementFormScreenState extends ConsumerState<MovementFormScreen> {
  late MovementKind _kind;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _date;
  int? _categoryId;
  int? _accountId;
  int? _fromId;
  int? _toId;
  String? _amountError;
  bool _categoryError = false;
  bool _accountError = false;
  String? _transferError;
  bool _saving = false;

  /// Parte della spesa pagata con i buoni pasto.
  bool _useVouchers = false;
  int _voucherCents = 0;
  String? _voucherError;

  /// Debito di cui la spesa è un pagamento.
  int? _debtId;

  TransactionWithCategory? get _tx => widget.existingTransaction;
  TransferWithAccounts? get _transfer => widget.existingTransfer;
  bool get _isNew => _tx == null && _transfer == null;
  bool get _isTransfer => _kind == MovementKind.transfer;
  TxType get _txType =>
      _kind == MovementKind.income ? TxType.income : TxType.expense;

  Color get _kindColor => switch (_kind) {
        MovementKind.expense => AppColors.expense,
        MovementKind.income => AppColors.income,
        MovementKind.transfer => AppColors.transfer,
      };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _kind = widget.initialKind;
    var amount = 0;
    var note = '';

    if (_tx case final tx?) {
      _kind = tx.isIncome ? MovementKind.income : MovementKind.expense;
      amount = tx.tx.amountCents;
      note = tx.tx.note;
      _date = tx.tx.date;
      _categoryId = tx.category.id;
      _accountId = tx.account.id;
      _useVouchers = tx.usesVouchers;
      _voucherCents = tx.voucherCents;
      _debtId = tx.tx.debtId;
    } else if (_transfer case final tr?) {
      _kind = MovementKind.transfer;
      amount = tr.amountCents;
      note = tr.transfer.note;
      _date = tr.transfer.date;
      _fromId = tr.from.id;
      _toId = tr.to.id;
    } else if (_isTransfer) {
      _fromId = widget.initialAccountId;
      _toId = widget.initialToAccountId;
    } else {
      _accountId = widget.initialAccountId;
      _debtId = widget.initialDebtId;
      // Pagamento di un debito a rate: l'importo proposto è la rata.
      final debt = (ref.read(debtsProvider).asData?.value ?? const [])
          .where((d) => d.id == _debtId)
          .firstOrNull;
      if (debt != null && debt.isInstallments) amount = debt.installmentCents;
    }

    _amount = TextEditingController(text: amount == 0 ? '' : centsToInput(amount));
    _note = TextEditingController(text: note);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setKind(MovementKind kind) {
    if (kind == _kind) return;
    setState(() {
      // Passando da spesa a entrata la categoria non è più valida.
      if (kind != MovementKind.transfer) _categoryId = null;
      _kind = kind;
      _transferError = null;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Data del movimento',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _newCategory() async {
    final id = await showCategoryEditor(context, initialType: _txType);
    if (id != null) {
      setState(() {
        _categoryId = id;
        _categoryError = false;
      });
    }
  }

  Future<int?> _newAccount() => showAccountEditor(context);

  /// Con un solo conto non c'è niente da chiedere: lo si usa direttamente.
  int? _effectiveAccountId(List<AccountEntity> accounts) =>
      _accountId ?? (accounts.length == 1 ? accounts.single.id : null);

  /// Conto dei buoni pasto da offrire nel form: quello già usato dalla spesa
  /// che si sta modificando, altrimenti quello attivato nelle impostazioni
  /// (`build` lo osserva, così il form si aggiorna se cambia).
  AccountEntity? get _voucherAccount =>
      _tx?.voucherAccount ?? ref.read(mealVoucherAccountProvider);

  /// La sezione buoni ha senso solo per una spesa pagata da un altro conto.
  bool _showVouchers(int? accountId) {
    final voucher = _voucherAccount;
    return _kind == MovementKind.expense &&
        voucher != null &&
        accountId != voucher.id;
  }

  void _setUseVouchers(bool value, int available) => setState(() {
        _useVouchers = value;
        _voucherError = null;
        if (value && _voucherCents == 0) {
          _voucherCents = suggestedVoucherCents(
            amountCents: parseAmountToCents(_amount.text) ?? 0,
            valueCents: ref.read(mealVoucherValueProvider),
            availableCents: available,
          );
        }
      });

  Future<void> _save(List<AccountEntity> accounts) async {
    final cents = parseAmountToCents(_amount.text);
    final amountInvalid = cents == null || cents <= 0;
    final accountId = _effectiveAccountId(accounts);
    final voucherAccount = _voucherAccount;
    final useVouchers =
        _showVouchers(accountId) && _useVouchers && _voucherCents > 0;
    final voucherError = useVouchers && cents != null && _voucherCents > cents
        ? 'I buoni (${formatMoney(_voucherCents)}) superano l\'importo della '
            'spesa: i buoni non danno resto, togline qualcuno.'
        : null;
    String? transferError;
    if (_isTransfer) {
      if (_fromId == null || _toId == null) {
        transferError = 'Scegli il conto di origine e quello di destinazione';
      } else if (_fromId == _toId) {
        transferError = 'I due conti devono essere diversi';
      }
    }
    setState(() {
      _amountError = amountInvalid ? 'Inserisci un importo maggiore di zero' : null;
      _categoryError = !_isTransfer && _categoryId == null;
      _accountError = !_isTransfer && accountId == null;
      _transferError = transferError;
      _voucherError = voucherError;
    });
    if (amountInvalid ||
        _categoryError ||
        _accountError ||
        _transferError != null ||
        _voucherError != null) {
      return;
    }
    final voucherAccountId = useVouchers ? voucherAccount!.id : null;
    final voucherCents = useVouchers ? _voucherCents : 0;
    // Solo una spesa può essere il pagamento di un debito.
    final debtId = _kind == MovementKind.expense ? _debtId : null;

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    final note = _note.text.trim();

    if (_isTransfer) {
      if (_transfer case final tr?) {
        await db.updateTransfer(
          tr.transfer.copyWith(
            fromAccountId: _fromId,
            toAccountId: _toId,
            amountCents: cents,
            date: _date,
            note: note,
          ),
        );
      } else {
        await db.addTransfer(
          fromAccountId: _fromId!,
          toAccountId: _toId!,
          amountCents: cents,
          date: _date,
          note: note,
        );
      }
    } else if (_tx case final tx?) {
      await db.updateTransaction(
        tx.tx.copyWith(
          type: _txType,
          amountCents: cents,
          categoryId: _categoryId,
          accountId: accountId,
          voucherAccountId: Value(voucherAccountId),
          voucherCents: voucherCents,
          debtId: Value(debtId),
          date: _date,
          note: note,
        ),
      );
    } else {
      await db.addTransaction(
        type: _txType,
        amountCents: cents,
        categoryId: _categoryId!,
        accountId: accountId!,
        voucherAccountId: voucherAccountId,
        voucherCents: voucherCents,
        debtId: debtId,
        date: _date,
        note: note,
      );
    }
    navigator.pop(true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isTransfer ? 'Eliminare il trasferimento?' : 'Eliminare il movimento?'),
        content: const Text('L\'operazione non può essere annullata.'),
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
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    final db = ref.read(databaseProvider);
    if (_transfer case final tr?) {
      await db.deleteTransfer(tr.transfer.id);
    } else if (_tx case final tx?) {
      await db.deleteTransaction(tx.tx.id);
    }
    navigator.pop(false);
  }

  /// "Dopo questo pagamento restano X" sotto il debito scelto.
  Widget? _debtHint(List<DebtSummary> debts) {
    final debt = debts.where((d) => d.id == _debtId).firstOrNull;
    final cents = parseAmountToCents(_amount.text);
    if (debt == null || cents == null || cents <= 0) return null;
    // Modificando un pagamento dello stesso debito, il suo importo è già
    // contato tra quelli restituiti.
    final tx = _tx;
    final already = tx != null && !tx.isIncome && tx.tx.debtId == debt.id
        ? tx.tx.amountCents
        : 0;
    final after = debt.afterPayment(cents, alreadyLinkedCents: already);
    final style = Theme.of(context).textTheme.bodySmall;
    final muted = style?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: after.isPaidOff
          ? Row(
              children: [
                const Icon(
                  Icons.celebration_rounded,
                  size: 18,
                  color: AppColors.income,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Con questo pagamento "${debt.debt.name}" è estinto',
                    style: style?.copyWith(
                      color: AppColors.income,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          : after.isInstallments
          ? SensitiveText(
              visibleText: 'Dopo questo pagamento: ${installmentsLabel(after)}, '
                  'restano ${formatMoney(after.remainingCents)}',
              hiddenText: 'Dopo questo pagamento: ${installmentsLabel(after)}',
              style: muted,
            )
          : SensitiveText(
              visibleText: 'Dopo questo pagamento restano '
                  '${formatMoney(after.remainingCents)} '
                  'su ${formatMoney(debt.amountCents)}',
              hiddenText: 'Dopo questo pagamento restano $kHiddenAmount',
              style: muted,
            ),
    );
  }

  /// Scegliendo un debito a rate con l'importo ancora vuoto, propone la rata.
  void _selectDebt(List<DebtSummary> debts, int? id) {
    _debtId = id;
    final debt = debts.where((d) => d.id == id).firstOrNull;
    if (debt != null &&
        debt.isInstallments &&
        (parseAmountToCents(_amount.text) ?? 0) == 0) {
      _amount.text = centsToInput(debt.installmentCents);
      _amountError = null;
    }
  }

  String get _title {
    if (_transfer != null) return 'Modifica trasferimento';
    if (_tx != null) return 'Modifica movimento';
    return _isTransfer ? 'Nuovo trasferimento' : 'Nuovo movimento';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accounts = ref.watch(accountsProvider).asData?.value ?? const [];
    final balances = ref.watch(accountBalancesProvider).asData?.value ?? const {};
    final categories = (ref.watch(categoriesProvider).asData?.value ?? const [])
        .where((c) => c.type == _txType)
        .toList();
    ref.watch(mealVoucherAccountProvider);
    final voucherValue = ref.watch(mealVoucherValueProvider);
    // Debiti da proporre: quelli da estinguere più quello già collegato.
    final debts = (ref.watch(debtsProvider).asData?.value ?? const [])
        .where((d) => !d.isPaidOff || d.id == _debtId)
        .toList();
    final voucherAccount = _voucherAccount;
    final effectiveAccountId = _effectiveAccountId(accounts);
    // Il saldo dei buoni, con quelli già usati da questa spesa restituiti.
    final voucherAvailable = voucherAccount == null
        ? 0
        : (balances[voucherAccount.id] ?? voucherAccount.initialBalanceCents) +
            (_tx?.voucherAccount?.id == voucherAccount.id
                ? _tx!.voucherCents
                : 0);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterday = todayDate.subtract(const Duration(days: 1));

    final kinds = [
      if (_transfer == null) ...[MovementKind.expense, MovementKind.income],
      if (_isNew || _transfer != null) MovementKind.transfer,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Elimina',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          PageContainer(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (kinds.length > 1) ...[
                  _KindToggle(kinds: kinds, value: _kind, onChanged: _setKind),
                  const SizedBox(height: 24),
                ],

                // Importo
                _AmountCard(
                  controller: _amount,
                  color: _kindColor,
                  autofocus: _isNew,
                  error: _amountError,
                  // Anche la ripartizione con i buoni dipende dall'importo.
                  onChanged: () => setState(() {
                    _amountError = null;
                    _voucherError = null;
                  }),
                ),
                const SizedBox(height: 24),

                if (_isTransfer)
                  ..._transferSection(accounts, balances)
                else ...[
                  // Conto
                  SectionLabel(
                    'Conto',
                    error: _accountError ? 'Scegli il conto' : null,
                  ),
                  AccountPicker(
                    accounts: accounts,
                    balances: balances,
                    selectedId: effectiveAccountId,
                    onSelected: (id) => setState(() {
                      _accountId = id;
                      _accountError = false;
                      _voucherError = null;
                    }),
                    onCreate: () async {
                      final id = await _newAccount();
                      if (id != null) setState(() => _accountId = id);
                    },
                  ),
                  if (_showVouchers(effectiveAccountId)) ...[
                    const SizedBox(height: 12),
                    VoucherPaymentSection(
                      voucherAccount: voucherAccount!,
                      otherAccount: accounts
                          .where((a) => a.id == effectiveAccountId)
                          .firstOrNull,
                      valueCents: voucherValue,
                      availableCents: voucherAvailable,
                      amountCents: parseAmountToCents(_amount.text),
                      enabled: _useVouchers,
                      voucherCents: _voucherCents,
                      error: _voucherError,
                      onEnabledChanged: (v) =>
                          _setUseVouchers(v, voucherAvailable),
                      onVoucherCentsChanged: (c) => setState(() {
                        _voucherCents = c;
                        _voucherError = null;
                      }),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // Categoria
                  SectionLabel(
                    'Categoria',
                    error: _categoryError ? 'Scegli una categoria' : null,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 12,
                    children: [
                      for (final c in categories)
                        _CategoryChoice(
                          category: c,
                          selected: c.id == _categoryId,
                          onTap: () => setState(() {
                            _categoryId = c.id;
                            _categoryError = false;
                          }),
                        ),
                      _NewChoice(label: 'Nuova', onTap: _newCategory),
                    ],
                  ),
                  if (_kind == MovementKind.expense && debts.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const SectionLabel('Pagamento di un debito'),
                    DebtPicker(
                      debts: debts,
                      selectedId: _debtId,
                      onSelected: (id) =>
                          setState(() => _selectDebt(debts, id)),
                      onCreate: () async {
                        final id = await showDebtEditor(context);
                        if (id == null || !mounted) return;
                        // Il nuovo debito arriva dal database poco dopo.
                        final all =
                            await ref.read(debtsProvider.future);
                        if (mounted) setState(() => _selectDebt(all, id));
                      },
                    ),
                    ?_debtHint(debts),
                  ],
                ],
                const SizedBox(height: 24),

                // Data
                const SectionLabel('Data'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Oggi'),
                      selected: _date == todayDate,
                      onSelected: (_) => setState(() => _date = todayDate),
                    ),
                    ChoiceChip(
                      label: const Text('Ieri'),
                      selected: _date == yesterday,
                      onSelected: (_) => setState(() => _date = yesterday),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.calendar_month_rounded, size: 18),
                      label: Text(
                        _date == todayDate || _date == yesterday
                            ? 'Altra data'
                            : '${formatWeekday(_date)} ${formatDate(_date)}',
                      ),
                      onPressed: _pickDate,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Nota
                const SectionLabel('Descrizione'),
                TextField(
                  controller: _note,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: switch (_kind) {
                      MovementKind.income => 'Es. Stipendio di novembre',
                      MovementKind.expense => 'Es. Spesa al supermercato',
                      MovementKind.transfer => 'Es. Accantonamento mensile',
                    },
                    prefixIcon: const Icon(Icons.notes_rounded),
                    counterText: '',
                  ),
                  onSubmitted: (_) => _save(accounts),
                ),
                if (_isTransfer)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Un trasferimento sposta denaro tra i tuoi conti: non conta '
                      'né come entrata né come spesa nei report.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: PageContainer(
            maxWidth: 640,
            child: GradientButton(
              label: _isNew
                  ? (_isTransfer ? 'Salva trasferimento' : 'Salva movimento')
                  : 'Salva modifiche',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: () => _save(accounts),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _transferSection(
    List<AccountEntity> accounts,
    Map<int, int> balances,
  ) {
    final theme = Theme.of(context);
    if (accounts.length < 2) {
      return [
        AppCard(
          color: AppColors.transfer.withValues(alpha: 0.06),
          child: EmptyState(
            icon: Icons.swap_horiz_rounded,
            title: 'Servono almeno due conti',
            message: 'Per spostare denaro crea un altro conto, ad esempio '
                '"Contanti" o "Risparmi".',
            actions: [
              FilledButton.icon(
                onPressed: () async {
                  final id = await _newAccount();
                  if (id != null && _fromId != id) setState(() => _toId = id);
                },
                icon: const Icon(Icons.add_rounded),
                label: const Text('Crea un conto'),
              ),
            ],
          ),
        ),
      ];
    }

    void select({int? from, int? to}) => setState(() {
          _transferError = null;
          if (from != null) {
            if (from == _toId) _toId = _fromId; // scambio automatico
            _fromId = from;
          }
          if (to != null) {
            if (to == _fromId) _fromId = _toId;
            _toId = to;
          }
        });

    final fromName = accounts.where((a) => a.id == _fromId).firstOrNull?.name;
    final toName = accounts.where((a) => a.id == _toId).firstOrNull?.name;

    return [
      const SectionLabel('Da'),
      AccountPicker(
        accounts: accounts,
        balances: balances,
        selectedId: _fromId,
        onSelected: (id) => select(from: id),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            const Expanded(child: Divider()),
            IconButton.filledTonal(
              tooltip: 'Inverti',
              onPressed: () => setState(() {
                final f = _fromId;
                _fromId = _toId;
                _toId = f;
              }),
              icon: const Icon(Icons.swap_vert_rounded),
            ),
            const Expanded(child: Divider()),
          ],
        ),
      ),
      const SectionLabel('A'),
      AccountPicker(
        accounts: accounts,
        balances: balances,
        selectedId: _toId,
        onSelected: (id) => select(to: id),
        onCreate: () async {
          final id = await _newAccount();
          if (id != null) select(to: id);
        },
      ),
      if (_transferError != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            _transferError!,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.expense),
          ),
        )
      else if (fromName != null && toName != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              const Icon(Icons.east_rounded, size: 18, color: AppColors.transfer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Da $fromName a $toName',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.transfer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.error});

  final String text;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (error != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.expense),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({
    required this.controller,
    required this.color,
    required this.autofocus,
    required this.error,
    required this.onChanged,
  });

  final TextEditingController controller;
  final Color color;
  final bool autofocus;
  final String? error;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        children: [
          Text(
            'Importo',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '€',
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120, maxWidth: 360),
                child: IntrinsicWidth(
                  child: TextField(
                    controller: controller,
                    autofocus: autofocus,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_AmountInputFormatter()],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                    decoration: InputDecoration(
                      hintText: '0,00',
                      hintStyle: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color.withValues(alpha: 0.3),
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => onChanged(),
                  ),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                error!,
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.expense),
              ),
            ),
        ],
      ),
    );
  }
}

/// Interruttore animato Spesa / Entrata / Trasferimento.
class _KindToggle extends StatelessWidget {
  const _KindToggle({
    required this.kinds,
    required this.value,
    required this.onChanged,
  });

  final List<MovementKind> kinds;
  final MovementKind value;
  final ValueChanged<MovementKind> onChanged;

  static Color _color(MovementKind k) => switch (k) {
        MovementKind.expense => AppColors.expense,
        MovementKind.income => AppColors.income,
        MovementKind.transfer => AppColors.transfer,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = kinds.indexOf(value).clamp(0, kinds.length - 1);
    final n = kinds.length;
    return Container(
      height: 54,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                decoration: BoxDecoration(
                  color: _color(value),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _color(value).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final k in kinds) _segment(context, k),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, MovementKind kind) {
    final selected = value == kind;
    final color =
        selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant;
    final (label, icon) = switch (kind) {
      MovementKind.expense => ('Spesa', Icons.arrow_downward_rounded),
      MovementKind.income => ('Entrata', Icons.arrow_upward_rounded),
      MovementKind.transfer => ('Trasferimento', Icons.swap_horiz_rounded),
    };
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(kind),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Scelta del conto: una "pillola" per conto con il saldo attuale.
class AccountPicker extends StatelessWidget {
  const AccountPicker({
    super.key,
    required this.accounts,
    required this.balances,
    required this.selectedId,
    required this.onSelected,
    this.onCreate,
  });

  final List<AccountEntity> accounts;
  final Map<int, int> balances;
  final int? selectedId;
  final ValueChanged<int> onSelected;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in accounts)
          InkWell(
            onTap: () => onSelected(a.id),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
              decoration: BoxDecoration(
                color: a.id == selectedId
                    ? Color(a.color).withValues(alpha: 0.12)
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: a.id == selectedId ? Color(a.color) : Colors.transparent,
                  width: 1.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CategoryAvatar.account(a, size: 34),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        a.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: a.id == selectedId
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                      SensitiveAmount(
                        cents: balances[a.id] ?? a.initialBalanceCents,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (onCreate != null)
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
                  Icon(Icons.add_rounded, size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text('Nuovo conto', style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CategoryChoice extends StatelessWidget {
  const _CategoryChoice({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final CategoryEntity category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Color(category.color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 96,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.6,
          ),
        ),
        child: Column(
          children: [
            CategoryAvatar.of(category, size: 46),
            const SizedBox(height: 6),
            Text(
              category.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewChoice extends StatelessWidget {
  const _NewChoice({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 96,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: scheme.outline, width: 1.2),
                ),
                child: Icon(Icons.add_rounded, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Accetta solo cifre e un separatore decimale (virgola o punto) con al
/// massimo due decimali.
class _AmountInputFormatter extends TextInputFormatter {
  static final _valid = RegExp(r'^\d{0,9}([.,]\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) =>
      _valid.hasMatch(newValue.text) ? newValue : oldValue;
}
