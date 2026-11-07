import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/category_style.dart';
import '../../data/app_database.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';
import '../../widgets/common.dart';
import 'delete_category_flow.dart';

/// Apre l'editor di categoria. Restituisce l'id della categoria salvata.
Future<int?> showCategoryEditor(
  BuildContext context, {
  CategoryEntity? existing,
  TxType initialType = TxType.expense,
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => CategoryEditorSheet(
        existing: existing,
        initialType: existing?.type ?? initialType,
      ),
    );

class CategoryEditorSheet extends ConsumerStatefulWidget {
  const CategoryEditorSheet({
    super.key,
    this.existing,
    this.initialType = TxType.expense,
  });

  final CategoryEntity? existing;
  final TxType initialType;

  @override
  ConsumerState<CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<CategoryEditorSheet> {
  late final TextEditingController _name;
  late TxType _type;
  late String _iconKey;
  late int _color;
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _type = widget.initialType;
    _iconKey = e?.iconKey ?? 'other';
    _color = e?.color ??
        (_type == TxType.income
            ? const Color(0xFF10B981).toARGB32()
            : kCategoryColors.first.toARGB32());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Dai un nome alla categoria');
      return;
    }
    final all = ref.read(categoriesProvider).asData?.value ?? const [];
    final duplicate = all.any(
      (c) =>
          c.type == _type &&
          c.id != widget.existing?.id &&
          c.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      setState(() => _error = 'Esiste già una categoria con questo nome');
      return;
    }

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    final navigator = Navigator.of(context);
    final int id;
    if (_isNew) {
      id = await db.createCategory(
        name: name,
        type: _type,
        iconKey: _iconKey,
        color: _color,
      );
    } else {
      id = widget.existing!.id;
      await db.updateCategory(
        widget.existing!.copyWith(name: name, iconKey: _iconKey, color: _color),
      );
    }
    navigator.pop(id);
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final deleted = await deleteCategoryFlow(context, ref, widget.existing!);
    if (deleted) navigator.pop();
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
              _isNew ? 'Nuova categoria' : 'Modifica categoria',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),

            // Anteprima
            Center(
              child: Column(
                children: [
                  CategoryAvatar(iconKey: _iconKey, color: color, size: 76),
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
                hintText: 'Es. Palestra',
                errorText: _error,
                counterText: '',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),

            if (_isNew) ...[
              SegmentedButton<TxType>(
                segments: const [
                  ButtonSegment(
                    value: TxType.expense,
                    label: Text('Spesa'),
                    icon: Icon(Icons.arrow_downward_rounded),
                  ),
                  ButtonSegment(
                    value: TxType.income,
                    label: Text('Entrata'),
                    icon: Icon(Icons.arrow_upward_rounded),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 20),
            ],

            _Label('Colore'),
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

            _Label('Icona'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in kCategoryIcons.entries)
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
              label: _isNew ? 'Crea categoria' : 'Salva modifiche',
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
                label: const Text('Elimina categoria'),
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

