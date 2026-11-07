import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/category_style.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import 'delete_account_flow.dart';

/// Apre l'editor di conto. Restituisce l'id del conto salvato.
Future<int?> showAccountEditor(BuildContext context, {AccountEntity? existing}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => AccountEditorSheet(existing: existing),
    );

class AccountEditorSheet extends ConsumerStatefulWidget {
  const AccountEditorSheet({super.key, this.existing});

  final AccountEntity? existing;

  @override
  ConsumerState<AccountEditorSheet> createState() => _AccountEditorSheetState();
}

class _AccountEditorSheetState extends ConsumerState<AccountEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _initial;
  late String _iconKey;
  late int _color;
  String? _nameError;
  String? _initialError;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    final initial = e?.initialBalanceCents ?? 0;
    _initial = TextEditingController(
      text: initial == 0 && _isNew
          ? ''
          : '${initial < 0 ? '-' : ''}${centsToInput(initial.abs())}',
    );
    _iconKey = e?.iconKey ?? 'wallet';
    _color = e?.color ?? kCategoryColors.first.toARGB32();
  }

  @override
  void dispose() {
    _name.dispose();
    _initial.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final initialText = _initial.text.trim();
    final initial = initialText.isEmpty ? 0 : parseSignedAmountToCents(initialText);
    final all = ref.read(accountsProvider).asData?.value ?? const [];
    final duplicate = all.any(
      (a) =>
          a.id != widget.existing?.id &&
          a.name.toLowerCase() == name.toLowerCase(),
    );
    setState(() {
      _nameError = name.isEmpty
          ? 'Dai un titolo al conto'
          : duplicate
              ? 'Esiste già un conto con questo nome'
              : null;
      _initialError = initial == null ? 'Importo non valido' : null;
    });
    if (_nameError != null || initial == null) return;

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    final int id;
    if (_isNew) {
      id = await db.createAccount(
        name: name,
        iconKey: _iconKey,
        color: _color,
        initialBalanceCents: initial,
      );
    } else {
      id = widget.existing!.id;
      await db.updateAccount(
        widget.existing!.copyWith(
          name: name,
          iconKey: _iconKey,
          color: _color,
          initialBalanceCents: initial,
        ),
      );
    }
    navigator.pop(id);
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final deleted = await deleteAccountFlow(context, ref, widget.existing!);
    if (deleted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(_color);
    final balance = widget.existing == null
        ? null
        : ref.watch(accountBalancesProvider).asData?.value[widget.existing!.id];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isNew ? 'Nuovo conto' : 'Modifica conto',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),

            // Anteprima
            Center(
              child: Column(
                children: [
                  CategoryAvatar.icon(
                    icon: accountIcon(_iconKey),
                    color: color,
                    size: 76,
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder(
                    valueListenable: _name,
                    builder: (context, value, _) => Text(
                      value.text.trim().isEmpty ? 'Anteprima' : value.text.trim(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: value.text.trim().isEmpty
                            ? scheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                  if (balance != null)
                    Text(
                      'Saldo attuale ${formatMoney(balance)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: balance < 0
                            ? AppColors.expense
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const _Label('Titolo'),
            TextField(
              controller: _name,
              autofocus: _isNew,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Es. Conto corrente, Contanti, Carta di credito',
                errorText: _nameError,
                counterText: '',
              ),
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
            ),
            const SizedBox(height: 16),

            const _Label('Saldo iniziale'),
            TextField(
              controller: _initial,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              inputFormatters: [
                TextInputFormatter.withFunction(
                  (oldValue, newValue) =>
                      RegExp(r'^-?\d{0,9}([.,]\d{0,2})?$').hasMatch(newValue.text)
                          ? newValue
                          : oldValue,
                ),
              ],
              decoration: InputDecoration(
                hintText: '0,00',
                prefixText: '€ ',
                errorText: _initialError,
                helperText: _isNew
                    ? 'Quanto c\'è oggi sul conto. Usa il segno meno per una carta di credito o un debito.'
                    : 'Il saldo del conto prima di tutti i movimenti registrati.',
                helperMaxLines: 2,
              ),
              onChanged: (_) {
                if (_initialError != null) setState(() => _initialError = null);
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
                for (final entry in kAccountIcons.entries)
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
              label: _isNew ? 'Crea conto' : 'Salva modifiche',
              icon: Icons.check_rounded,
              loading: _saving,
              onPressed: _save,
            ),
            if (!_isNew) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _delete,
                style: TextButton.styleFrom(foregroundColor: AppColors.expense),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Elimina conto'),
              ),
            ],
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
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}
