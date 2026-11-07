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
  late String _iconKey;
  late int _color;
  String? _nameError;
  String? _amountError;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _amount = TextEditingController(
      text: e == null ? '' : centsToInput(e.amountCents),
    );
    _iconKey = e?.iconKey ?? 'loan';
    _color = e?.color ?? 0xFFF43F5E;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final cents = parseAmountToCents(_amount.text);
    setState(() {
      _nameError = name.isEmpty ? 'Dai un nome al debito' : null;
      _amountError = cents == null || cents <= 0
          ? 'Inserisci un importo maggiore di zero'
          : null;
    });
    if (_nameError != null || _amountError != null) return;

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    final int id;
    if (_isNew) {
      id = await db.createDebt(
        name: name,
        amountCents: cents!,
        iconKey: _iconKey,
        color: _color,
      );
    } else {
      id = widget.existing!.id;
      await db.updateDebt(
        widget.existing!.copyWith(
          name: name,
          amountCents: cents,
          iconKey: _iconKey,
          color: _color,
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
            const _Label('Nome'),
            TextField(
              controller: _name,
              autofocus: _isNew,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Es. Prestito auto, Soldi da Marco, Rate telefono',
                errorText: _nameError,
                counterText: '',
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 16),
            const _Label('Importo da restituire'),
            TextField(
              controller: _amount,
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
                errorText: _amountError,
                helperText:
                    'Quanto devi restituire in tutto. Ogni spesa che '
                    'colleghi al debito lo riduce, fino a estinguerlo.',
                helperMaxLines: 2,
              ),
              onChanged: (_) {
                if (_amountError != null) setState(() => _amountError = null);
              },
            ),
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
