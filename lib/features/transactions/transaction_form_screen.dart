import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import '../categories/category_editor_sheet.dart';

/// Apre il form. Restituisce `true` se il movimento è stato salvato.
Future<bool?> openTransactionForm(
  BuildContext context, {
  TransactionWithCategory? existing,
  TxType initialType = TxType.expense,
}) =>
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TransactionFormScreen(
          existing: existing,
          initialType: initialType,
        ),
      ),
    );

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.existing,
    this.initialType = TxType.expense,
  });

  final TransactionWithCategory? existing;
  final TxType initialType;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  late TxType _type;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _date;
  int? _categoryId;
  String? _amountError;
  bool _categoryError = false;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.tx.type ?? widget.initialType;
    _amount = TextEditingController(
      text: e == null ? '' : centsToInput(e.tx.amountCents),
    );
    _note = TextEditingController(text: e?.tx.note ?? '');
    final now = DateTime.now();
    _date = e?.tx.date ?? DateTime(now.year, now.month, now.day);
    _categoryId = e?.category.id;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setType(TxType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _categoryId = null;
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
    final id = await showCategoryEditor(context, initialType: _type);
    if (id != null) {
      setState(() {
        _categoryId = id;
        _categoryError = false;
      });
    }
  }

  Future<void> _save() async {
    final cents = parseAmountToCents(_amount.text);
    final amountInvalid = cents == null || cents <= 0;
    setState(() {
      _amountError = amountInvalid ? 'Inserisci un importo maggiore di zero' : null;
      _categoryError = _categoryId == null;
    });
    if (amountInvalid || _categoryId == null) return;

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    final note = _note.text.trim();
    if (_isNew) {
      await db.addTransaction(
        type: _type,
        amountCents: cents,
        categoryId: _categoryId!,
        date: _date,
        note: note,
      );
    } else {
      await db.updateTransaction(
        widget.existing!.tx.copyWith(
          type: _type,
          amountCents: cents,
          categoryId: _categoryId,
          date: _date,
          note: note,
        ),
      );
    }
    navigator.pop(true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare il movimento?'),
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
    await ref.read(databaseProvider).deleteTransaction(widget.existing!.tx.id);
    navigator.pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final typeColor = AppColors.forIncome(_type == TxType.income);
    final categories = (ref.watch(categoriesProvider).asData?.value ?? const [])
        .where((c) => c.type == _type)
        .toList();
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final yesterday = todayDate.subtract(const Duration(days: 1));

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Nuovo movimento' : 'Modifica movimento'),
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
                _TypeToggle(value: _type, onChanged: _setType),
                const SizedBox(height: 24),

                // Importo
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  child: Column(
                    children: [
                      Text(
                        'Importo',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '€',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: typeColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints:
                                const BoxConstraints(minWidth: 120, maxWidth: 360),
                            child: IntrinsicWidth(
                              child: TextField(
                                controller: _amount,
                                autofocus: _isNew,
                                keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [_AmountInputFormatter()],
                                textAlign: TextAlign.center,
                                style: theme.textTheme.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: typeColor,
                                ),
                                decoration: InputDecoration(
                                  hintText: '0,00',
                                  hintStyle: theme.textTheme.displaySmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: typeColor.withValues(alpha: 0.3),
                                  ),
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (_) {
                                  if (_amountError != null) {
                                    setState(() => _amountError = null);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_amountError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            _amountError!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.expense),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Categoria
                _SectionLabel(
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
                    _NewCategoryChoice(onTap: _newCategory),
                  ],
                ),
                const SizedBox(height: 24),

                // Data
                const _SectionLabel('Data'),
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
                const _SectionLabel('Descrizione'),
                TextField(
                  controller: _note,
                  maxLength: 120,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _type == TxType.income
                        ? 'Es. Stipendio di novembre'
                        : 'Es. Spesa al supermercato',
                    prefixIcon: const Icon(Icons.notes_rounded),
                    counterText: '',
                  ),
                  onSubmitted: (_) => _save(),
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
              label: _isNew ? 'Salva movimento' : 'Salva modifiche',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.error});

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
            Text(
              error!,
              style: theme.textTheme.bodySmall?.copyWith(color: AppColors.expense),
            ),
          ],
        ],
      ),
    );
  }
}

/// Interruttore animato Spesa / Entrata.
class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.value, required this.onChanged});

  final TxType value;
  final ValueChanged<TxType> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isIncome = value == TxType.income;
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
            alignment: isIncome ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                decoration: BoxDecoration(
                  color: AppColors.forIncome(isIncome),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.forIncome(isIncome).withValues(alpha: 0.35),
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
              _segment(context, 'Spesa', Icons.arrow_downward_rounded,
                  TxType.expense),
              _segment(context, 'Entrata', Icons.arrow_upward_rounded,
                  TxType.income),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    String label,
    IconData icon,
    TxType type,
  ) {
    final selected = value == type;
    final color =
        selected ? Colors.white : Theme.of(context).colorScheme.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(type),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
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

class _NewCategoryChoice extends StatelessWidget {
  const _NewCategoryChoice({required this.onTap});

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
              Text(
                'Nuova',
                style: theme.textTheme.labelMedium,
              ),
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
