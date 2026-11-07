import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/app_database.dart';
import '../../providers.dart';
import '../../widgets/category_widgets.dart';

/// Elimina un conto. Se ha movimenti o un saldo diverso da zero chiede a quale
/// conto unirlo, così nessun dato e nessun euro vanno persi.
/// Restituisce `true` se il conto è stato eliminato.
Future<bool> deleteAccountFlow(
  BuildContext context,
  WidgetRef ref,
  AccountEntity account,
) async {
  final db = ref.read(databaseProvider);
  final all = await db.getAccounts();
  final usage = await db.countAccountUsage(account.id);
  final balance = (await db.watchAccountBalances().first)[account.id] ?? 0;
  if (!context.mounted) return false;

  if (all.length <= 1) {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Impossibile eliminare'),
        content: const Text(
          'Serve almeno un conto su cui registrare i movimenti. '
          'Puoi rinominare questo conto invece di eliminarlo.',
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

  if (usage == 0 && balance == 0) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminare "${account.name}"?'),
        content: const Text('Il conto non ha movimenti e il saldo è zero.'),
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
    await db.deleteAccount(account.id);
    return true;
  }

  final targetId = await showDialog<int>(
    context: context,
    builder: (_) => _MergeDialog(
      account: account,
      usage: usage,
      balance: balance,
      targets: all.where((a) => a.id != account.id).toList(),
    ),
  );
  if (targetId == null) return false;
  await db.deleteAccount(account.id, mergeInto: targetId);
  return true;
}

class _MergeDialog extends StatefulWidget {
  const _MergeDialog({
    required this.account,
    required this.usage,
    required this.balance,
    required this.targets,
  });

  final AccountEntity account;
  final int usage;
  final int balance;
  final List<AccountEntity> targets;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = [
      if (widget.usage > 0) plural(widget.usage, 'movimento', 'movimenti'),
      if (widget.balance != 0) 'il saldo di ${formatMoney(widget.balance)}',
    ];
    return AlertDialog(
      title: Text('Eliminare "${widget.account.name}"?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${capitalize(parts.join(' e '))} verranno uniti al conto che '
              'scegli. Gli eventuali trasferimenti tra i due conti verranno '
              'eliminati perché diventerebbero interni.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in widget.targets)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: CategoryAvatar.account(a, size: 36),
                      title: Text(a.name),
                      selected: _selected == a.id,
                      trailing: _selected == a.id
                          ? Icon(Icons.check_circle_rounded,
                              color: theme.colorScheme.primary)
                          : null,
                      onTap: () => setState(() => _selected = a.id),
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
          child: const Text('Unisci ed elimina'),
        ),
      ],
    );
  }
}
