import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/category_style.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';

/// Apre l'editor di un debito. Restituisce l'id del debito salvato.
Future<int?> showDebtEditor(BuildContext context, {DebtEntity? existing}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => DebtEditorSheet(existing: existing),
    );

class DebtEditorSheet extends ConsumerStatefulWidget {
  const DebtEditorSheet({super.key, this.existing});

  final DebtEntity? existing;

  @override
  ConsumerState<DebtEditorSheet> createState() => _DebtEditorSheetState();
}

class _DebtEditorSheetState extends ConsumerState<DebtEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _installment;
  late final TextEditingController _count;
  late final TextEditingController _paidBefore;
  late DebtKind _kind;
  late String _iconKey;
  late int _color;
  String? _nameError;
  String? _amountError;
  String? _installmentError;
  String? _countError;
  String? _paidBeforeError;
  bool _saving = false;

  bool get _isNew => widget.existing == null;
  bool get _isInstallments => _kind == DebtKind.installments;

  static final _moneyFormatter = TextInputFormatter.withFunction(
    (oldValue, newValue) =>
        RegExp(r'^\d{0,9}([.,]\d{0,2})?$').hasMatch(newValue.text)
        ? newValue
        : oldValue,
  );
  static final _countFormatter = FilteringTextInputFormatter.digitsOnly;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _kind = e?.kind ?? DebtKind.amount;
    final installments = e != null && e.kind == DebtKind.installments;
    final prior = installments
        ? (e.installmentCents ?? 0) * e.paidInstallments
        : 0;
    _name = TextEditingController(text: e?.name ?? '');
    // Passando da "a rate" a "importo totale" si parte da quanto restava.
    _amount = TextEditingController(
      text: e == null ? '' : centsToInput(e.amountCents - prior),
    );
    _installment = TextEditingController(
      text: e?.installmentCents == null ? '' : centsToInput(e!.installmentCents!),
    );
    _count = TextEditingController(text: e?.installmentCount?.toString() ?? '');
    _paidBefore = TextEditingController(
      text: installments ? '${e.paidInstallments}' : '0',
    );
    _iconKey = e?.iconKey ?? 'loan';
    _color = e?.color ?? 0xFFF43F5E;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _installment.dispose();
    _count.dispose();
    _paidBefore.dispose();
    super.dispose();
  }

  int? get _countValue => int.tryParse(_count.text.trim());
  int get _paidBeforeValue => int.tryParse(_paidBefore.text.trim()) ?? 0;

  Future<void> _save() async {
    final name = _name.text.trim();
    final amount = parseAmountToCents(_amount.text);
    final installment = parseAmountToCents(_installment.text);
    final count = _countValue;
    final paidBefore = _paidBeforeValue;
    setState(() {
      _nameError = name.isEmpty ? 'Dai un nome al debito' : null;
      if (_isInstallments) {
        _amountError = null;
        _installmentError = installment == null || installment <= 0
            ? 'Inserisci l\'importo della rata'
            : null;
        _countError = count == null || count < 1
            ? 'Inserisci quante rate sono in tutto'
            : null;
        _paidBeforeError = count != null && paidBefore > count
            ? 'Non possono essere più delle rate totali'
            : null;
      } else {
        _amountError = amount == null || amount <= 0
            ? 'Inserisci un importo maggiore di zero'
            : null;
        _installmentError = _countError = _paidBeforeError = null;
      }
    });
    if (_nameError != null ||
        _amountError != null ||
        _installmentError != null ||
        _countError != null ||
        _paidBeforeError != null) {
      return;
    }

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    final int id;
    if (_isNew) {
      id = await db.createDebt(
        name: name,
        amountCents: _isInstallments ? 0 : amount!,
        iconKey: _iconKey,
        color: _color,
        kind: _kind,
        installmentCents: _isInstallments ? installment : null,
        installmentCount: _isInstallments ? count : null,
        paidInstallments: _isInstallments ? paidBefore : 0,
      );
    } else {
      id = widget.existing!.id;
      await db.updateDebt(
        widget.existing!.copyWith(
          name: name,
          amountCents: _isInstallments ? 0 : amount,
          iconKey: _iconKey,
          color: _color,
          kind: _kind,
          installmentCents: Value(_isInstallments ? installment : null),
          installmentCount: Value(_isInstallments ? count : null),
          paidInstallments: _isInstallments ? paidBefore : 0,
        ),
      );
    }
    navigator.pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(_color);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isNew ? 'Nuovo debito' : 'Modifica debito',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  CategoryAvatar.icon(
                    icon: debtIcon(_iconKey),
                    color: color,
                    size: 76,
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder(
                    valueListenable: _name,
                    builder: (context, value, _) => Text(
                      value.text.trim().isEmpty
                          ? 'Anteprima'
                          : value.text.trim(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: value.text.trim().isEmpty
                            ? scheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SegmentedButton<DebtKind>(
              segments: const [
                ButtonSegment(
                  value: DebtKind.amount,
                  label: Text('Importo totale'),
                  icon: Icon(Icons.payments_rounded),
                ),
                ButtonSegment(
                  value: DebtKind.installments,
                  label: Text('A rate'),
                  icon: Icon(Icons.calendar_month_rounded),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 10),
            Text(
              _isInstallments
                  ? 'Per prestiti e finanziamenti: indichi la rata, quante '
                        'sono e quante ne hai già pagate. Ogni spesa '
                        'collegata paga le rate successive. Gli interessi '
                        'non si calcolano: il totale è rata × numero di rate.'
                  : 'Per gli acquisti divisi in poche rate, come PayPal in '
                        '3 rate o Klarna, o per soldi da restituire a '
                        'qualcuno: indichi il totale e ogni spesa collegata '
                        'lo riduce.',
              style: muted,
            ),
            const SizedBox(height: 20),
            const _Label('Nome'),
            TextField(
              controller: _name,
              autofocus: _isNew,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _isInstallments
                    ? 'Es. Prestito auto, Mutuo, Finanziamento divano'
                    : 'Es. PayPal in 3 rate, Klarna, Soldi da Marco',
                errorText: _nameError,
                counterText: '',
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 16),
            if (_isInstallments) ...[
              const _Label('Importo della rata'),
              TextField(
                controller: _installment,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_moneyFormatter],
                decoration: InputDecoration(
                  hintText: '0,00',
                  prefixText: '€ ',
                  errorText: _installmentError,
                ),
                onChanged: (_) => setState(() => _installmentError = null),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('Numero di rate'),
                        TextField(
                          controller: _count,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            _countFormatter,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          decoration: InputDecoration(
                            hintText: 'Es. 60',
                            errorText: _countError,
                            errorMaxLines: 2,
                          ),
                          onChanged: (_) => setState(() {
                            _countError = null;
                            _paidBeforeError = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('Rate già pagate'),
                        TextField(
                          controller: _paidBefore,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            _countFormatter,
                            LengthLimitingTextInputFormatter(3),
                          ],
                          decoration: InputDecoration(
                            hintText: '0',
                            errorText: _paidBeforeError,
                            errorMaxLines: 2,
                          ),
                          onChanged: (_) =>
                              setState(() => _paidBeforeError = null),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Le rate già pagate sono quelle saldate prima di '
                'registrarle qui: contano come restituite.',
                style: muted,
              ),
              _InstallmentsPreview(
                installmentCents: parseAmountToCents(_installment.text),
                count: _countValue,
                paidBefore: _paidBeforeValue,
              ),
            ] else ...[
              const _Label('Importo da restituire'),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_moneyFormatter],
                decoration: InputDecoration(
                  hintText: '0,00',
                  prefixText: '€ ',
                  errorText: _amountError,
                  helperText:
                      'Quanto devi restituire in tutto. Ogni spesa che '
                      'colleghi al debito lo riduce, fino a estinguerlo.',
                  helperMaxLines: 2,
                ),
                onChanged: (_) {
                  if (_amountError != null) {
                    setState(() => _amountError = null);
                  }
                },
              ),
            ],
            const SizedBox(height: 20),
            const _Label('Colore'),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in kCategoryColors)
                  ColorDot(
                    color: c,
                    selected: c.toARGB32() == _color,
                    onTap: () => setState(() => _color = c.toARGB32()),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const _Label('Icona'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in kDebtIcons.entries)
                  IconOption(
                    icon: entry.value,
                    color: color,
                    selected: entry.key == _iconKey,
                    onTap: () => setState(() => _iconKey = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            GradientButton(
              label: _isNew ? 'Crea debito' : 'Salva modifiche',
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

/// Riepilogo di un debito a rate mentre lo si compila.
class _InstallmentsPreview extends StatelessWidget {
  const _InstallmentsPreview({
    required this.installmentCents,
    required this.count,
    required this.paidBefore,
  });

  final int? installmentCents;
  final int? count;
  final int paidBefore;

  @override
  Widget build(BuildContext context) {
    final rate = installmentCents;
    final n = count;
    if (rate == null || rate <= 0 || n == null || n < 1 || paidBefore > n) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final left = n - paidBefore;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          left == 0
              ? 'Totale ${formatMoney(rate * n)}: tutte le $n rate sono già '
                    'pagate, il debito risulterà estinto.'
              : 'Totale ${formatMoney(rate * n)}'
                    '${paidBefore > 0 ? ', già pagati ${formatMoney(rate * paidBefore)}' : ''}'
                    '. Restano ${formatMoney(rate * left)} in '
                    '${left == 1 ? '1 rata' : '$left rate'}.',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
