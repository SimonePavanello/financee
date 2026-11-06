import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/app_database.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';

/// Elimina una categoria. Se ha movimenti chiede in quale categoria
/// spostarli, così nessun dato va perso. Restituisce `true` se eliminata.
Future<bool> deleteCategoryFlow(
  BuildContext context,
  WidgetRef ref,
  CategoryEntity category,
) async {
  final db = ref.read(databaseProvider);
  final count = await db.countTransactionsForCategory(category.id);
  if (!context.mounted) return false;

  if (count == 0) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminare "${category.name}"?'),
        content: const Text('La categoria non ha movimenti associati.'),
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
    if (ok != true) return false;
    await db.deleteCategory(category.id);
    return true;
  }

  final all = await db.getCategories();
  final targets = all
      .where((c) => c.type == category.type && c.id != category.id)
      .toList();
  if (!context.mounted) return false;

  if (targets.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Impossibile eliminare'),
        content: Text(
          '"${category.name}" ha $count movimenti e non esiste un\'altra '
          'categoria di ${category.type == TxType.income ? 'entrate' : 'spese'} '
          'in cui spostarli. Creane una e riprova.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ho capito'),
          ),
        ],
      ),
    );
    return false;
  }

  final targetId = await showDialog<int>(
    context: context,
    builder: (_) => _ReassignDialog(
      category: category,
      count: count,
      targets: targets,
    ),
  );
  if (targetId == null) return false;
  await db.deleteCategory(category.id, moveTransactionsTo: targetId);
  return true;
}

class _ReassignDialog extends StatefulWidget {
  const _ReassignDialog({
    required this.category,
    required this.count,
    required this.targets,
  });

  final CategoryEntity category;
  final int count;
  final List<CategoryEntity> targets;

  @override
  State<_ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<_ReassignDialog> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.count;
    return AlertDialog(
      title: Text('Eliminare "${widget.category.name}"?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              n == 1
                  ? 'C\'è 1 movimento in questa categoria. Scegli dove spostarlo:'
                  : 'Ci sono $n movimenti in questa categoria. Scegli dove spostarli:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in widget.targets)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: CategoryAvatar.of(c, size: 36),
                      title: Text(c.name),
                      selected: _selected == c.id,
                      trailing: _selected == c.id
                          ? Icon(Icons.check_circle_rounded,
                              color: theme.colorScheme.primary)
                          : null,
                      onTap: () => setState(() => _selected = c.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
          onPressed:
              _selected == null ? null : () => Navigator.pop(context, _selected),
          child: const Text('Sposta ed elimina'),
        ),
      ],
    );
  }
}
